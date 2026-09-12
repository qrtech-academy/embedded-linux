// SPDX-License-Identifier: GPL-2.0-only
/**
 * @file Userspace tester for the gpiochip registered in L11's lab.
 *
 * This ships with the course. What makes it worth reading is that it contains nothing specific to
 * this driver: it finds the chip by the label the driver gave it, and then uses the same GPIO
 * character device ABI that libgpiod uses and that every other GPIO driver in the kernel presents.
 * That is the whole argument of the lecture, in a program: implement a framework's interface and
 * tools you did not write can drive your hardware.
 *
 * The device wires its four output lines back to its four input lines, so driving line N low or
 * high should be visible on line N+4. Nothing about a real board works that way; it is there so
 * this test needs no wires.
 */

#include <errno.h>
#include <fcntl.h>
#include <linux/gpio.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

/** Label prefix the driver's chip carries, which is how this test finds it. */
#define CHIP_LABEL "c000000.qa-dev"

/** Name recorded against every line this test requests. */
#define CONSUMER "qa_gpio_test"

/** Chips searched before giving up. */
#define MAX_CHIPS 8U

/** Bytes reserved for a /dev/gpiochipN path. */
#define PATH_BYTES 32U

/** Lines the driver's chip is expected to expose. */
#define EXPECTED_LINES 8U

/** The output line the test drives. */
#define OUTPUT_LINE 0U

/** The input line it is wired back to. */
#define INPUT_LINE 4U

/** Lines per request: this test drives and reads one at a time. */
#define LINES_PER_REQUEST 1U

/** The bit standing for the first, and here only, line of a request. */
#define FIRST_LINE_BIT 1U

/** A line driven high. */
#define LINE_HIGH 1

/** A line driven low. */
#define LINE_LOW 0

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
 * @brief Find the chip whose label starts with the given prefix, rather than assuming a number.
 *
 * The target already has a PL061 at gpiochip0, so this driver's chip is not chip 0, and would not
 * be chip 1 on a board with more of them.
 *
 * @param[in]  prefix Label prefix to look for.
 * @param[out] info   Chip information, as the kernel reports it.
 *
 * @returns An open descriptor for the chip, or -1 if no chip matched.
 */
static int open_chip_by_label(const char* prefix, struct gpiochip_info* info)
{
    char path[PATH_BYTES];
    unsigned int i;

    for (i = 0U; i < MAX_CHIPS; i++)
    {
        int fd;

        snprintf(path, sizeof(path), "/dev/gpiochip%u", i);
        fd = open(path, O_RDWR);
        if (0 > fd) { continue; }

        if ((0 == ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, info)) &&
            (0 == strncmp(info->label, prefix, strlen(prefix))))
        {
            printf("        found %s: label \"%s\", %u lines\n", path, info->label, info->lines);
            return fd;
        }
        close(fd);
    }
    return -1;
}

/**
 * @brief Request one line from the chip.
 *
 * @param[in] chip     Open chip descriptor.
 * @param[in] offset   Line to request.
 * @param[in] flags    Line flags, input or output.
 * @param[in] consumer Name recorded against the line, which gpioinfo prints.
 *
 * @returns The request descriptor, or -1 on failure.
 */
static int request_line(int chip, unsigned int offset, unsigned long flags, const char* consumer)
{
    struct gpio_v2_line_request req;

    memset(&req, 0, sizeof(req));
    req.offsets[0]   = offset;
    req.num_lines    = LINES_PER_REQUEST;
    req.config.flags = flags;
    snprintf(req.consumer, sizeof(req.consumer), "%s", consumer);

    if (0 > ioctl(chip, GPIO_V2_GET_LINE_IOCTL, &req)) { return -1; }
    return req.fd;
}

/**
 * @brief Read the value of a requested line.
 *
 * @param[in]  line_fd Request descriptor.
 * @param[out] value   The line's value, 0 or 1.
 *
 * @returns 0 on success, or -1 on failure.
 */
static int get_value(int line_fd, int* value)
{
    struct gpio_v2_line_values values;

    memset(&values, 0, sizeof(values));
    values.mask = FIRST_LINE_BIT;
    if (0 > ioctl(line_fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &values)) { return -1; }
    *value = (int)(values.bits & FIRST_LINE_BIT);
    return 0;
}

/**
 * @brief Drive a requested line.
 *
 * @param[in] line_fd Request descriptor.
 * @param[in] value   Value to drive, 0 or 1.
 *
 * @returns 0 on success, or -1 on failure.
 */
static int set_value(int line_fd, int value)
{
    struct gpio_v2_line_values values;

    memset(&values, 0, sizeof(values));
    values.mask = FIRST_LINE_BIT;
    values.bits = (LINE_LOW != value) ? FIRST_LINE_BIT : 0U;
    return ioctl(line_fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &values);
}

/**
 * @brief Drive the loopback through the GPIO character device ABI, with no driver-specific code.
 *
 * @returns The number of failed checks.
 */
int main(void)
{
    struct gpiochip_info info;
    int chip, out, in, value;

    printf("qa_gpio_test: looking for the chip by label\n");

    memset(&info, 0, sizeof(info));
    chip = open_chip_by_label(CHIP_LABEL, &info);
    check(0 <= chip, "the driver's gpiochip is present and findable by label");
    if (0 > chip)
    {
        printf("qa_gpio_test: %d failure(s)\n", failures);
        return failures;
    }

    check(EXPECTED_LINES == info.lines, "the chip reports eight lines");

    out = request_line(chip, OUTPUT_LINE, GPIO_V2_LINE_FLAG_OUTPUT, CONSUMER);
    check(0 <= out, "line 0 can be requested as an output");

    in = request_line(chip, INPUT_LINE, GPIO_V2_LINE_FLAG_INPUT, CONSUMER);
    check(0 <= in, "line 4 can be requested as an input");

    if ((0 <= out) && (0 <= in))
    {
        check(0 == set_value(out, LINE_HIGH), "line 0 can be driven high");
        check((0 == get_value(in, &value)) && (LINE_HIGH == value),
              "line 4 reads high, through the loopback");

        check(0 == set_value(out, LINE_LOW), "line 0 can be driven low");
        check((0 == get_value(in, &value)) && (LINE_LOW == value), "line 4 follows it low");
    }

    if (0 <= out) { close(out); }
    if (0 <= in) { close(in); }
    close(chip);

    printf("qa_gpio_test: %d failure(s)\n", failures);
    return failures;
}
