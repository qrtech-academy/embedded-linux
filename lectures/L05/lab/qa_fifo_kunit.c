// SPDX-License-Identifier: GPL-2.0-only
/**
 * @file KUnit suite for the qa_fifo ring buffer specified in qa_fifo.h.
 *
 * This file ships with the course; you do not write it and you should not need to change it. It
 * is a separate module from your qa_fifo.c, which means your implementation has to export the
 * functions in qa_fifo.h with EXPORT_SYMBOL_GPL. That is not an artefact of the testing setup;
 * it is the same mechanism L04 built, used for the reason it exists.
 *
 * Run it on the target with:
 *
 *     insmod qa_fifo.ko
 *     insmod qa_fifo_kunit.ko
 *
 * and read the results out of dmesg. ci/test.sh does exactly that and parses the output.
 *
 * What this suite does NOT check is anything about concurrency. Every test here runs on one
 * thread. A ring buffer that passes all of this and is torn apart by two writers is a ring
 * buffer that passes all of this; that is L07's subject, and it is why L07 exists.
 */

#include <kunit/test.h>
#include <linux/module.h>
#include <linux/slab.h>

#include "qa_fifo.h"

/**
 * @brief A new FIFO holds nothing and reports the capacity it was asked for.
 */
static void qa_fifo_create_destroy(struct kunit* test)
{
    struct qa_fifo* fifo = qa_fifo_create(16U);

    KUNIT_ASSERT_NOT_NULL(test, fifo);
    KUNIT_EXPECT_EQ(test, qa_fifo_capacity(fifo), 16U);
    KUNIT_EXPECT_EQ(test, qa_fifo_level(fifo), 0U);
    qa_fifo_destroy(fifo);
}

/**
 * @brief A capacity of zero is a request that cannot be satisfied, not an empty FIFO.
 */
static void qa_fifo_rejects_zero_capacity(struct kunit* test)
{
    KUNIT_EXPECT_NULL(test, qa_fifo_create(0U));
}

/**
 * @brief Destroying NULL has to work, so that an error path can call it unconditionally.
 */
static void qa_fifo_destroy_tolerates_null(struct kunit* test)
{
    qa_fifo_destroy(NULL);
    KUNIT_SUCCEED(test);
}

/**
 * @brief What goes in comes out, unchanged and in one piece.
 */
static void qa_fifo_round_trip(struct kunit* test)
{
    struct qa_fifo* fifo = qa_fifo_create(8U);
    const u8 in[4U]      = {1U, 2U, 3U, 4U};
    u8 out[4U]           = {0U};

    KUNIT_ASSERT_NOT_NULL(test, fifo);
    KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, in, 4U), 4U);
    KUNIT_EXPECT_EQ(test, qa_fifo_level(fifo), 4U);
    KUNIT_EXPECT_EQ(test, qa_fifo_get(fifo, out, 4U), 4U);
    KUNIT_EXPECT_EQ(test, qa_fifo_level(fifo), 0U);
    KUNIT_EXPECT_MEMEQ(test, out, in, 4U);
    qa_fifo_destroy(fifo);
}

/**
 * @brief Bytes come out in the order they went in. A ring that returns a set is not a FIFO.
 */
static void qa_fifo_preserves_order(struct kunit* test)
{
    struct qa_fifo* fifo = qa_fifo_create(8U);
    u8 byte;
    unsigned int i;

    KUNIT_ASSERT_NOT_NULL(test, fifo);
    for (i = 0U; i < 8U; i++)
    {
        u8 value = (u8)(i + 100U);
        KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, &value, 1U), 1U);
    }
    for (i = 0U; i < 8U; i++)
    {
        KUNIT_EXPECT_EQ(test, qa_fifo_get(fifo, &byte, 1U), 1U);
        KUNIT_EXPECT_EQ(test, byte, (u8)(i + 100U));
    }
    qa_fifo_destroy(fifo);
}

/**
 * @brief Putting more than fits is a short write, not an error and not an overwrite.
 */
static void qa_fifo_put_is_short_when_full(struct kunit* test)
{
    struct qa_fifo* fifo = qa_fifo_create(4U);
    const u8 in[6U]      = {1U, 2U, 3U, 4U, 5U, 6U};

    KUNIT_ASSERT_NOT_NULL(test, fifo);
    KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, in, 6U), 4U);
    KUNIT_EXPECT_EQ(test, qa_fifo_level(fifo), 4U);
    KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, in, 1U), 0U);
    qa_fifo_destroy(fifo);
}

/**
 * @brief Getting more than is held is a short read, and getting from empty returns zero.
 */
