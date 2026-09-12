"""Figures that follow one value through the transformations that change it.

Each of these exists because a number the reader can see is not the number the machine uses, and
the gap between the two is where the lecture's mistakes live: an option that was written down and
then discarded, an address that has to be translated before it means anything, and an interrupt
that has three different numbers depending on who is asked.
"""

from __future__ import annotations

import measured
import style
from style import Diagram

SPAN = (0.5, 19.5)


# ----------------------------------------------------------------------------------------
# L03 - where a config option goes to die
# ----------------------------------------------------------------------------------------

_CONFIG_STEPS = (
    ("defconfig", "the architecture's\ndefaults", style.FILL_PLAIN),
    ("fragments", "trim, qa, rt:\nwhat you asked for", style.FILL_USER),
    ("merge", "concatenates;\nchecks nothing", style.FILL_PLAIN),
    ("olddefconfig", "resolves every\ndependency", style.FILL_ACCENT),
    (".config", "what is\nactually built", style.FILL_KERNEL),
)


def _kconfig_flow(ax) -> None:
    style.title(ax, "A fragment is a request, and olddefconfig decides", (10.0, 10.4))

    widths = style.row_widths([(name, "") for name, _, _ in _CONFIG_STEPS], pad=1.4)
    lefts, gap = style.row_lefts(widths, SPAN)
    for (name, note, fill), left, width in zip(_CONFIG_STEPS, lefts, widths):
        style.box(ax, (left, 7.2), (width, 1.5), name, fill=fill)
        style.caption(ax, note, left + width / 2, 6.7, SPAN)
    for left in lefts[1:]:
        style.arrow(ax, (left - gap, 7.95), (left, 7.95))

    # The failure this figure exists for. The line is written, it survives the merge, and it is
    # then discarded without a warning, because a symbol whose dependencies are unmet has no
    # prompt and a symbol with no prompt takes its default.
    #
    # The callout is centred on the canvas rather than on the box it points at: centring it on
    # olddefconfig, which sits three quarters of the way across, runs it off the right edge.
    drop = lefts[3] + widths[3] / 2
    style.arrow(ax, (drop, 5.4), (drop, 4.4), color=style.ACCENT_COLOR, width=style.ACCENT_WIDTH)
    style.box(
        ax,
        (3.6, 2.8),
        (12.8, 1.6),
        "CONFIG_PREEMPT_RT=y",
        "silently discarded",
        fill=style.FILL_ACCENT,
        edge=style.ACCENT_COLOR,
        text_color=style.ACCENT_COLOR,
    )
    style.text(
        ax,
        "It depends on EXPERT, and EXPERT is off. A symbol whose dependencies are unmet has no\n"
        "prompt; a symbol with no prompt cannot be set, and takes its default instead.",
        (10.0, 2.3),
        size=style.SMALL_SIZE,
        valign="top",
    )

    style.text(
        ax,
        "The kernel then builds cleanly, boots, and reports PREEMPT. Nothing failed, so nothing\n"
        "was reported: this is why ci/kernel.sh re-reads every fragment after the merge.",
        (10.0, 0.5),
        size=style.SMALL_SIZE,
        color=style.MUTED_COLOR,
        valign="top",
    )


KCONFIG_FLOW = Diagram(_kconfig_flow, canvas=(0.0, -1.0, 20.0, 11.0))


# ----------------------------------------------------------------------------------------
# L06 - translating an address out of the device tree
# ----------------------------------------------------------------------------------------

_TRANSLATION = (
    (
        "reg",
        f"0x{measured.QA_DEV_CHILD_ADDRESS:02X}  0x{measured.QA_DEV_WINDOW:X}",
        "what the node itself\nsays: a child address",
    ),
    (
        "ranges",
        f"0x0 -> 0x{measured.QA_DEV_PARENT_BASE:08X}",
        "what the parent maps\nthat child address to",
    ),
    (
        "ioremap",
        f"0x{measured.QA_DEV_PARENT_BASE:08X}",
        "the physical address,\nmapped into the kernel",
    ),
    ("readl", f"0x{measured.QA_DEV_ID_MAGIC:08X}", 'the identity register:\n"QADV", so it worked'),
)


