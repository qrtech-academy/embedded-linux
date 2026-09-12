"""Block diagrams of how the pieces sit relative to one another.

These answer "where is this thing" and "what is this obliged to do", which are the questions a
reader has most often in the first half of the course: where the kernel ends and userspace
begins, what a loaded module actually is, what a read owes its caller, and what the driver model
has that a bare character device does not.

Every box is sized by `style.fit_width` from the text it holds, and every row is placed by
`style.row_lefts`. Choosing widths by hand produces a figure that looks right in the source and
ships with its sublabels hanging over the borders.
"""

from __future__ import annotations

import measured
import style
from style import Diagram

SPAN = (0.5, 19.5)  # The usable width of a 20-unit canvas.


# ----------------------------------------------------------------------------------------
# L01 - the boot chain, and the four pieces
# ----------------------------------------------------------------------------------------

# (stage, what it does, which of the four pieces it comes from).
_STAGES = (
    ("ROM code", "on the die", style.FILL_DEVICE),
    ("SPL", "fits in SRAM", style.FILL_ACCENT),
    ("U-Boot", "brings up DRAM", style.FILL_ACCENT),
    ("Kernel", "Image + DTB", style.FILL_KERNEL),
    ("init", "PID 1", style.FILL_USER),
)

_PIECES = (
    ("Not yours", style.FILL_DEVICE, False),
    ("Bootloader", style.FILL_ACCENT, False),
    ("Kernel", style.FILL_KERNEL, False),
    ("Root filesystem", style.FILL_USER, False),
)


def _boot_chain(ax) -> None:
    style.title(ax, "The boot chain, and the four pieces", (10.0, 8.5))

    widths = style.row_widths([(name, note) for name, note, _ in _STAGES])
    lefts, gap = style.row_lefts(widths, SPAN)
    for (name, note, fill), left, width in zip(_STAGES, lefts, widths):
        style.box(ax, (left, 5.4), (width, 1.8), name, note, fill=fill)

    for left, width in zip(lefts[1:], widths[:-1]):
        style.arrow(ax, (left - gap, 6.3), (left, 6.3))

    style.text(
        ax,
        "each stage loads the next, and then stops existing",
        (10.0, 4.9),
        size=style.SMALL_SIZE,
        color=style.MUTED_COLOR,
        valign="top",
    )

    style.swatch_legend(ax, _PIECES, 3.1, SPAN)

    style.text(
        ax,
        "The toolchain is the piece that never ships, and the one that decides whether the\n"
        "other three fit together: it fixes the C library and the ABI of every binary it builds.",
        (10.0, 1.9),
        size=style.SMALL_SIZE,
        valign="top",
    )


BOOT_CHAIN = Diagram(_boot_chain, canvas=(0.0, 1.0, 20.0, 9.2))


# ----------------------------------------------------------------------------------------
# L02 - the three doors into the kernel
# ----------------------------------------------------------------------------------------

_DOORS = (
    ("/proc", "processes and kernel state", "grew organically;", "no shared format"),
    ("/sys", "the driver model", "one value per file;", "a documented ABI"),
    ("/dev", "device nodes", "major selects the driver,", "minor selects the device"),
)


def _kernel_interfaces(ax) -> None:
    style.title(ax, "Every command is a question, asked through one of three doors", (10.0, 12.4))

    style.box(
        ax,
        (SPAN[0], 10.6),
        (SPAN[1] - SPAN[0], 1.3),
        "Userspace",
        "ls   cat   dmesg   udevadm   your program",
        fill=style.FILL_USER,
    )

    # Drawn the same size on purpose. These are not three tiers of anything; they are three
    # conventions layered over the same pair of system calls.
    width = 5.6
    lefts, _ = style.row_lefts([width] * 3, SPAN)
    centres = [left + width / 2 for left in lefts]

    # The boundary label sits in the gap between the first two arrows. Anywhere centred or
    # right-aligned puts it underneath one of them, which is invisible until the figure renders.
    style.rule(ax, 9.6, SPAN)
    style.text(
        ax,
        "the syscall boundary",
        ((centres[0] + centres[1]) / 2, 9.85),
        size=style.SMALL_SIZE,
        valign="bottom",
    )

    # Every label lives inside its box, so the space below the row is free for the arrows. Notes
    # placed under a box collide with the arrow that leaves it, every time.
    for (name, what, note_a, note_b), left in zip(_DOORS, lefts):
        style.box(ax, (left, 6.0), (width, 2.9), fill=style.FILL_KERNEL)
        centre = left + width / 2
        style.text(ax, name, (centre, 8.3), size=style.TITLE_SIZE)
        style.text(ax, what, (centre, 7.6), size=style.SMALL_SIZE, color=style.MUTED_COLOR)
        style.text(ax, note_a, (centre, 6.95), size=style.SMALL_SIZE)
        style.text(ax, note_b, (centre, 6.45), size=style.SMALL_SIZE)
        style.arrow(ax, (centre, 10.6), (centre, 8.9), both=True)
        style.arrow(ax, (centre, 6.0), (centre, 4.4), both=True)

    style.box(
        ax,
        (SPAN[0], 3.1),
        (SPAN[1] - SPAN[0], 1.3),
        "The kernel's live data structures",
        fill=style.FILL_KERNEL,
    )

    style.text(
        ax,
        "Nothing here is stored. Opening the path selects a function; reading it runs that\n"
        "function, which formats an answer from live variables and then throws it away.",
        (10.0, 2.5),
        size=style.SMALL_SIZE,
        valign="top",
    )
    style.text(
        ax,
        "So the files have size zero, two reads need not agree, and most of it cannot be seeked.",
        (10.0, 0.9),
        size=style.SMALL_SIZE,
        color=style.ACCENT_COLOR,
    )


