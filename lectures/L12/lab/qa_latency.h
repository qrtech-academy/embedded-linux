/**
 * @file The record the qa_latency driver delivers, one per interrupt.
 */
#ifndef QA_LATENCY_H
#define QA_LATENCY_H

#include <linux/types.h>

/** Latency record structure. */
struct qa_latency_record
{
    /** The instant the device asserted its interrupt line, on QEMU's virtual clock. */
    __u64 device_ns;

    /** ktime_get_ns() taken as the interrupt handler's first statement, on CLOCK_MONOTONIC. */
    __u64 handler_ns;

    /** Sequence number of this record, so a reader can tell which ones it did not see. */
    __u32 sequence;

    /** Records the driver dropped because the reader was behind. */
    __u32 overruns;
};

#endif /* QA_LATENCY_H */
