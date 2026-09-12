// SPDX-License-Identifier: GPL-2.0-only
/**
 * @file Latency measurement for L12, by subtraction rather than by inference.
 */

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/** The device the driver creates. */
static const char* DEVICE = "/dev/qa_latency";

/** Nanoseconds in a microsecond, which is what every figure is reported in. */
#define NS_PER_US 1000ULL

/** Nanoseconds in a second, for turning a struct timespec into one number. */
#define NS_PER_S 1000000000ULL

/** Records read in one call. More than one in a batch means the reader was already behind. */
#define BATCH_RECORDS 64U

/** Batches thrown away at startup, before the first measurement is kept. */
#define DISCARD_BATCHES 8U

/** Samples collected when the command line does not say. */
#define DEFAULT_SAMPLES 2000UL

/** Histogram buckets, each twice the width of the one below it. */
#define BUCKETS 22U

/** Columns the longest bar in the histogram occupies. */
#define BAR_COLUMNS 40.0

/** Multiplier that turns a fraction into a percentage. */
#define PERCENT 100.0

/** A copy of the record the driver delivers, in types userspace has. Must match qa_latency.h. */
struct qa_latency_record
{
    /** The instant the device asserted its interrupt line, on QEMU's virtual clock. */
    unsigned long long device_ns;

    /** ktime_get_ns() taken as the interrupt handler's first statement, on CLOCK_MONOTONIC. */
    unsigned long long handler_ns;

    /** Sequence number of this record. */
    unsigned int sequence;

    /** Records the driver dropped because the reader was behind. */
    unsigned int overruns;
};

/** How many samples fell into each bucket. */
static unsigned long histogram[BUCKETS];

/**
 * @brief Count one latency into its logarithmic bucket.
 *
 * The buckets double each time: under 1 us, 1-2, 2-4, and so on. Linear microsecond buckets are
 * the obvious choice and are useless here. Idle latency is tens of microseconds and loaded
 * latency runs into seconds, so any linear width either loses the bottom of the distribution or
 * produces ten thousand rows. A latency distribution spans orders of magnitude and wants a log
 * axis, which is how cyclictest histograms are usually read too.
 *
 * @param[in] ns The latency, in nanoseconds.
 */
static void record(unsigned long long ns)
{
    unsigned long long us = ns / NS_PER_US;
    unsigned int bucket   = 0U;

    while ((0ULL < us) && (bucket < (BUCKETS - 1U)))
    {
        us >>= 1U;
        bucket++;
    }
    histogram[bucket]++;
}

/**
 * @brief The inclusive lower edge of a bucket.
 *
 * @param[in] bucket Bucket index.
 *
 * @returns The lower edge, in microseconds.
 */
static unsigned long bucket_floor(unsigned int bucket)
{
    return (0U == bucket) ? 0UL : (1UL << (bucket - 1U));
}

/**
 * @brief Print the histogram, with a cumulative percentage and a bar per bucket.
 *
 * @param[in] total Number of samples recorded.
 */
static void print_histogram(unsigned long total)
{
    unsigned long running = 0UL;
    unsigned int i;

    printf("        %-12s %8s %8s\n", "latency", "count", "cum %");
    for (i = 0U; i < BUCKETS; i++)
    {
        if (0UL == histogram[i]) { continue; }
        running += histogram[i];
        printf("        %s%7lu us %8lu %7.2f%%  ", ((BUCKETS - 1U) == i) ? ">=" : "  ",
               bucket_floor(i), histogram[i], PERCENT * running / total);
        {
            const unsigned int bar = (unsigned int)(BAR_COLUMNS * histogram[i] / total);
            unsigned int j;

            for (j = 0U; j < bar; j++)
            {
                putchar('#');
            }
        }
        putchar('\n');
    }
}

/**
 * @brief Collect records from the driver and report both intervals.
 *
 * @param[in] argc Argument count.
 * @param[in] argv Arguments; argv[1] is the number of samples to collect, DEFAULT_SAMPLES if not.
 *
 * @returns 0, or 1 if the device could not be read.
 */
int main(int argc, char** argv)
{
    struct qa_latency_record batch[BATCH_RECORDS];
    unsigned long long min_offset = ULLONG_MAX;
    unsigned long long max_wake = 0ULL, sum_wake = 0ULL;
    unsigned long long* offsets;
    unsigned long got    = 0UL;
    unsigned long want   = (1 < argc) ? strtoul(argv[1], NULL, 0) : DEFAULT_SAMPLES;
    unsigned int dropped = 0U;
    int fd;

    offsets = calloc(want, sizeof(*offsets));
    if (NULL == offsets) { return 1; }

    fd = open(DEVICE, O_RDONLY);
    if (0 > fd)
    {
        printf("  FAIL  %s: %s\n", DEVICE, strerror(errno));
        free(offsets);
        return 1;
    }

    /* Discard whatever accumulated between the driver enabling the device and this program
     * getting scheduled. Those records really did wait a long time, and they measure process
     * startup rather than interrupt latency. */
    {
        struct qa_latency_record discard[BATCH_RECORDS];
        unsigned int i;

        for (i = 0U; i < DISCARD_BATCHES; i++)
        {
            if (0 >= read(fd, discard, sizeof(discard))) { break; }
        }
    }

    while (got < want)
    {
        struct timespec now;
        ssize_t n;
        unsigned int i, count;

        n = read(fd, batch, sizeof(batch));
        if (0 >= n) { break; }

        /* Taken once per batch, immediately on return, and applied to every record in it. A
         * batch of more than one means the reader was already behind, which is itself a result. */
        clock_gettime(CLOCK_MONOTONIC, &now);
        count = (unsigned int)(n / (ssize_t)sizeof(batch[0]));

        for (i = 0U; (i < count) && (got < want); i++)
        {
            const unsigned long long now_ns =
                ((unsigned long long)now.tv_sec * NS_PER_S) + (unsigned long long)now.tv_nsec;
            const unsigned long long offset = batch[i].handler_ns - batch[i].device_ns;
            unsigned long long wake;

            if (offset < min_offset) { min_offset = offset; }
            offsets[got] = offset;

            wake = (now_ns > batch[i].handler_ns) ? (now_ns - batch[i].handler_ns) : 0ULL;
            if (wake > max_wake) { max_wake = wake; }
            sum_wake += wake;
            record(wake);

            dropped = batch[i].overruns;
            got++;
        }
    }
    close(fd);

    if (0UL == got)
    {
        printf("  FAIL  no samples\n");
        free(offsets);
        return 1;
    }

    printf("  samples: %lu, dropped by the driver: %u\n", got, dropped);

    printf("\n  handler-to-userspace latency, absolute (both ends are CLOCK_MONOTONIC)\n");
    printf("        mean %llu us, max %llu us\n", (sum_wake / got) / NS_PER_US,
           max_wake / NS_PER_US);
    print_histogram(got);

    {
        unsigned long long spread = 0ULL;
        unsigned long i;

        for (i = 0UL; i < got; i++)
        {
            const unsigned long long above = offsets[i] - min_offset;

            if (above > spread) { spread = above; }
        }
        printf("\n  interrupt-to-handler, as a spread above the best case observed\n");
        printf("        worst %llu us above the minimum\n", spread / NS_PER_US);
        printf("        (the absolute value is unknowable here: the two clocks have different\n");
        printf("         origins, and the constant between them cannot be read)\n");
    }

    free(offsets);
    return 0;
}