KERNEL_INTERFACES = Diagram(_kernel_interfaces, canvas=(0.0, 0.4, 20.0, 13.0))


# ----------------------------------------------------------------------------------------
# L04 - what a loaded module is doing, which is nothing
# ----------------------------------------------------------------------------------------

_LIFECYCLE = (
    ("insmod", "the loader", style.FILL_USER),
    ("init", "runs once", style.FILL_KERNEL),
    ("resident", "nothing of yours runs", style.FILL_ACCENT),
    ("exit", "runs once", style.FILL_KERNEL),
    ("rmmod", "refcount zero", style.FILL_USER),
)


def _module_lifecycle(ax) -> None:
    style.title(ax, "A loaded module is resident, not running", (10.0, 8.3))

    widths = style.row_widths([(name, note) for name, note, _ in _LIFECYCLE])
    lefts, gap = style.row_lefts(widths, SPAN)
    centres = []
    for (name, note, fill), left, width in zip(_LIFECYCLE, lefts, widths):
        centres.append(style.box(ax, (left, 5.4), (width, 1.8), name, note, fill=fill))
    for left in lefts[1:]:
        style.arrow(ax, (left - gap, 6.3), (left, 6.3))

    # The middle box is the whole figure. The misconception is that a loaded module is a running
    # one, so the state it spends all of its time in gets called out rather than just drawn.
    style.arrow(
        ax,
        (centres[2][0], 4.3),
        (centres[2][0], 5.4),
        color=style.ACCENT_COLOR,
        width=style.ACCENT_WIDTH,
    )
    style.text(
        ax,
        "Code and data occupying kernel memory, waiting to be called by\n"
        "something else: a system call, an interrupt, a timer, another module.",
        (centres[2][0], 3.9),
        size=style.FONT_SIZE,
        color=style.ACCENT_COLOR,
        valign="top",
    )

    style.text(
        ax,
        "Code marked __init is freed once initialisation is done. That is the\n"
        "'Freeing unused kernel memory' line at the end of the boot.",
        (10.0, 1.9),
        size=style.SMALL_SIZE,
        color=style.MUTED_COLOR,
        valign="top",
    )


MODULE_LIFECYCLE = Diagram(_module_lifecycle, canvas=(0.0, 0.5, 20.0, 9.0))


# ----------------------------------------------------------------------------------------
# L10 - bus, device, driver, and what devm_ is attached to
# ----------------------------------------------------------------------------------------


def _device_model(ax) -> None:
    style.title(ax, "The bus matches a device to a driver; probe gets the resources", (10.0, 11.4))

    style.box(
        ax, (1.0, 8.6), (7.4, 1.9), "Device", "from the device tree node", fill=style.FILL_DEVICE
    )
    style.box(
        ax,
        (11.6, 8.6),
        (7.4, 1.9),
        "Driver",
        "your module and its match table",
        fill=style.FILL_KERNEL,
    )

    style.box(
        ax,
        (1.0, 5.6),
        (18.0, 1.7),
        "The platform bus",
        "compares compatible against every registered driver",
        fill=style.FILL_PLAIN,
    )
    style.arrow(ax, (4.7, 8.6), (4.7, 7.3))
    style.arrow(ax, (15.3, 8.6), (15.3, 7.3))

    style.box(
        ax,
        (5.6, 2.6),
        (8.8, 1.7),
        "probe(pdev)",
        "once per matching device",
        fill=style.FILL_ACCENT,
    )
    style.arrow(ax, (10.0, 5.6), (10.0, 4.3), color=style.ACCENT_COLOR, width=style.ACCENT_WIDTH)
    style.text(
        ax, "match", (10.35, 4.95), halign="left", size=style.SMALL_SIZE, color=style.ACCENT_COLOR
    )

    # The lecture demonstrates this by unbinding rather than by unloading, so the figure has to
    # make the bind the unit of lifetime rather than the module.
    style.text(
        ax,
        "Everything probe takes with devm_ is released when this bind ends, and unbinding\n"
        "through sysfs ends it while the module stays loaded. devm_ is attached to the\n"
        "device, not to the module.",
        (10.0, 2.1),
        size=style.SMALL_SIZE,
        color=style.ACCENT_COLOR,
        valign="top",
    )


DEVICE_MODEL = Diagram(_device_model, canvas=(0.0, 0.2, 20.0, 12.0))


# ----------------------------------------------------------------------------------------
# L11 - what a framework writes for you
# ----------------------------------------------------------------------------------------