static void qa_fifo_get_is_short_when_empty(struct kunit* test)
{
    struct qa_fifo* fifo = qa_fifo_create(4U);
    const u8 in[2U]      = {7U, 8U};
    u8 out[4U]           = {0U};

    KUNIT_ASSERT_NOT_NULL(test, fifo);
    KUNIT_EXPECT_EQ(test, qa_fifo_get(fifo, out, 4U), 0U);
    KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, in, 2U), 2U);
    KUNIT_EXPECT_EQ(test, qa_fifo_get(fifo, out, 4U), 2U);
    KUNIT_EXPECT_EQ(test, out[0U], 7U);
    KUNIT_EXPECT_EQ(test, out[1U], 8U);
    qa_fifo_destroy(fifo);
}

/**
 * @brief The test that catches the naive implementation. Fill, drain, then fill again: the second
 * fill has to wrap around the end of the storage. An implementation that tracks head and tail as
 * plain indices without wrapping passes every test above this one and fails this.
 */
static void qa_fifo_wraps(struct kunit* test)
{
    struct qa_fifo* fifo = qa_fifo_create(4U);
    const u8 first[3U]   = {1U, 2U, 3U};
    const u8 second[3U]  = {4U, 5U, 6U};
    u8 out[3U]           = {0U};

    KUNIT_ASSERT_NOT_NULL(test, fifo);

    KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, first, 3U), 3U);
    KUNIT_EXPECT_EQ(test, qa_fifo_get(fifo, out, 3U), 3U);
    KUNIT_EXPECT_MEMEQ(test, out, first, 3U);

    /* Head and tail are now three into a four-byte buffer; this put must straddle the end. */
    KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, second, 3U), 3U);
    KUNIT_EXPECT_EQ(test, qa_fifo_level(fifo), 3U);
    KUNIT_EXPECT_EQ(test, qa_fifo_get(fifo, out, 3U), 3U);
    KUNIT_EXPECT_MEMEQ(test, out, second, 3U);

    qa_fifo_destroy(fifo);
}

/**
 * @brief A full buffer must accept a full buffer's worth, not capacity minus one.
 */
static void qa_fifo_uses_its_whole_capacity(struct kunit* test)
{
    struct qa_fifo* fifo = qa_fifo_create(4U);
    const u8 in[4U]      = {1U, 2U, 3U, 4U};

    KUNIT_ASSERT_NOT_NULL(test, fifo);
    KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, in, 4U), 4U);
    KUNIT_EXPECT_EQ(test, qa_fifo_level(fifo), 4U);
    qa_fifo_destroy(fifo);
}

/**
 * @brief Reset empties the FIFO and leaves it usable afterwards.
 */
static void qa_fifo_reset_empties(struct kunit* test)
{
    struct qa_fifo* fifo = qa_fifo_create(8U);
    const u8 in[4U]      = {1U, 2U, 3U, 4U};
    u8 out[4U]           = {0U};

    KUNIT_ASSERT_NOT_NULL(test, fifo);
    KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, in, 4U), 4U);
    qa_fifo_reset(fifo);
    KUNIT_EXPECT_EQ(test, qa_fifo_level(fifo), 0U);
    KUNIT_EXPECT_EQ(test, qa_fifo_get(fifo, out, 4U), 0U);

    /* And the FIFO is still usable afterwards, rather than merely emptied. */
    KUNIT_EXPECT_EQ(test, qa_fifo_put(fifo, in, 4U), 4U);
    KUNIT_EXPECT_EQ(test, qa_fifo_level(fifo), 4U);
    qa_fifo_destroy(fifo);
}

static struct kunit_case qa_fifo_cases[] = {KUNIT_CASE(qa_fifo_create_destroy),
                                            KUNIT_CASE(qa_fifo_rejects_zero_capacity),
                                            KUNIT_CASE(qa_fifo_destroy_tolerates_null),
                                            KUNIT_CASE(qa_fifo_round_trip),
                                            KUNIT_CASE(qa_fifo_preserves_order),
                                            KUNIT_CASE(qa_fifo_put_is_short_when_full),
                                            KUNIT_CASE(qa_fifo_get_is_short_when_empty),
                                            KUNIT_CASE(qa_fifo_wraps),
                                            KUNIT_CASE(qa_fifo_uses_its_whole_capacity),
                                            KUNIT_CASE(qa_fifo_reset_empties),
                                            {}};

static struct kunit_suite qa_fifo_suite = {
    .name       = "qa_fifo",
    .test_cases = qa_fifo_cases,
};

kunit_test_suite(qa_fifo_suite);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("L05: KUnit suite for the qa_fifo ring buffer");
