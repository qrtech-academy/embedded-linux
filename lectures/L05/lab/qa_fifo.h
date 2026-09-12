/**
 * @file Byte ring buffer implementation.
 */
#ifndef QA_FIFO_H
#define QA_FIFO_H

#include <linux/types.h>

/** Byte ring buffer structure. */
struct qa_fifo;

/**
 * @brief Create a new FIFO.
 *
 * @param[in] capacity FIFO capacity. Must be greater than 0.
 *
 * @returns The new FIFO, or NULL on allocation failure.
 */
struct qa_fifo* qa_fifo_create(size_t capacity);

/**
 * @brief Destroy a FIFO.
 *
 * @param[in] fifo FIFO to destroy.
 */
void qa_fifo_destroy(struct qa_fifo* fifo);

/**
 * @brief Get the capacity the FIFO was created with.
 *
 * @param[in] fifo FIFO to read.
 *
 * @returns The capacity in bytes.
 */
size_t qa_fifo_capacity(const struct qa_fifo* fifo);

/**
 * @brief Get how many bytes the FIFO currently holds.
 *
 * @param[in] fifo FIFO to read.
 *
 * @returns The number of bytes held.
 */
size_t qa_fifo_level(const struct qa_fifo* fifo);

/**
 * @brief Copy up to len bytes into the FIFO.
 *
 * @param[in] fifo FIFO to write to.
 * @param[in] data Bytes to copy in.
 * @param[in] len Number of bytes to copy.
 *
 * @returns The number of bytes copied, which is less than len when the FIFO fills.
 */
size_t qa_fifo_put(struct qa_fifo* fifo, const u8* data, size_t len);

/**
 * @brief Copy up to len bytes out of the FIFO, removing them.
 *
 * @param[in] fifo FIFO to read from.
 * @param[out] data Buffer the bytes are copied into.
 * @param[in] len Number of bytes to copy.
 *
 * @returns The number of bytes copied, or zero if it was already empty.
 */
size_t qa_fifo_get(struct qa_fifo* fifo, u8* data, size_t len);

/**
 * @brief Discard everything the FIFO holds, without freeing or reallocating.
 *
 * @param[in] fifo FIFO to reset.
 */
void qa_fifo_reset(struct qa_fifo* fifo);

#endif /* QA_FIFO_H */
