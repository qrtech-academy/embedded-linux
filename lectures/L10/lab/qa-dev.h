/**
 * @file QAcademy teaching device.
 */
#ifndef QA_DEV_H
#define QA_DEV_H

/** The QOM type name, which is what "-device qa-dev" names. */
#define TYPE_QA_DEV "qa-dev"

/** The MMIO window. One page, which is the smallest thing an MMU can map. */
#define QA_DEV_MMIO_SIZE 0x1000U

/** Number of samples the device buffers before it starts dropping them and setting OVERRUN. */
#define QA_DEV_FIFO_DEPTH 16U

/** The shortest period the device accepts. */
#define QA_DEV_MIN_PERIOD_NS 1000U

/** Register offsets. Every register is 32 bits and must be accessed as 32 bits. */
#define QA_DEV_ID 0x00U         /**< RO. Magic. */
#define QA_DEV_VERSION 0x04U    /**< RO. Major in bits 15:8, minor in bits 7:0. */
#define QA_DEV_CTRL 0x08U       /**< RW. */
#define QA_DEV_STATUS 0x0CU     /**< RO. */
#define QA_DEV_PERIOD_NS 0x10U  /**< RW. Sample period in nanoseconds. */
#define QA_DEV_SAMPLE 0x14U     /**< RO. Reading pops one sample from the FIFO. */
#define QA_DEV_FIFO_LEVEL 0x18U /**< RO. Samples currently queued. */
#define QA_DEV_IRQ_STATUS 0x1CU /**< RW1C. Write a one to a bit to clear it. */
#define QA_DEV_TS_LO 0x20U      /**< RO. Low 32 bits of the last interrupt's timestamp. */
#define QA_DEV_TS_HI 0x24U      /**< RO. High 32 bits. Latched by reading TS_LO. */
#define QA_DEV_GPIO_OUT 0x28U   /**< RW. Outputs in bits 7:0; bits 3:0 loop back to GPIO_IN. */
#define QA_DEV_GPIO_IN 0x2CU    /**< RO. Bits 7:4 read back GPIO_OUT bits 3:0; bits 3:0 read 0. */
#define QA_DEV_SCRATCH 0x30U    /**< RW. Reads back what was written. Nothing else uses it. */

/** The value of QA_DEV_ID: "QADV" in ASCII, big end first. */
#define QA_DEV_ID_MAGIC 0x51414456U

/** QA_DEV_CTRL. */
#define QA_DEV_CTRL_ENABLE (1U << 0U) /**< Start sampling. */
#define QA_DEV_CTRL_IRQ_EN (1U << 1U) /**< Let a pending IRQ_STATUS bit raise the line. */
#define QA_DEV_CTRL_RESET (1U << 2U)  /**< Self-clearing. Empties the FIFO and the status bits. */
#define QA_DEV_CTRL_MODE_SHIFT 4U
#define QA_DEV_CTRL_MODE_MASK (3U << QA_DEV_CTRL_MODE_SHIFT)

/** Sample modes. */
#define QA_DEV_MODE_COUNTER 0U  /**< Sample n is n. */
#define QA_DEV_MODE_SAWTOOTH 1U /**< Sample n is n modulo 4096. */
#define QA_DEV_MODE_NOISE 2U    /**< A linear congruential sequence from a fixed seed. */

/** QA_DEV_STATUS. */
#define QA_DEV_STATUS_READY (1U << 0U)
#define QA_DEV_STATUS_FIFO_EMPTY (1U << 1U)
#define QA_DEV_STATUS_FIFO_FULL (1U << 2U)
#define QA_DEV_STATUS_OVERRUN (1U << 3U) /**< Sticky. Cleared by clearing IRQ_STATUS_OVERRUN. */

/** QA_DEV_IRQ_STATUS. Write-one-to-clear, both bits. */
#define QA_DEV_IRQ_SAMPLE (1U << 0U)  /**< At least one sample is waiting. */
#define QA_DEV_IRQ_OVERRUN (1U << 1U) /**< A sample was dropped because the FIFO was full. */

/** The device tree node this device generates, and the string a driver matches on. */
#define QA_DEV_DT_COMPATIBLE "qacademy,qa-dev-1.0"

#endif /* QA_DEV_H */
