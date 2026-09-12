"""Charts of numbers this course actually measured.

Every value comes from `measured.py`, which cites the appendix that publishes it. Nothing here is
modelled and nothing is illustrative: if a chart shows a bar, a reader can rebuild that bar by
running the lab that produced it.

That is also why several of these charts are ugly in a specific way. The interesting result is
usually the one that refuses to be a smooth line: two sleeps that cost exactly the same, a race
that is invisible until it is not, a kernel that wins one column and loses the other.
"""

from __future__ import annotations

import measured
import style
from style import Plot

# ----------------------------------------------------------------------------------------
# L03 - three measurements of one change
# ----------------------------------------------------------------------------------------


def _ikconfig_sizes(ax) -> None:
    labels = ("content\nof configs.o", "vmlinux\nsection total", "arm64\nImage")
    values = (measured.IKCONFIG_CONTENT, measured.IKCONFIG_SECTIONS, measured.IKCONFIG_IMAGE)
    colors = (style.MUTED_COLOR, style.ACCENT_COLOR_2, style.ACCENT_COLOR)

    bars = ax.bar(range(3), values, width=0.6, color=colors, zorder=3)
    style.bar_labels(ax, bars, values)

    ax.set_xticks(range(3))
    ax.set_xticklabels(labels)
    ax.set_ylim(0, max(values) * 1.62)
    style.style_axes(ax, ylabel="bytes removed with CONFIG_IKCONFIG")
    style.plot_title(ax, "Removing one option, measured three ways")

    # The gaps are alignment, not code, and saying so is the point of the figure. Written as
    # plain text in the headroom rather than as arrows: an arrow into a bar top lands on the
    # bar's own value label, and a note beside a bar gets drawn over the next one.
    notes = (
        (
            "sections: page alignment. .rodata moved nine pages\n"
            "for 34,058 bytes; .text a whole page for 76.",
            style.ACCENT_COLOR_2,
        ),
        (
            "Image: 64 KiB segment alignment, so it cannot\nresolve any change smaller than that.",
            style.ACCENT_COLOR,
        ),
    )
    for index, (note, color) in enumerate(notes):
        ax.text(
            -0.45,
            max(values) * (1.52 - index * 0.22),
            note,
            ha="left",
            va="top",
            fontsize=style.TICK_SIZE,
            family=style.PLOT_FONT,
            color=color,
        )


IKCONFIG_SIZES = Plot(_ikconfig_sizes, size=(7.6, 4.6))


# ----------------------------------------------------------------------------------------
# L05 - five calls against a 256-byte FIFO
# ----------------------------------------------------------------------------------------


def _fifo_sequence(ax) -> None:
    steps = measured.FIFO_SEQUENCE
    positions = range(len(steps))
    asked = [count for _, count, _, _ in steps]
    # The failed call has no byte count at all, which is the distinction the chart has to keep:
    # -EAGAIN is not "zero bytes", and drawing it as a zero-height bar would say it was.
    got = [(returned or 0) for _, _, returned, _ in steps]

    width = 0.38
    ax.bar(
        [p - width / 2 for p in positions],
        asked,
        width,
        label="asked for",
        color=style.MUTED_COLOR,
        zorder=3,
    )
    bars = ax.bar(
        [p + width / 2 for p in positions],
        got,
        width,
        label="returned",
        color=style.ACCENT_COLOR,
        zorder=3,
    )
    for bar, (_, _, returned, _) in zip(bars, steps):
        if returned is None:
            continue
        ax.annotate(
            str(returned),
            xy=(bar.get_x() + bar.get_width() / 2, returned),
            xytext=(0, 3),
            textcoords="offset points",
            ha="center",
            fontsize=style.TICK_SIZE,
            family=style.PLOT_FONT,
        )

    failed = [i for i, (_, _, r, _) in enumerate(steps) if r is None][0]
    ax.annotate(
        measured.FIFO_ERROR_LABEL,
        xy=(failed + width / 2, 12),
        ha="center",
        fontsize=style.TICK_SIZE,
        family=style.PLOT_FONT,
        color=style.ACCENT_COLOR,
        weight="bold",
    )

    ax.axhline(
        measured.FIFO_CAPACITY,
        color=style.ACCENT_COLOR_2,
        linewidth=style.CONSTRUCTION_WIDTH,
        linestyle="--",
        zorder=2,
    )
    # Left-aligned above the first pair, which is the only place on this chart with room: the
    # right-hand end is where the 256-byte bars and their labels are.
    ax.annotate(
        f"capacity {measured.FIFO_CAPACITY}",
        xy=(-0.45, measured.FIFO_CAPACITY + 12),
        ha="left",
        fontsize=style.TICK_SIZE,
        family=style.PLOT_FONT,
        color=style.ACCENT_COLOR_2,
    )

    ax.set_xticks(list(positions))
    ax.set_xticklabels(
        [f"{i + 1}. {call}\nlevel after: {level}" for i, (call, _, _, level) in enumerate(steps)]
    )
    ax.set_ylim(0, 580)  # The two reads ask for 512, and a clipped bar reads as a broken chart.
    style.style_axes(ax, ylabel="bytes")
    style.plot_title(ax, "A short write is not an error, and an empty FIFO is not end of file")
    style.legend(ax, loc="upper left")


