/**
 * @file QAcademy teaching device, as a QEMU device model.
 */
#include "qemu/osdep.h" /* Always first: it sets the macros the system headers below depend on. */

#include <stdbool.h>
#include <stdint.h>

#include "exec/hwaddr.h"
#include "exec/memory.h"
#include "hw/irq.h"
#include "hw/qdev-core.h"
#include "hw/qdev-properties.h"
#include "hw/resettable.h"
#include "hw/sysbus.h"
#include "migration/vmstate.h"
#include "qapi/error.h"
#include "qemu/bitops.h"
#include "qemu/log.h"
#include "qemu/module.h"
#include "qemu/timer.h"
#include "qom/object.h"

#include "hw/misc/qa-dev.h"

OBJECT_DECLARE_SIMPLE_TYPE(QADevState, QA_DEV)

/**
 * @brief QAcademy device state structure.
 */
struct QADevState
{
    /** Parent object. */
    SysBusDevice parent_obj;

    /** I/O memory. */
    MemoryRegion iomem;

    /** Interrupt request. */
    qemu_irq irq;

    /** Timer that produces one sample per period. */
    QEMUTimer* timer;

    /** CTRL, as the guest wrote it, with RESET masked off. */
    uint32_t ctrl;

    /** Sample period in nanoseconds. */
    uint32_t period_ns;

    /** Pending interrupt causes. Write-one-to-clear. */
    uint32_t irq_status;

    /** The output lines, of which bits 3:0 loop back to GPIO_IN. */
    uint32_t gpio_out;

    /** Scratch register, which reads back what was written and nothing else. */
    uint32_t scratch;

    /** Sticky overrun, kept separately because STATUS is computed on read. */
    bool overrun;

    /** The sample FIFO. A ring, so a full one drops the newest rather than shuffling. */
    uint32_t fifo[QA_DEV_FIFO_DEPTH];

    /** Index of the oldest sample held. */
    uint32_t fifo_head;

    /** Samples currently held. */
    uint32_t fifo_level;

    /** The instant the last interrupt was asserted, on the virtual clock. */
    uint64_t timestamp;

    /** The copy latched by a read of TS_LO, so that the 64-bit pair cannot tear. */
    uint64_t timestamp_latched;

    /** Samples produced since reset, which is also what counter mode returns. */
    uint64_t sample_count;

    /** State of the noise mode's linear congruential generator. */
    uint32_t noise_state;

    /** The period the device resets to. A property. */
    uint32_t period_ns_reset;
};

/**
 * @brief Read one register.
 *
 * @param[in] opaque Device state.
 * @param[in] offset Register offset within the MMIO window.
 * @param[in] size   Access size in bytes, which the ops table has already restricted to four.
 *
 * @returns The register's value, or zero for an unmapped offset, which is also logged.
 */
static uint64_t qa_dev_read(void* opaque, hwaddr offset, unsigned size);
/**
 * @brief Write one register. Read-only and unmapped offsets are logged, not obeyed.
 *
 * @param[in] opaque Device state.
 * @param[in] offset Register offset within the MMIO window.
 * @param[in] value  Value written by the guest.
 * @param[in] size   Access size in bytes, which the ops table has already restricted to four.
 */
static void qa_dev_write(void* opaque, hwaddr offset, uint64_t value, unsigned size);
/**
 * @brief Create the MMIO window and the interrupt line.
 *
 * @param[in] obj The device, as a QOM object.
 */
static void qa_dev_init(Object* obj);
/**
 * @brief Install the class's callbacks, properties and reset phase.
 *
 * @param[in] klass The class being initialised.
 * @param[in] data  Class data, unused here.
 */
static void qa_dev_class_init(ObjectClass* klass, void* data);

/** Device operations. Every register is 32 bits and must be accessed as 32 bits. */
static const MemoryRegionOps qa_dev_ops = {
    .read       = qa_dev_read,
    .write      = qa_dev_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid =
        {
            .min_access_size = 4U,
            .max_access_size = 4U,
            .unaligned       = false,
        },
    .impl =
        {
            .min_access_size = 4U,
            .max_access_size = 4U,
        },
};

/** Virtual machine state. */
static const VMStateDescription qa_dev_vmstate = {
    .name               = TYPE_QA_DEV,
    .version_id         = 1,
    .minimum_version_id = 1,
    .fields =
        (const VMStateField[]){
            VMSTATE_UINT32(ctrl, QADevState),
            VMSTATE_UINT32(period_ns, QADevState),
            VMSTATE_UINT32(irq_status, QADevState),
            VMSTATE_UINT32(gpio_out, QADevState),
            VMSTATE_UINT32(scratch, QADevState),
            VMSTATE_BOOL(overrun, QADevState),
            VMSTATE_UINT32_ARRAY(fifo, QADevState, QA_DEV_FIFO_DEPTH),
            VMSTATE_UINT32(fifo_head, QADevState),
            VMSTATE_UINT32(fifo_level, QADevState),
            VMSTATE_UINT64(timestamp, QADevState),
            VMSTATE_UINT64(timestamp_latched, QADevState),
            VMSTATE_UINT64(sample_count, QADevState),
            VMSTATE_UINT32(noise_state, QADevState),
            VMSTATE_TIMER_PTR(timer, QADevState),
            VMSTATE_END_OF_LIST(),
        },
};

