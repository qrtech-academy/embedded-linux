"""Every number that appears on a chart in this course, with the appendix that publishes it.

Nothing here is modelled, estimated or invented. Each block was measured on the course's own
target, an emulated `qemu-system-aarch64 -M virt` running the pinned 6.12.30 kernel, and is
quoted in the appendix named beside it. The figures import from this module and never carry a
literal of their own, which means two things:

* A figure cannot drift from the prose. If a measurement is redone, it is edited here, every
  chart that uses it is redrawn by `make diagrams`, and the appendix is the only other place to
  change.
* Every number on every chart is auditable. The docstring beside it says where the reader can
  find the same figure written out, and `ci/links.sh` keeps those paths honest.

Where a figure needs a number this module does not have, the answer is to measure it and add it
here, not to pass a literal at the call site.
"""

from __future__ import annotations

# ----------------------------------------------------------------------------------------
# L03 - what one config option costs
#
# lectures/L03/appendix/b_kconfig_and_kbuild.md B.6, and its cross-check in c_exercises.md C.9.
# Measured by building the kernel twice, with and without CONFIG_IKCONFIG, and comparing
# `size -A` on vmlinux against the two boot images.
# ----------------------------------------------------------------------------------------

# The option's actual content: the four sections of `size -A build/kernel/kernel/configs.o` that
# B.6 counts, .rodata 34,048, .text 76, .rodata.str1.8 10 and .initcall6.init 4. The whole of that
# output is 34,532; the rest is metadata, notes and the init and exit code discarded at boot.
IKCONFIG_CONTENT = 34_138

# How much vmlinux's section total moved, and how much the arm64 Image moved. The three numbers
# differ by roughly a factor of two, which is the entire point of the exercise.
IKCONFIG_SECTIONS = 41_208
IKCONFIG_IMAGE = 65_536

# The per-section deltas behind the 41,208, in the order they contribute. Two sections carry
# almost all of it and both moved by a whole number of 4,096-byte pages: .rodata by nine pages
# for 34,058 bytes of content, and .text by a full page for 76 bytes.
IKCONFIG_SECTION_DELTAS = (
    (".rodata", 36_864, 34_058),
    (".text", 4_096, 76),
    (".init.text", 112, 0),
    (".rela.dyn", 96, 0),
    (".exit.text", 40, 0),
)

PAGE_SIZE = 4_096
SEGMENT_ALIGN = 65_536  # arch/arm64/include/asm/memory.h: SEGMENT_ALIGN is SZ_64K.

# ----------------------------------------------------------------------------------------
# L05 - the character device contract
#
# lectures/L05/appendix/c_exercises.md C.9. Five calls against /dev/qa_fifo at the default
# capacity of 256, run on the target.
# ----------------------------------------------------------------------------------------

FIFO_CAPACITY = 256

# (call, bytes asked for, what read/write returned, FIFO level afterwards). Step 2 is the one
# people predict wrongly: the FIFO is not full when the call arrives, so it is a short write of
# 56 rather than -ENOSPC. Step 4 is the other one: an empty FIFO is -EAGAIN, never 0, because 0
# means end of file and every reader believes it.
FIFO_SEQUENCE = (
    ("write", 200, 200, 200),
    ("write", 100, 56, 256),
    ("read", 512, 256, 0),
    ("read", 512, None, 0),  # -EAGAIN
    ("write", 300, 256, 256),
)
FIFO_ERROR_LABEL = "-EAGAIN"

# ----------------------------------------------------------------------------------------
# L07 - a race that only appears when it is given time
#
# lectures/L07/appendix/a_concurrency_and_locks.md A.2. Four threads incrementing a shared
# counter with no lock, released together by a starting barrier, three runs at each size.
# ----------------------------------------------------------------------------------------

RACE_THREADS = 4

# (increments per thread, expected total, loss percentage in each of three runs). The first two
# rows are the same broken program returning the right answer every time.
RACE_BY_SIZE = (
    (200, 800, (0.0, 0.0, 0.0)),
    (2_000, 8_000, (0.0, 0.0, 0.0)),
    (20_000, 80_000, (23.3, 20.8, 6.9)),
    (200_000, 800_000, (31.7, 34.9, 26.5)),
)