_BY_HAND = (
    "open, release",
    "read, write",
    "an ioctl ABI of your own",
    "a /dev node to create",
    "a class and a device",
    "and nothing can still find it",
)
_BY_FRAMEWORK = ("a channel specification", "read_raw")
_SUPPLIED = (
    "/sys/bus/iio/devices/iio:device0",
    "a documented, stable ABI",
    "tools that never heard of you",
    "buffered and triggered modes",
)


def _framework_stack(ax) -> None:
    style.title(ax, "The same device, exposed two ways", (10.0, 12.4))

    width = 9.2
    lefts, _ = style.row_lefts([width] * 2, SPAN)
    for left, heading, fill in (
        (lefts[0], "A character device of your own", style.FILL_ACCENT),
        (lefts[1], "An IIO device", style.FILL_KERNEL),
    ):
        style.box(ax, (left, 10.6), (width, 1.3), heading, fill=fill)
        style.text(
            ax,
            "you write",
            (left + width / 2, 10.1),
            size=style.SMALL_SIZE,
            color=style.MUTED_COLOR,
            valign="top",
        )

    for index, row in enumerate(_BY_HAND):
        style.box(
            ax,
            (lefts[0] + 0.5, 8.6 - index * 1.15),
            (width - 1.0, 0.95),
            row,
            fill=style.FILL_PLAIN,
            label_size=style.SMALL_SIZE,
            width=style.CONSTRUCTION_WIDTH,
        )
    for index, row in enumerate(_BY_FRAMEWORK):
        style.box(
            ax,
            (lefts[1] + 0.5, 8.6 - index * 1.15),
            (width - 1.0, 0.95),
            row,
            fill=style.FILL_PLAIN,
            label_size=style.SMALL_SIZE,
            width=style.CONSTRUCTION_WIDTH,
        )

    style.box(
        ax, (lefts[1] + 0.5, 2.6), (width - 1.0, 3.6), "", fill=style.FILL_DEVICE, dashed=True
    )
    style.text(
        ax,
        "the framework supplies",
        (lefts[1] + width / 2, 5.8),
        size=style.SMALL_SIZE,
        weight=style.TITLE_WEIGHT,
    )
    for index, row in enumerate(_SUPPLIED):
        style.text(ax, row, (lefts[1] + width / 2, 5.1 - index * 0.65), size=style.SMALL_SIZE)

    style.text(
        ax,
        f"Reading in_voltage0_raw costs {measured.SYSFS_COST[0][1]} us from a C program, so "
        f"sysfs is for inspection.\nKeeping up with {measured.DEVICE_SAMPLE_RATE} samples a "
        "second is what the buffered modes are for.",
        (10.0, 1.8),
        size=style.SMALL_SIZE,
        color=style.MUTED_COLOR,
        valign="top",
    )


FRAMEWORK_STACK = Diagram(_framework_stack, canvas=(0.0, 0.2, 20.0, 13.0))


# ----------------------------------------------------------------------------------------
# L05 - what read owes its caller
#
# Deliberately the contract rather than the lab's measured sequence. C.9 asks the reader to
# predict that sequence, and a figure of the answer would be a solution rather than a figure.
# ----------------------------------------------------------------------------------------

_READ_CASES = (
    ("data available", "the number of bytes delivered", "which may be fewer than asked for"),
    ("empty, blocking", "sleep, then that count", "wait_event_interruptible"),
    ("empty, O_NONBLOCK", "-EAGAIN", "not now; ask again"),
    ("a signal arrives", "-ERESTARTSYS", "the kernel restarts or reports it"),
)


def _read_contract(ax) -> None:
    style.title(ax, "What read must return, in each of the four cases it faces", (10.0, 11.4))

    left_w, right_w = 6.4, 7.0
    left_x, right_x = 1.4, 10.4
    for index, (case, ret, note) in enumerate(_READ_CASES):
        y = 8.8 - index * 1.6
        style.box(
            ax, (left_x, y), (left_w, 1.2), case, fill=style.FILL_USER, label_size=style.SMALL_SIZE
        )
        style.box(
            ax,
            (right_x, y),
            (right_w, 1.2),
            ret,
            note,
            fill=style.FILL_KERNEL,
            label_size=style.SMALL_SIZE,
        )
        style.arrow(
            ax, (left_x + left_w, y + 0.6), (right_x, y + 0.6), width=style.CONSTRUCTION_WIDTH
        )

    # The claim first, then what it costs. The other way round, the explanation arrives before
    # the thing it is explaining.
    style.box(
        ax,
        (1.4, 2.0),
        (16.0, 1.6),
        "Zero is not on this list",
        "it means end of file, and every reader believes it",
        fill=style.FILL_ACCENT,
        edge=style.ACCENT_COLOR,
        text_color=style.ACCENT_COLOR,
    )
    style.text(
        ax,
        "cat exits. A while (read(...) > 0) loop stops. The program concludes the device is\n"
        "finished when it has merely not produced anything yet.",
        (10.0, 1.5),
        size=style.SMALL_SIZE,
        valign="top",
    )


READ_CONTRACT = Diagram(_read_contract, canvas=(0.0, 0.4, 20.0, 12.0))