/** Device properties. */
static Property qa_dev_properties[] = {
    DEFINE_PROP_UINT32("period-ns", QADevState, period_ns_reset, 1000000U),
    DEFINE_PROP_END_OF_LIST(),
};

/** Device info. */
static const TypeInfo qa_dev_info = {
    .name          = TYPE_QA_DEV,
    .parent        = TYPE_SYS_BUS_DEVICE,
    .instance_size = sizeof(QADevState),
    .instance_init = qa_dev_init,
    .class_init    = qa_dev_class_init,
};

// -----------------------------------------------------------------------------
/**
 * @brief Raise the line while the guest has interrupts enabled and something is pending.
 *
 * Called after every change to either, which is the only way to keep a level-triggered line
 * honest.
 *
 * @param[in] self Device state.
 */
static void qa_dev_update_irq(QADevState* self)
{
    const bool pending = 0U != (self->irq_status & (QA_DEV_IRQ_SAMPLE | QA_DEV_IRQ_OVERRUN));
    const bool enabled = 0U != (self->ctrl & QA_DEV_CTRL_IRQ_EN);
    qemu_set_irq(self->irq, pending && enabled);
}

// -----------------------------------------------------------------------------
/**
 * @brief Push one sample.
 *
 * @param[in] self  Device state.
 * @param[in] value Sample to push.
 *
 * @returns true if the sample was queued, false if the FIFO was full and it was dropped.
 */
static bool qa_dev_fifo_push(QADevState* self, const uint32_t value)
{
    if (QA_DEV_FIFO_DEPTH <= self->fifo_level) { return false; }

    const uint32_t tail = (self->fifo_head + self->fifo_level) % QA_DEV_FIFO_DEPTH;
    self->fifo[tail]    = value;
    self->fifo_level++;
    return true;
}

// -----------------------------------------------------------------------------
/**
 * @brief Pop one sample.
 *
 * An empty FIFO reads as zero rather than as an error, and zero is also a perfectly good sample
 * in counter mode. That is why STATUS carries FIFO_EMPTY.
 *
 * @param[in] self Device state.
 *
 * @returns The oldest sample held, or zero if the FIFO was empty.
 */
static uint32_t qa_dev_fifo_pop(QADevState* self)
{
    if (0U == self->fifo_level) { return 0U; }

    const uint32_t value = self->fifo[self->fifo_head];
    self->fifo_head      = (self->fifo_head + 1U) % QA_DEV_FIFO_DEPTH;
    self->fifo_level--;

    /* Emptying the FIFO clears SAMPLE on its own; only a write clears OVERRUN. */
    if (0U == self->fifo_level)
    {
        self->irq_status &= ~QA_DEV_IRQ_SAMPLE;
        qa_dev_update_irq(self);
    }
    return value;
}

// -----------------------------------------------------------------------------
/**
 * @brief Produce the next sample for the configured mode.
 *
 * Two of the three modes are exactly reproducible, which is what lets a test assert on values
 * rather than on their shape; the third exists so L12 has something to plot that does not look
 * like a ruler.
 *
 * @param[in] self Device state.
 *
 * @returns The sample.
 */
static uint32_t qa_dev_next_sample(QADevState* self)
{
    const uint32_t mode = (self->ctrl & QA_DEV_CTRL_MODE_MASK) >> QA_DEV_CTRL_MODE_SHIFT;
    uint32_t value;

    switch (mode)
    {
        case QA_DEV_MODE_SAWTOOTH:
            value = (uint32_t)(self->sample_count & 0xFFFU);
            break;

        case QA_DEV_MODE_NOISE:
            /* The constants are glibc's. Any LCG would do; a named one is easier to check. */
            self->noise_state = (self->noise_state * 1103515245U) + 12345U;
            value             = (self->noise_state >> 16U) & 0xFFFU;
            break;

        case QA_DEV_MODE_COUNTER:
        default:
            value = (uint32_t)self->sample_count;
            break;
    }

    self->sample_count++;
    return value;
}

// -----------------------------------------------------------------------------
/**
 * @brief Arm the timer for one more period, or stop it if the device is disabled.
 *
 * @param[in] self Device state.
 */
