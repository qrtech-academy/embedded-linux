"""Figures that put two things on the same time axis.

Every bug in the second half of the course is an ordering: two CPUs interleaving inside one
increment, an interrupt arriving between a test and a sleep, an acknowledgement on the wrong side
of the work. Prose describes those one step at a time, which is exactly the wrong shape for them.
"""

from __future__ import annotations

import style
from style import Diagram

SPAN = (0.5, 19.5)

# Two lanes, side by side, with the left margin left free for the time arrow.
_LANE_W = 7.4
_LANE_X = (2.3, 10.3)
_STEP_H = 1.0  # A step with just a label.
_STEP_H_NOTE = 1.6  # A step whose consequence is spelled out under its label.
_STEP_GAP = 0.35


def _lanes(ax, headers, top: float, bottom: float) -> None:
    """Draw the lane headings and the dashed lifelines under them."""
    for (name, fill), left in zip(headers, _LANE_X):
        style.box(ax, (left, top), (_LANE_W, 1.1), name, fill=fill)
        centre = left + _LANE_W / 2
        ax.plot(
            [centre, centre],
            [bottom, top],
            linestyle=(0, (3, 4)),
            color=style.MUTED_COLOR,
            linewidth=style.CONSTRUCTION_WIDTH,
            zorder=1,
        )


def _steps(ax, items, top: float) -> float:
    """Lay a sequence of actions down the lanes from `top`, and return the y it ended at.

    The steps flow rather than sitting on a fixed pitch, because a step that spells out its
    consequence is taller than one that does not, and a fixed pitch would either crowd the tall
    ones or leave the short ones swimming.
    """
    y = top
    for lane, label, accent, note in items:
        height = _STEP_H_NOTE if note else _STEP_H
        y -= height
        # The consequence goes inside the box. Hung off the side, it runs off the canvas: the
        # two lanes already use the full width, and there is no margin left to put it in.
        style.box(
            ax,
            (_LANE_X[lane], y),
            (_LANE_W, height),
            label,
            note,
            fill=style.FILL_ACCENT if accent else style.FILL_PLAIN,
            edge=style.ACCENT_COLOR if accent else style.LINE_COLOR,
            text_color=style.ACCENT_COLOR if accent else style.LINE_COLOR,
            label_size=style.SMALL_SIZE,
            width=style.ACCENT_WIDTH if accent else style.CONSTRUCTION_WIDTH,
        )
        y -= _STEP_GAP
    return y + _STEP_GAP


def _time_arrow(ax, top: float, bottom: float) -> None:
    style.arrow(ax, (1.3, top), (1.3, bottom), color=style.MUTED_COLOR)
    style.text(
        ax,
        "time",
        (0.75, (top + bottom) / 2),
        size=style.SMALL_SIZE,
        color=style.MUTED_COLOR,
        rotation=90,
    )


# ----------------------------------------------------------------------------------------
# L07 - two increments, one of them lost
# ----------------------------------------------------------------------------------------

# (lane, label, accent). counter++ is three instructions, and this is the interleaving that
# turns two of them into one.
_LOST_UPDATE = (
    (0, "load counter -> n", False, ""),
    (1, "load counter -> n", True, "the same n: A has not stored yet"),
    (0, "add 1 -> n+1", False, ""),
    (1, "add 1 -> n+1", False, ""),
    (0, "store n+1", False, ""),
    (1, "store n+1", True, "one increment has vanished"),
)


def _lost_update(ax) -> None:
    style.title(
        ax, "counter++ is three instructions, and nothing keeps them together", (10.0, 13.3)
    )

    # The steps are laid out first, because the lifelines have to stop where they stop. Drawing
    # the lanes first means guessing that y, and a lifeline running on past the last box and down
    # through the caption is what guessing it looks like.
    top = 11.6
    bottom = _steps(ax, _LOST_UPDATE, top - 0.3)
    _lanes(ax, (("CPU A", style.FILL_KERNEL), ("CPU B", style.FILL_KERNEL)), top, bottom)
    _time_arrow(ax, top - 0.3, bottom)

    style.text(
        ax,
        "Both CPUs read the same n, so both store n+1. Two increments happened and the counter\n"
        "advanced by one. At 200 increments per thread this never occurs, because the threads do\n"
        "not overlap for long enough; the bug is identical at every size.",
        (10.0, bottom - 0.6),
        size=style.SMALL_SIZE,
        valign="top",
    )


LOST_UPDATE = Diagram(_lost_update, canvas=(0.0, -1.0, 20.0, 14.0))


# ----------------------------------------------------------------------------------------
# L09 - a wake that arrives before anything is asleep
# ----------------------------------------------------------------------------------------

_LOST_WAKEUP = (
    (0, "test: fifo_empty() -> true", False, ""),
    (1, "push a sample", False, ""),
    (1, "wake_up(&wq)", True, "finds nothing asleep to wake"),
    (0, "set_current_state(INTERRUPTIBLE)", False, ""),
    (0, "schedule()", True, "sleeps until the next wake, if any"),
)


def _lost_wakeup(ax) -> None:
    style.title(ax, "The wake arrives between the test and the sleep", (10.0, 11.3))

    top = 9.6
    bottom = _steps(ax, _LOST_WAKEUP, top - 0.3)
    _lanes(ax, (("The reader", style.FILL_USER), ("The handler", style.FILL_KERNEL)), top, bottom)
    _time_arrow(ax, top - 0.3, bottom)

    style.text(
        ax,
        "wait_event_interruptible closes this by queueing the task and setting its state before\n"
        "it tests the condition, so a wake arriving in the window finds something to wake. It\n"
        "then re-tests in a loop, because a wake does not mean the condition is true.",
        (10.0, bottom - 0.6),
        size=style.SMALL_SIZE,
        valign="top",
    )