FIFO_SEQUENCE = Plot(_fifo_sequence, size=(8.4, 4.6))


# ----------------------------------------------------------------------------------------
# L07 - a race that is correct every time, until it is not
# ----------------------------------------------------------------------------------------


def _race_loss(ax) -> None:
    rows = measured.RACE_BY_SIZE
    positions = range(len(rows))
    means = [sum(runs) / len(runs) for _, _, runs in rows]

    ax.bar(
        positions, means, width=0.55, color=style.ACCENT_COLOR, zorder=3, label="mean of three runs"
    )
    for position, (_, _, runs) in zip(positions, rows):
        ax.plot(
            [position] * len(runs),
            runs,
            marker="o",
            linestyle="none",
            color=style.LINE_COLOR,
            markersize=5,
            zorder=4,
            label="individual runs" if position == 0 else None,
        )

    ax.set_xticks(list(positions))
    ax.set_xticklabels([f"{per:,}\nper thread" for per, _, _ in rows])
    ax.set_ylim(0, 42)
    style.style_axes(ax, ylabel="increments lost, per cent")
    style.plot_title(
        ax, f"{measured.RACE_THREADS} threads, one unlocked counter, released together"
    )

    style.annotate(
        ax,
        "correct every single time,\nand exactly as broken",
        xy=(0.5, 0.6),
        xytext=(0.2, 17),
        color=style.ACCENT_COLOR_2,
    )
    style.legend(ax, loc="upper left")


RACE_LOSS = Plot(_race_loss, size=(7.6, 4.4))


# ----------------------------------------------------------------------------------------
# L09 - what a sleep costs, against what it was asked for
# ----------------------------------------------------------------------------------------


def _sleep_cost(ax) -> None:
    rows = list(reversed(measured.SLEEP_COST))  # first row at the top
    positions = range(len(rows))
    height = 0.36

    ax.barh(
        [p + height / 2 for p in positions],
        [asked for _, asked, _ in rows],
        height,
        label="asked for",
        color=style.MUTED_COLOR,
        zorder=3,
    )
    bars = ax.barh(
        [p - height / 2 for p in positions],
        [got for _, _, got in rows],
        height,
        label="measured",
        color=style.ACCENT_COLOR,
        zorder=3,
    )
    for bar, (_, _, got) in zip(bars, rows):
        ax.annotate(
            f"{got:,}",
            xy=(got, bar.get_y() + bar.get_height() / 2),
            xytext=(4, 0),
            textcoords="offset points",
            va="center",
            fontsize=style.TICK_SIZE,
            family=style.PLOT_FONT,
        )

    # Staggered heights, in headroom above the bars. On a log axis one, two and four jiffies sit
    # a tenth of the width apart, which is narrower than the labels are wide.
    # Two lines, not three. A one-jiffy line sits a tenth of the width from the two-jiffy line,
    # so their labels overlap at any stagger, and nothing measured here lands on it anyway.
    for index, jiffies in enumerate((2, 4)):
        ax.axvline(
            jiffies * measured.JIFFY_US,
            color=style.ACCENT_COLOR_2,
            linewidth=style.CONSTRUCTION_WIDTH,
            linestyle="--",
            zorder=2,
        )
        ax.annotate(
            f"{jiffies} jiffy" if jiffies == 1 else f"{jiffies} jiffies",
            xy=(jiffies * measured.JIFFY_US, len(rows) + (0.55 if index % 2 else 0.05)),
            ha="center",
            va="bottom",
            fontsize=style.TICK_SIZE,
            family=style.PLOT_FONT,
            color=style.ACCENT_COLOR_2,
        )

    ax.set_yticks(list(positions))
    ax.set_yticklabels([name for name, _, _ in rows], family=style.FONT)
    ax.set_xscale("log")
    ax.set_xlim(60, 60_000)
    ax.set_ylim(-0.7, len(rows) + 1.1)
    style.style_axes(ax, xlabel="microseconds (log scale)", grid="x")
    style.plot_title(ax, f"At HZ={measured.HZ}, msleep(1) and msleep(4) cost the same")
    style.legend(ax, loc="lower right")