static void qa_dev_arm_timer(QADevState* self)
{
    if ((0U != (self->ctrl & QA_DEV_CTRL_ENABLE)) && (QA_DEV_MIN_PERIOD_NS <= self->period_ns))
    {
        timer_mod(self->timer, qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL) + self->period_ns);
    }
    else { timer_del(self->timer); }
}

// -----------------------------------------------------------------------------
/**
 * @brief One period has elapsed: take a sample, stamp the moment, raise the line.
 *
 * The stamp comes from QEMU_CLOCK_VIRTUAL, the base the guest's generic timer counts. The two do
 * not share an origin and nothing published relates them, so L12 uses the difference only as a
 * spread: subtract the smallest ever seen, and the unknown offset goes with it.
 *
 * @param[in] opaque Device state.
 */
static void qa_dev_timer_expired(void* opaque)
{
    QADevState* self = opaque;

    self->timestamp = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);

    if (!qa_dev_fifo_push(self, qa_dev_next_sample(self)))
    {
        self->overrun = true;
        self->irq_status |= QA_DEV_IRQ_OVERRUN;
    }
    else { self->irq_status |= QA_DEV_IRQ_SAMPLE; }

    qa_dev_update_irq(self);
    qa_dev_arm_timer(self);
}

// -----------------------------------------------------------------------------
/**
 * @brief Compute STATUS.
 *
 * It is computed rather than stored, so it cannot drift out of step with the FIFO.
 *
 * @param[in] self Device state.
 *
 * @returns The value a read of STATUS returns.
 */
static uint32_t qa_dev_status(const QADevState* self)
{
    uint32_t status = QA_DEV_STATUS_READY;

    if (0U == self->fifo_level) { status |= QA_DEV_STATUS_FIFO_EMPTY; }
    if (QA_DEV_FIFO_DEPTH <= self->fifo_level) { status |= QA_DEV_STATUS_FIFO_FULL; }
    if (self->overrun) { status |= QA_DEV_STATUS_OVERRUN; }

    return status;
}

// -----------------------------------------------------------------------------
/** Read one register. */
static uint64_t qa_dev_read(void* opaque, hwaddr offset, unsigned size)
{
    QADevState* self = opaque;

    switch (offset)
    {
        case QA_DEV_ID:
            return QA_DEV_ID_MAGIC;

        case QA_DEV_VERSION:
            return 0x0100U;

        case QA_DEV_CTRL:
            return self->ctrl;

        case QA_DEV_STATUS:
            return qa_dev_status(self);

        case QA_DEV_PERIOD_NS:
            return self->period_ns;

        case QA_DEV_SAMPLE:
            return qa_dev_fifo_pop(self);

        case QA_DEV_FIFO_LEVEL:
            return self->fifo_level;

        case QA_DEV_IRQ_STATUS:
            return self->irq_status;

        /* Reading the low half snapshots the pair. See the comment on timestamp_latched. */
        case QA_DEV_TS_LO:
            self->timestamp_latched = self->timestamp;
            return (uint32_t)self->timestamp_latched;

        case QA_DEV_TS_HI:
            return (uint32_t)(self->timestamp_latched >> 32U);

        case QA_DEV_GPIO_OUT:
            return self->gpio_out;

        /*
         * The four output lines are wired back to the four input lines, so a driver can drive a
         * line and see it change with nothing plugged in. No real board works this way; it is here
         * so L11's gpiochip lab has something to observe.
         */
        case QA_DEV_GPIO_IN:
            return (self->gpio_out & 0x0FU) << 4U;

        case QA_DEV_SCRATCH:
            return self->scratch;

        default:
            qemu_log_mask(LOG_GUEST_ERROR, "qa-dev: read from unmapped offset 0x%" HWADDR_PRIx "\n",
                          offset);
            return 0U;
    }
}