LOST_WAKEUP = Diagram(_lost_wakeup, canvas=(0.0, -1.0, 20.0, 12.0))


# ----------------------------------------------------------------------------------------
# L08 - which side of the work the acknowledgement goes on
# ----------------------------------------------------------------------------------------

# (heading, steps, outcome, outcome is survivable). The event always arrives at the same
# instant; only the handler's order differs.
_ORDERINGS = (
    (
        "Clear the status, then drain",
        (
            "clear IRQ_STATUS",
            "an event arrives: status set again,\nand its sample is queued",
            "drain the FIFO, taking the new sample too",
            "return IRQ_HANDLED",
        ),
        "At worst one spurious interrupt\nwith nothing to do. No data lost.",
        True,
    ),
    (
        "Drain, then clear with the value read at entry",
        (
            "drain the FIFO",
            "an event arrives: its sample is queued,\nstatus set again",
            "clear IRQ_STATUS, clearing the new bit too",
            "return IRQ_HANDLED, nothing pending",
        ),
        "A sample sits in the FIFO with\nno interrupt to collect it.",
        False,
    ),
)


def _ack_ordering(ax) -> None:
    style.title(ax, "The event arrives at the same instant either way", (10.0, 13.4))

    width = 9.2
    lefts, _ = style.row_lefts([width] * 2, SPAN)
    for (heading, steps, outcome, ok), left in zip(_ORDERINGS, lefts):
        style.box(
            ax,
            (left, 11.6),
            (width, 1.2),
            heading,
            fill=style.FILL_KERNEL if ok else style.FILL_ACCENT,
            label_size=style.SMALL_SIZE,
        )
        for index, step in enumerate(steps):
            arriving = index == 1
            style.box(
                ax,
                (left + 0.3, 9.6 - index * 2.0),
                (width - 0.6, 1.5),
                step,
                fill=style.FILL_ACCENT if arriving else style.FILL_PLAIN,
                edge=style.ACCENT_COLOR if arriving else style.LINE_COLOR,
                text_color=style.ACCENT_COLOR if arriving else style.LINE_COLOR,
                label_size=style.SMALL_SIZE,
                width=style.ACCENT_WIDTH if arriving else style.CONSTRUCTION_WIDTH,
            )
            if index:
                style.arrow(
                    ax,
                    (left + width / 2, 9.6 - (index - 1) * 2.0),
                    (left + width / 2, 9.6 - index * 2.0 + 1.5),
                    width=style.CONSTRUCTION_WIDTH,
                )
        style.box(
            ax,
            (left, 1.4),
            (width, 1.4),
            outcome,
            fill=style.FILL_DEVICE if ok else style.FILL_ACCENT,
            edge=style.LINE_COLOR if ok else style.ACCENT_COLOR,
            label_size=style.SMALL_SIZE,
        )

    style.text(
        ax,
        "Survivable on the left, not on the right: acknowledge first, then drain, and write back\n"
        "the value you read rather than a mask of everything.",
        (10.0, 0.9),
        size=style.SMALL_SIZE,
        valign="top",
    )


ACK_ORDERING = Diagram(_ack_ordering, canvas=(0.0, -0.6, 20.0, 14.0))


# ----------------------------------------------------------------------------------------
# L12 - three timestamps on one path, taken from two clocks
# ----------------------------------------------------------------------------------------

# The x of each mark is pulled in from the edges far enough that its box, which is 5.2 wide and
# centred on it, still lands inside the canvas.
_MARKS = (
    (3.2, "the device asserts\nits interrupt line", "TS_LO / TS_HI", style.FILL_DEVICE),
    (10.0, "the handler runs", "ktime_get()", style.FILL_KERNEL),
    (16.8, "read() returns to\nthe program", "CLOCK_MONOTONIC", style.FILL_USER),
)


def _three_timestamps(ax) -> None:
    style.title(ax, "Three timestamps, and only one interval you can quote", (10.0, 10.4))

    axis_y = 6.4
    ax.plot(
        [1.0, 19.0], [axis_y, axis_y], color=style.LINE_COLOR, linewidth=style.ARROW_WIDTH, zorder=1
    )

    for x, what, clock, fill in _MARKS:
        ax.plot(
            [x, x],
            [axis_y - 0.35, axis_y + 0.35],
            color=style.LINE_COLOR,
            linewidth=style.ARROW_WIDTH,
            zorder=3,
        )
        style.box(
            ax,
            (x - 2.6, axis_y + 1.0),
            (5.2, 1.9),
            what,
            clock,
            fill=fill,
            label_size=style.SMALL_SIZE,
        )

    intervals = (
        (
            3.2,
            10.0,
            4.6,
            "the device clock against the kernel's:\n"
            "a constant, unknown offset, so only the\nspread is usable",
            style.ACCENT_COLOR,
        ),
        (
            10.0,
            16.8,
            4.6,
            "both ends are CLOCK_MONOTONIC,\n" "so this interval is absolute",
            style.ACCENT_COLOR_2,
        ),
    )
    for left, right, y, note, color in intervals:
        style.arrow(ax, (left, y), (right, y), color=color, both=True, width=style.ACCENT_WIDTH)
        style.text(
            ax,
            note,
            ((left + right) / 2, y - 0.4),
            size=style.SMALL_SIZE,
            color=color,
            valign="top",
        )

    style.text(
        ax,
        "Which is why the appendix reports the first as a spread above the best case observed,\n"
        "and the second as a number. Quoting both the same way would be the mistake.",
        (10.0, 1.5),
        size=style.SMALL_SIZE,
        valign="top",
    )


THREE_TIMESTAMPS = Diagram(_three_timestamps, canvas=(0.0, 0.2, 20.0, 11.0))
