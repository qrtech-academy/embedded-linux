// SPDX-License-Identifier: GPL-2.0-only
/**
 * @file Userspace tester for the blocking driver specified in L09's Appendix C.
 *
 * This ships with the course. It exists as a program rather than as shell because the three
 * things it checks are invisible from a shell: whether a read blocked or returned immediately,
 * whether it returned -EAGAIN or 0, and whether select() reported readiness or timed out. A
 * shell sees "no output" for all six outcomes.
 *
 * Two modes, because the driver has to be tested both with the device producing samples and with
 * it stopped, and stopping it means reloading the module with period_ns=0.
 *
 *   qa_wait_test running    the device is producing samples
 *   qa_wait_test stopped    the device is idle
 *
 * Exit status is the number of failed checks.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/select.h>
#include <sys/time.h>
#include <unistd.h>

/** The device the driver creates. */
static const char* DEVICE = "/dev/qa_wait";

/** Samples read at a time. */
#define BUFFER_SAMPLES 64U

/** Milliseconds in a second. */
#define MS_PER_S 1000L

/** Microseconds in a millisecond. */
#define US_PER_MS 1000L

/** How long select() is given to report a producing device readable. */
#define READY_TIMEOUT_S 1

/** How long select() is given on an idle device, where it must time out instead. */
#define IDLE_TIMEOUT_US 300000

/** Failed checks so far, which is also the exit status. */
static int failures;

/**
 * @brief Report one check, and count it if it failed.
 *
 * @param[in] ok   Non-zero if the check passed.
 * @param[in] what What was checked, printed either way.
 */
static void check(int ok, const char* what)
{
    if (ok) { printf("  ok    %s\n", what); }
    else
    {
        printf("  FAIL  %s\n", what);
        failures++;
    }
}

/**
 * @brief Report one check, naming the errno when it failed.
 *
 * "It failed" is rarely enough to act on, so the value and its message are printed with it.
 *
 * @param[in] ok   Non-zero if the check passed.
 * @param[in] what What was checked, printed either way.
 * @param[in] err  errno, as it was immediately after the call.
 */
static void check_errno(int ok, const char* what, int err)
{
    if (ok) { printf("  ok    %s\n", what); }
    else
    {
        printf("  FAIL  %s (errno %d: %s)\n", what, err, strerror(err));
        failures++;
    }
}

/**
 * @brief Milliseconds since an arbitrary origin, for measuring whether a call actually blocked.
 *
 * @returns The current time in milliseconds.
 */
static long now_ms(void)
{
    struct timeval tv;

    gettimeofday(&tv, NULL);
    return (tv.tv_sec * MS_PER_S) + (tv.tv_usec / US_PER_MS);
}

/**
 * @brief Check the driver while the device is producing samples.
 *
 * @returns The number of failed checks so far.
 */
static int test_running(void)
{
    unsigned int buffer[BUFFER_SAMPLES];
    long start;
    ssize_t n;
    fd_set set;
    int fd;

    fd = open(DEVICE, O_RDONLY);
    check_errno(0 <= fd, "the device opens", errno);
    if (0 > fd) { return failures; }

    /* A blocking read on a device producing a sample every millisecond must return data, and
     * must not return 0. Returning 0 would mean end of file, which is L05's subject. */
    n = read(fd, buffer, sizeof(buffer));
    check_errno(0 < n, "a blocking read returns data rather than 0 or an error", errno);
    printf("        read returned %zd bytes, %zd samples\n", n, n / (ssize_t)sizeof(buffer[0]));

    /* Drain, then read again. The second read has to wait for the interrupt, so it must take
     * about a millisecond rather than returning instantly.
     *
     * Draining needs O_NONBLOCK. On a blocking descriptor attached to a device that produces a
     * sample every millisecond, "read until it stops returning data" never stops: there is
     * always more data a millisecond from now. Toggle the flag with fcntl, drain until -EAGAIN,
     * and toggle it back. */
    {
        int flags = fcntl(fd, F_GETFL, 0);

        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        while (0 < read(fd, buffer, sizeof(buffer))) {}
        fcntl(fd, F_SETFL, flags);
    }
    start = now_ms();
    n     = read(fd, buffer, sizeof(buffer));
    check(0 < n, "a read after draining still returns data");
    printf("        it waited %ld ms for the next sample\n", now_ms() - start);

    /* select() must report the device readable once a sample has arrived. */
    FD_ZERO(&set);
    FD_SET(fd, &set);
    {
        struct timeval timeout = {.tv_sec = READY_TIMEOUT_S, .tv_usec = 0};
        int ready              = select(fd + 1, &set, NULL, NULL, &timeout);

        check_errno(1 == ready, "select reports the device readable within a second", errno);
        check(FD_ISSET(fd, &set), "and it is this descriptor that is ready");
    }

    close(fd);
    return failures;
}

/**
 * @brief Check the driver while the device is idle, where "not now" must not read as "never".
 *
 * @returns The number of failed checks so far.
 */
static int test_stopped(void)
{
    unsigned int buffer[BUFFER_SAMPLES];
    ssize_t n;
    long start;
    fd_set set;
    int fd;

    fd = open(DEVICE, O_RDONLY | O_NONBLOCK);
    check_errno(0 <= fd, "the device opens non-blocking", errno);
    if (0 > fd) { return failures; }

    /* Nothing is producing samples, so a non-blocking read must say "not now" rather than
     * "never again". This is the distinction a shell cannot see. */
    n = read(fd, buffer, sizeof(buffer));
    check_errno((-1 == n) && (EAGAIN == errno),
                "a non-blocking read on an idle device gives -EAGAIN", errno);

    /* And select must time out rather than reporting readiness. */
    FD_ZERO(&set);
    FD_SET(fd, &set);
    start = now_ms();
    {
        struct timeval timeout = {.tv_sec = 0, .tv_usec = IDLE_TIMEOUT_US};
        int ready              = select(fd + 1, &set, NULL, NULL, &timeout);

        check_errno(0 == ready, "select times out on an idle device", errno);
        printf("        it waited %ld ms before giving up\n", now_ms() - start);
    }

    close(fd);
    return failures;
}

/**
 * @brief Run one of the two modes.
 *
 * @param[in] argc Argument count.
 * @param[in] argv Arguments; argv[1] selects "running" (the default) or "stopped".
 *
 * @returns The number of failed checks.
 */
int main(int argc, char** argv)
{
    const char* mode = (1 < argc) ? argv[1] : "running";

    printf("qa_wait_test: %s, mode=%s\n", DEVICE, mode);

    if (0 == strcmp(mode, "stopped")) { test_stopped(); }
    else { test_running(); }

    printf("qa_wait_test: %d failure(s)\n", failures);
    return failures;
}