# Ten consecutive unlocked runs at 20,000 increments per thread, from the same appendix. Never
# zero, and never the same twice, which is what lets the lab's test assert on it.
RACE_TEN_RUNS = (1_564, 6_471, 9_708, 12_278, 16_438, 16_805, 17_285, 17_475, 26_545, 30_047)
RACE_EXPECTED = 80_000

# ----------------------------------------------------------------------------------------
# L09 - what a sleep actually costs
#
# lectures/L09/appendix/b_time.md B.4. 200 repetitions of each call, at HZ=250 where one jiffy
# is 4,000 us.
# ----------------------------------------------------------------------------------------

JIFFY_US = 4_000
HZ = 250

# (call, microseconds asked for, microseconds measured). msleep(1) and msleep(4) come out
# identical because msecs_to_jiffies rounds both up to one jiffy, and schedule_timeout then
# guarantees "at least", which costs a second tick.
SLEEP_COST = (
    ("msleep(1)", 1_000, 8_000),
    ("msleep(4)", 4_000, 8_000),
    ("msleep(10)", 10_000, 15_998),
    ("usleep_range(1000)", 1_000, 1_443),
    ("usleep_range(100)", 100, 307),
    ("udelay(100)", 100, 112),
)

# ----------------------------------------------------------------------------------------
# L11 - the cost of reading a sysfs attribute
#
# lectures/L11/appendix/a_frameworks.md A.8. Reading in_voltage0_raw in a loop, two ways.
# ----------------------------------------------------------------------------------------

# (how it was read, microseconds per read, reads per second).
SYSFS_COST = (
    ("A C program", 571, 1_748),
    ("A shell loop of `cat`", 29_700, 34),
)

# The device produces this many samples a second, so a reader has to keep up with it. Both
# figures above are on the wrong side of it for a shell, and marginal for C.
DEVICE_SAMPLE_RATE = 881

# ----------------------------------------------------------------------------------------
# L12 - PREEMPT against PREEMPT_RT
#
# lectures/L12/appendix/a_realtime.md A.8. Handler-to-userspace latency, the one interval the lab
# can give as an absolute figure, 2,000 samples per configuration, one run of each.
# ----------------------------------------------------------------------------------------

# (kernel, load, mean us, worst us). PREEMPT_RT makes the mean worse and the maximum better.
# That is the trade, and it is the whole lecture in four rows.
LATENCY = (
    ("PREEMPT", "idle", 449, 11_321),
    ("PREEMPT_RT", "idle", 551, 4_964),
    ("PREEMPT", "busy", 1_685, 29_729),
    ("PREEMPT_RT", "busy", 2_393, 18_559),
)

# The same PREEMPT idle measurement, repeated. More than a factor of four on one kernel with
# nothing changed, which is larger than some of the kernel-to-kernel differences above.
LATENCY_REPEAT_WORST = (11_321, 2_502)

# ----------------------------------------------------------------------------------------
# L06 and L08 - the device the course builds its labs around
#
# lectures/L06/appendix/b_mmio_and_resources.md, lectures/L08/appendix/a_interrupts.md.
# ----------------------------------------------------------------------------------------

QA_DEV_CHILD_ADDRESS = 0x0  # What the node's own `reg` says.
QA_DEV_PARENT_BASE = 0xC000000  # What the parent's `ranges` maps it to.
QA_DEV_WINDOW = 0x1000
QA_DEV_ID_MAGIC = 0x51414456  # "QADV", the first thing a working mapping reads back.

# One interrupt, three numbering spaces, all visible at once in /proc/interrupts.
IRQ_DT_CELL = 112  # What the device tree says.
GIC_SPI_BASE = 32
IRQ_GIC = IRQ_DT_CELL + GIC_SPI_BASE  # 144, the controller's own number.
IRQ_LINUX = 17  # Allocated at run time, and unrelated to either.