def _address_translation(ax) -> None:
    style.title(ax, "reg is not an address until the parent has translated it", (10.0, 9.4))

    widths = style.row_widths([(name, value) for name, value, _ in _TRANSLATION])
    lefts, gap = style.row_lefts(widths, SPAN)
    for (name, value, note), left, width in zip(_TRANSLATION, lefts, widths):
        # The last box is the payoff, so it is the only one accented.
        accent = name == "readl"
        style.box(
            ax,
            (left, 6.0),
            (width, 1.9),
            name,
            value,
            fill=style.FILL_ACCENT if accent else style.FILL_KERNEL,
        )
        style.caption(ax, note, left + width / 2, 5.5, SPAN)
    for left in lefts[1:]:
        style.arrow(ax, (left - gap, 6.95), (left, 6.95))

    style.text(
        ax,
        "Take reg at face value and you map address 0. A wrong mapping fails two ways and only\n"
        "one of them is loud: an unbacked address raises a synchronous external abort, and an\n"
        "address that is merely not the device reads plausible zeros with no error at all.",
        (10.0, 3.9),
        size=style.SMALL_SIZE,
        color=style.ACCENT_COLOR,
        valign="top",
    )
    style.text(
        ax,
        "Which is why probe reads the identity register and refuses to continue unless it "
        "matches.",
        (10.0, 1.5),
        size=style.SMALL_SIZE,
        color=style.MUTED_COLOR,
    )


ADDRESS_TRANSLATION = Diagram(_address_translation, canvas=(0.0, 0.9, 20.0, 10.0))


# ----------------------------------------------------------------------------------------
# L08 - one interrupt, three numbers
# ----------------------------------------------------------------------------------------

_NUMBERS = (
    (
        "Device tree",
        str(measured.IRQ_DT_CELL),
        "written by whoever\ndescribed the board",
        style.FILL_DEVICE,
    ),
    ("GIC", str(measured.IRQ_GIC), "the controller's own\nhardware number", style.FILL_KERNEL),
    (
        "Linux",
        str(measured.IRQ_LINUX),
        "allocated at run time,\nand not derived from either",
        style.FILL_ACCENT,
    ),
)


def _irq_numbers(ax) -> None:
    style.title(ax, "One interrupt, three numbers, none of them interchangeable", (10.0, 9.4))

    # The gap between two boxes is about two and a half units wide, which is not enough for a
    # label. So the arrow labels go above the row, where nothing else is drawn and they can
    # overhang the boxes without touching anything.
    width = 4.6
    lefts, gap = style.row_lefts([width] * 3, SPAN)
    for (space, number, note, fill), left in zip(_NUMBERS, lefts):
        style.box(ax, (left, 5.9), (width, 2.2), fill=fill)
        centre = left + width / 2
        style.text(ax, space, (centre, 7.6), size=style.SMALL_SIZE, color=style.MUTED_COLOR)
        style.text(ax, number, (centre, 6.6), size=style.TITLE_SIZE + 6, weight=style.TITLE_WEIGHT)
        style.caption(ax, note, centre, 5.4, SPAN, color=style.LINE_COLOR)

    joins = [(lefts[i] + width, lefts[i + 1]) for i in range(2)]
    labels = (
        ("+ 32, the SPI base", style.LINE_COLOR, style.ARROW_WIDTH),
        ("no arithmetic at all", style.ACCENT_COLOR, style.ACCENT_WIDTH),
    )
    for (start_x, end_x), (label, color, weight) in zip(joins, labels):
        style.arrow(ax, (start_x, 7.0), (end_x, 7.0), color=color, width=weight)
        style.text(
            ax,
            label,
            ((start_x + end_x) / 2, 8.4),
            size=style.SMALL_SIZE,
            color=color,
            valign="bottom",
        )

    style.text(
        ax,
        "All three appear at once on one line of /proc/interrupts. The Linux number is an "
        "index\ninto a table, so booting with a different set of devices changes it; anything "
        "that\nhard-codes it is wrong.",
        (10.0, 3.6),
        size=style.SMALL_SIZE,
        valign="top",
    )


IRQ_NUMBERS = Diagram(_irq_numbers, canvas=(0.0, 1.2, 20.0, 10.2))
