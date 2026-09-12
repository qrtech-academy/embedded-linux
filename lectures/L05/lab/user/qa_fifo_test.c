// SPDX-License-Identifier: GPL-2.0-only
/**
 * @file Userspace tester for the qa_fifo character device specified in L05's Appendix B.
 *
 * This ships with the course; you do not write it. It is deliberately a separate program rather
 * than part of the lab's run.sh, because a shell script can only see what a shell can express,
 * and several of the things a character driver has to get right are only visible to a program
 * that can make one system call at a time and look at errno afterwards. A short read, a write
 * that is refused, and the difference between "returned 0" and "returned -EAGAIN" all look the
 * same from a shell pipeline and are entirely different to a program.
 *
 * It is cross-compiled statically by ci/build.sh and copied into /lab on the target.
 *
 * Exit status is the number of failed checks, which is what lab/run.sh reports.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/** The device the driver creates. */
static const char* DEVICE = "/dev/qa_fifo";

/** The word written and read back, to prove the bytes survive the round trip. */
static const char HELLO[] = "hello";

/** Bytes in HELLO, without its terminator. */
#define HELLO_BYTES (sizeof(HELLO) - 1U)

/** The sequence written in one call and read back in two, to prove the order. */
static const char SEQUENCE[] = "abcdef";

/** Bytes in SEQUENCE, without its terminator. */
#define SEQUENCE_BYTES (sizeof(SEQUENCE) - 1U)

/** Bytes taken by each of the two short reads. */
#define SHORT_READ_BYTES 3U

/** Bytes read at a time, which is more than any single write this test makes. */
#define BUFFER_BYTES 64U

/** Bytes written per call while filling the FIFO. */
#define FILL_BYTES 4096U

/** Fill batches after which the test gives up, so a FIFO that never fills cannot hang it. */
#define FILL_LIMIT 64U

/** Failed checks so far, which is also the exit status. */
static int failures = 0;

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
 * @brief Exercise the character device, one system call at a time.
 *
 * @returns The number of failed checks, which is what lab/run.sh reports.
 */
int main(void)
{
    char buffer[BUFFER_BYTES];
    ssize_t n;
    int fd;

    printf("qa_fifo_test: %s\n", DEVICE);

    fd = open(DEVICE, O_RDWR);
    check_errno(0 <= fd, "the device node opens", errno);
    if (0 > fd) { return failures; }

    /* An empty FIFO is not end of file. Returning 0 here is the mistake the whole lecture is
     * about, and it is the one thing a shell cannot tell you: `cat` prints nothing either way. */
    n = read(fd, buffer, sizeof(buffer));
    check_errno((-1 == n) && (EAGAIN == errno), "read on an empty FIFO returns -EAGAIN, not 0",
                errno);

    n = write(fd, HELLO, HELLO_BYTES);
    check_errno((ssize_t)HELLO_BYTES == n, "write of 5 bytes returns 5", errno);

    n = read(fd, buffer, sizeof(buffer));
    check_errno((ssize_t)HELLO_BYTES == n, "read returns the 5 bytes that were written", errno);
    check(((ssize_t)HELLO_BYTES == n) && (0 == memcmp(buffer, HELLO, HELLO_BYTES)),
          "the bytes come back unchanged");

    /* Order matters: a FIFO that returns a set rather than a sequence is not a FIFO. */
    check((ssize_t)SEQUENCE_BYTES == write(fd, SEQUENCE, SEQUENCE_BYTES),
          "write of 6 bytes returns 6");
    n = read(fd, buffer, SHORT_READ_BYTES);
    check(((ssize_t)SHORT_READ_BYTES == n) && (0 == memcmp(buffer, SEQUENCE, SHORT_READ_BYTES)),
          "a short read takes the oldest bytes first");
    n = read(fd, buffer, SHORT_READ_BYTES);
    check(((ssize_t)SHORT_READ_BYTES == n) &&
              (0 == memcmp(buffer, &SEQUENCE[SHORT_READ_BYTES], SHORT_READ_BYTES)),
          "the rest follow in order");

    /* Fill it, and check that the overflow is refused rather than silently dropped. Capacity is
     * a module parameter; the test discovers it rather than assuming it. */
    {
        char big[FILL_BYTES];
        size_t total = 0U;

        memset(big, 'x', sizeof(big));
        for (;;)
        {
            n = write(fd, big, sizeof(big));
            if (0 >= n) { break; }
            total += (size_t)n;
            if ((sizeof(big) * FILL_LIMIT) < total) { break; }
        }
        check_errno((-1 == n) && (ENOSPC == errno), "writing to a full FIFO returns -ENOSPC",
                    errno);
        printf("        capacity measured from userspace: %zu bytes\n", total);

        /* And everything written can be read back, which proves nothing was dropped. */
        {
            size_t drained = 0U;

            for (;;)
            {
                n = read(fd, buffer, sizeof(buffer));
                if (0 >= n) { break; }
                drained += (size_t)n;
            }
            check(drained == total, "everything written can be read back, nothing was dropped");
            printf("        wrote %zu, drained %zu\n", total, drained);
        }
    }

    /* It is a stream, so seeking is meaningless and must be refused rather than ignored. */
    check_errno((((off_t)-1) == lseek(fd, 0, SEEK_SET)) && (ESPIPE == errno),
                "lseek is refused with -ESPIPE", errno);

    close(fd);

    printf("qa_fifo_test: %d failure(s)\n", failures);
    return failures;
}