// -----------------------------------------------------------------------------
/** Write one register. Reads-only offsets and unmapped ones are logged, not obeyed. */
static void qa_dev_write(void* opaque, hwaddr offset, uint64_t value, unsigned size)
{
    QADevState* self    = opaque;
    const uint32_t word = (uint32_t)value;

    switch (offset)
    {
        case QA_DEV_CTRL:
            /*
             * RESET is self-clearing: it never reads back as set, which is what a driver polling
             * for it to clear will hang on. That is deliberate, and L06's exercises ask about it.
             */
            if (0U != (word & QA_DEV_CTRL_RESET))
            {
                self->fifo_head    = 0U;
                self->fifo_level   = 0U;
                self->sample_count = 0U;
                self->overrun      = false;
                self->irq_status   = 0U;
            }
            self->ctrl = word & ~QA_DEV_CTRL_RESET;
            qa_dev_update_irq(self);
            qa_dev_arm_timer(self);
            break;

        case QA_DEV_PERIOD_NS:
            self->period_ns = word;
            qa_dev_arm_timer(self);
            break;

        /* Write one to clear. Writing zero to a bit leaves it alone; writing a one clears it. */
        case QA_DEV_IRQ_STATUS:
            self->irq_status &= ~word;
            if (0U != (word & QA_DEV_IRQ_OVERRUN)) { self->overrun = false; }
            qa_dev_update_irq(self);
            break;

        case QA_DEV_GPIO_OUT:
            self->gpio_out = word & 0xFFU;
            break;

        case QA_DEV_SCRATCH:
            self->scratch = word;
            break;

        case QA_DEV_ID:
        case QA_DEV_VERSION:
        case QA_DEV_STATUS:
        case QA_DEV_SAMPLE:
        case QA_DEV_FIFO_LEVEL:
        case QA_DEV_TS_LO:
        case QA_DEV_TS_HI:
        case QA_DEV_GPIO_IN:
            qemu_log_mask(LOG_GUEST_ERROR, "qa-dev: write to read-only offset 0x%" HWADDR_PRIx "\n",
                          offset);
            break;

        default:
            qemu_log_mask(LOG_GUEST_ERROR, "qa-dev: write to unmapped offset 0x%" HWADDR_PRIx "\n",
                          offset);
            break;
    }
}

// -----------------------------------------------------------------------------
/**
 * @brief Reset every register to the state the guest finds at power-on.
 *
 * @param[in] obj  The device, as a QOM object.
 * @param[in] type Reset type, which this device does not distinguish.
 */
static void qa_dev_reset_hold(Object* obj, ResetType type)
{
    QADevState* self = QA_DEV(obj);

    self->ctrl              = 0U;
    self->period_ns         = self->period_ns_reset;
    self->irq_status        = 0U;
    self->gpio_out          = 0U;
    self->scratch           = 0U;
    self->overrun           = false;
    self->fifo_head         = 0U;
    self->fifo_level        = 0U;
    self->timestamp         = 0U;
    self->timestamp_latched = 0U;
    self->sample_count      = 0U;
    self->noise_state       = 1U;

    timer_del(self->timer);
    qemu_set_irq(self->irq, 0);
}

// -----------------------------------------------------------------------------
/** Create the MMIO window and the interrupt line. */
static void qa_dev_init(Object* obj)
{
    QADevState* self = QA_DEV(obj);
    SysBusDevice* sb = SYS_BUS_DEVICE(obj);

    memory_region_init_io(&self->iomem, obj, &qa_dev_ops, self, TYPE_QA_DEV, QA_DEV_MMIO_SIZE);
    sysbus_init_mmio(sb, &self->iomem);
    sysbus_init_irq(sb, &self->irq);
}

// -----------------------------------------------------------------------------
/**
 * @brief Allocate the sample timer.
 *
 * @param[in]  dev  The device.
 * @param[out] errp Where an error would be reported; this device cannot fail to realize.
 */
static void qa_dev_realize(DeviceState* dev, Error** errp)
{
    QADevState* self = QA_DEV(dev);
    self->timer      = timer_new_ns(QEMU_CLOCK_VIRTUAL, qa_dev_timer_expired, self);
}

// -----------------------------------------------------------------------------
/**
 * @brief Free the sample timer.
 *
 * @param[in] dev The device.
 */
static void qa_dev_unrealize(DeviceState* dev)
{
    QADevState* self = QA_DEV(dev);

    if (NULL != self->timer)
    {
        timer_free(self->timer);
        self->timer = NULL;
    }
}

// -----------------------------------------------------------------------------
/** Install the class's callbacks, properties and reset phase. */
static void qa_dev_class_init(ObjectClass* klass, void* data)
{
    DeviceClass* dc     = DEVICE_CLASS(klass);
    ResettableClass* rc = RESETTABLE_CLASS(klass);

    /*
     * TYPE_SYS_BUS_DEVICE turns this off for every subclass, because a sysbus device generally
     * cannot be plugged in from the command line: nothing would wire up its memory region or its
     * interrupt line. The dynamic platform bus is the exception, and a device that wants to be
     * placed on it has to say so here as well as being named in the machine's allowlist. Miss this
     * and the device links, registers its type, and simply does not appear in "-device help";
     * ci/qemu.sh checks for exactly that.
     */
    dc->user_creatable = true;

    dc->desc        = "QAcademy teaching device";
    dc->realize     = qa_dev_realize;
    dc->unrealize   = qa_dev_unrealize;
    dc->vmsd        = &qa_dev_vmstate;
    rc->phases.hold = qa_dev_reset_hold;

    device_class_set_props(dc, qa_dev_properties);
    set_bit(DEVICE_CATEGORY_MISC, dc->categories);
}

// -----------------------------------------------------------------------------
/**
 * @brief Register the type with QOM.
 */
static void qa_dev_register_types(void) { type_register_static(&qa_dev_info); }

type_init(qa_dev_register_types)