SLEEP_COST = Plot(_sleep_cost, size=(7.8, 4.6))


# ----------------------------------------------------------------------------------------
# L11 - what it costs to read one sysfs attribute
# ----------------------------------------------------------------------------------------


def _sysfs_cost(ax) -> None:
    rows = measured.SYSFS_COST
    labels = [name.replace("`", "") for name, _, _ in rows]
    rates = [rate for _, _, rate in rows]

    bars = ax.bar(
        range(len(rows)),
        rates,
        width=0.5,
        color=(style.ACCENT_COLOR_2, style.ACCENT_COLOR),
        zorder=3,
    )
    for bar, (_, per_read, rate) in zip(bars, rows):
        ax.annotate(
            f"{rate:,} reads/s\n{per_read:,} us each",
            xy=(bar.get_x() + bar.get_width() / 2, rate),
            xytext=(0, 4),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=style.TICK_SIZE,
            family=style.PLOT_FONT,
        )

    ax.axhline(
        measured.DEVICE_SAMPLE_RATE,
        color=style.LINE_COLOR,
        linewidth=style.CONSTRUCTION_WIDTH,
        linestyle="--",
        zorder=2,
    )
    style.annotate(
        ax,
        f"the device produces\n{measured.DEVICE_SAMPLE_RATE} samples a second",
        xy=(0.62, measured.DEVICE_SAMPLE_RATE),
        xytext=(0.48, 190),
        halign="center",
    )

    ax.set_xticks(range(len(rows)))
    ax.set_xticklabels(labels)
    ax.set_yscale("log")
    ax.set_ylim(10, 12_000)
    style.style_axes(ax, ylabel="reads per second (log scale)")
    style.plot_title(ax, "A shell cannot monitor a device above about 30 Hz")


SYSFS_COST = Plot(_sysfs_cost, size=(6.8, 4.4))


# ----------------------------------------------------------------------------------------
# L12 - the trade, in two panels because the columns disagree
# ----------------------------------------------------------------------------------------


def _latency(axes) -> None:
    loads = ("idle", "busy")
    kernels = ("PREEMPT", "PREEMPT_RT")
    colors = (style.ACCENT_COLOR_2, style.ACCENT_COLOR)

    for ax, column, heading, better in (
        (axes[0], 2, "Mean latency", "PREEMPT is lower"),
        (axes[1], 3, "Worst case", "PREEMPT_RT is lower"),
    ):
        width = 0.34
        for index, (kernel, color) in enumerate(zip(kernels, colors)):
            values = [
                row[column] for row in measured.LATENCY if row[0] == kernel and row[1] in loads
            ]
            offset = (index - 0.5) * width
            bars = ax.bar(
                [p + offset for p in range(len(loads))],
                values,
                width,
                label=kernel,
                color=color,
                zorder=3,
            )
            style.bar_labels(ax, bars, values)

        ax.set_xticks(range(len(loads)))
        ax.set_xticklabels(loads)
        ax.set_ylim(0, max(row[column] for row in measured.LATENCY) * 1.3)
        style.style_axes(ax, ylabel="microseconds" if column == 2 else "")
        style.plot_title(ax, f"{heading}: {better}")
        style.legend(ax, loc="upper left")

    # The repeat is what stops the reader carrying a factor away from this figure.
    first, second = measured.LATENCY_REPEAT_WORST
    axes[1].annotate(
        f"the same PREEMPT measurement,\nrepeated: {second:,} us",
        xy=(-0.17, first * 0.75),
        xytext=(-0.42, first * 1.75),
        fontsize=style.TICK_SIZE,
        family=style.PLOT_FONT,
        color=style.LINE_COLOR,
        arrowprops={
            "arrowstyle": "->",
            "color": style.LINE_COLOR,
            "linewidth": style.CONSTRUCTION_WIDTH,
        },
    )


LATENCY = Plot(_latency, size=(9.6, 4.6), panels=2)
