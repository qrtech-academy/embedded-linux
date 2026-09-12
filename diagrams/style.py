"""Shared drawing style and rendering plumbing for the lecture figures.

Every visual constant lives here, so restyling every figure at once is a single edit. Figure
modules describe geometry and data; they never choose a color, a line weight or an output size.

There are two kinds of figure, and they are rendered differently:

* `Diagram` is block art drawn onto a declared canvas in abstract units, at a fixed number of
  inches per unit. Declaring the canvas rather than cropping to the content is what lets two
  figures read in sequence line up with each other, and what keeps a label the same size in a
  crowded figure as in a sparse one.
* `Plot` is a matplotlib chart of measured numbers, drawn onto a page in inches and laid out by
  `tight_layout`. Every number in one comes from `measured.py`, never from this file.
"""

from __future__ import annotations

import io
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import matplotlib

matplotlib.use("Agg")  # Render straight to file; there is no display in WSL or in CI.

import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import FancyArrowPatch, Rectangle  # noqa: E402
from PIL import Image  # noqa: E402

# ----------------------------------------------------------------------------------------
# Colors
# ----------------------------------------------------------------------------------------
LINE_COLOR = "black"

# The one thing the figure is about: the register that is read, the update that is lost, the
# option that is dropped. Used sparingly, because a figure where everything is accented has
# emphasised nothing.
ACCENT_COLOR = "#c00000"

# A second ink, for the other half of a comparison. Blue rather than green because red/green is
# the pair most colour vision deficiencies confuse, and several figures here put the two side by
# side and ask the reader to tell them apart.
ACCENT_COLOR_2 = "#0050b3"

MUTED_COLOR = "#6b6b6b"  # Context: something present but not the subject.
GRID_COLOR = "#d9d9d9"
BACKGROUND = "white"

# Flat fills for boxes. Light enough that black text on them stays readable, which is the only
# constraint that matters; these are not decoration.
FILL_PLAIN = "#f2f2f2"  # An ordinary block.
FILL_KERNEL = "#e4ecf7"  # Anything on the kernel side of the syscall boundary.
FILL_USER = "#f7efe4"  # Anything in userspace.
FILL_DEVICE = "#e8f0e8"  # Hardware, or the emulator standing in for it.
FILL_ACCENT = "#f7e4e4"  # The block the figure is about.

SERIES_COLORS = (ACCENT_COLOR, ACCENT_COLOR_2, MUTED_COLOR)

# ----------------------------------------------------------------------------------------
# Line weights
# ----------------------------------------------------------------------------------------
BOX_WIDTH = 2.0  # A block boundary.
ARROW_WIDTH = 1.8  # A flow from one block to the next.
ACCENT_WIDTH = 2.2  # Anything drawn in an accent color.
RULE_WIDTH = 2.6  # A boundary that matters: the syscall line, a privilege split.
CONSTRUCTION_WIDTH = 1.2  # The dashed lines that drop a marker onto its axes.
GRID_WIDTH = 0.8

# ----------------------------------------------------------------------------------------
# Text. Identifiers are monospace so they read as the identifiers they are; prose on a plot is
# proportional, because an axis label is a sentence rather than a symbol.
# ----------------------------------------------------------------------------------------
FONT = "monospace"
PLOT_FONT = "DejaVu Sans"
FONT_SIZE = 13
SMALL_SIZE = 11
LABEL_SIZE = 12
TICK_SIZE = 11
TITLE_SIZE = 15
TITLE_WEIGHT = "bold"

# ----------------------------------------------------------------------------------------
# Output geometry
# ----------------------------------------------------------------------------------------

# The default canvas for a diagram, (xmin, ymin, xmax, ymax). Most figures declare their own;
# this is a floor rather than a house size.
CANVAS = (0.0, 0.0, 20.0, 8.0)

# Half an inch per unit, so a 13-point monospace character is about 0.22 units wide. That ratio
# is the whole reason these numbers are here: `fit_width` below turns a label into the box width
# it needs, and a figure that guesses its box widths instead is a figure whose sublabels hang out
# over the border. They do, and it is invisible from the code.
INCHES_PER_UNIT = 0.5
DPI = 110  # A 20-unit-wide canvas is 10 inches, so 1100 px: wide enough to read on GitHub.

PLOT_SIZE = (7.2, 4.2)  # The default page for a plot, in inches.

# Line art and flat fills on white use a few hundred colors at most, so a palette beats 32-bit
# RGBA: a third of the file size, and lossless for a figure already inside 256 colors. Median cut
# is deterministic, which is what keeps a rebuild byte-identical.
PALETTE_COLORS = 256

# The diagram text is monospace, so a string's width is its length times one character. DejaVu
# Sans Mono advances 0.602 em per character; 72 points to the inch.
CHAR_ASPECT = 0.602

DiagramBuilder = Callable[["plt.Axes"], None]
PlotBuilder = Callable[..., None]


@dataclass(frozen=True)
class Diagram:
    """One block diagram: how to draw it, and the canvas it is drawn onto."""

    draw: DiagramBuilder
    canvas: tuple[float, float, float, float] = field(default=CANVAS)


@dataclass(frozen=True)
class Plot:
    """One chart of measured numbers: how to draw it, its page, and how many panels.

    A multi-panel plot hands its builder a list of axes rather than one, which is what lets two
    kernels be drawn side by side on axes guaranteed to share their limits.
    """

    draw: PlotBuilder
    size: tuple[float, float] = field(default=PLOT_SIZE)
    panels: int = 1


# ----------------------------------------------------------------------------------------
# Diagram helpers
# ----------------------------------------------------------------------------------------


def text_width(string: str, size: float = FONT_SIZE) -> float:
    """Width of a monospace string in canvas units, for laying out around a label."""
    return len(string) * size * CHAR_ASPECT / (72 * INCHES_PER_UNIT)


def text_height(size: float = FONT_SIZE) -> float:
    """Cap-to-descender height of a line of text, in canvas units."""
    return size / (72 * INCHES_PER_UNIT)


def fit_width(
    label: str = "", sublabel: str = "", pad: float = 1.0, label_size: float = FONT_SIZE
) -> float:
    """The box width that holds `label` and `sublabel` without either touching the border.

    Use this rather than choosing a width. A sublabel is routinely longer than the name above it,
    a name is routinely longer than the reader expects, and a box that is one character too
    narrow looks fine in the source and broken in the PNG.
    """
    return max(text_width(label, label_size), text_width(sublabel, SMALL_SIZE)) + pad


def row_widths(entries, pad: float = 1.0, label_size: float = FONT_SIZE) -> list[float]:
    """Widths for a row of boxes, each sized to its own (label, sublabel) pair."""
    return [fit_width(label, sublabel, pad, label_size) for label, sublabel in entries]


def row_lefts(widths: list[float], span: tuple[float, float]) -> tuple[list[float], float]:
    """Left edges for a row of boxes of the given widths, spread evenly across `span`.

    Returns the positions and the gap between neighbours, since the gap is where the arrows
    between the boxes go. A negative gap means the row does not fit and the figure needs shorter
    labels or a wider canvas; that is a bug in the figure, so it raises rather than overlapping.
    """
    left, right = span
    slack = (right - left) - sum(widths)
    gap = slack / (len(widths) - 1) if len(widths) > 1 else 0.0
    if gap < 0:
        raise ValueError(
            f"row of {len(widths)} boxes needs {sum(widths):.1f} units, span is "
            f"{right - left:.1f}"
        )
    positions, x = [], left
    for width in widths:
        positions.append(x)
        x += width + gap
    return positions, gap


def swatch_legend(
    ax, entries, y: float, span: tuple[float, float], size: float = SMALL_SIZE
) -> None:
    """A row of filled squares with labels, for a figure whose blocks are colour-coded."""
    widths = [text_width(label, size) + 1.4 for label, _, _ in entries]
    lefts, _ = row_lefts(widths, span)
    for (label, fill, dashed), left, width in zip(entries, lefts, widths):
        ax.add_patch(
            Rectangle(
                (left, y),
                0.85,
                0.85,
                facecolor=fill,
                edgecolor=LINE_COLOR,
                linewidth=CONSTRUCTION_WIDTH,
                linestyle="--" if dashed else "-",
                zorder=2,
            )
        )
        text(ax, label, (left + 1.15, y + 0.42), halign="left", size=size)


def text(
    ax,
    string: str,
    pos: tuple[float, float],
    halign: str = "center",
    valign: str = "center",
    size: float = FONT_SIZE,
    weight: str = "normal",
    color: str = LINE_COLOR,
    family: str = FONT,
    rotation: float = 0.0,
) -> None:
    """Draw text at an exact point on the canvas."""
    ax.text(
        pos[0],
        pos[1],
        string,
        fontsize=size,
        family=family,
        weight=weight,
        color=color,
        ha=halign,
        va=valign,
        rotation=rotation,
        zorder=4,
    )


def fit_x(string: str, x: float, span: tuple[float, float], size: float = SMALL_SIZE) -> float:
    """Nudge a centred text block's x so no line of it crosses the edge of `span`.

    The caption under the leftmost or rightmost box in a row is the one that runs off the
    canvas, because it is centred on a box that is already at the margin. Clamping is better
    than shortening the words: the figure stays readable and the caption stays true.
    """
    half = max(text_width(line, size) for line in string.split("\n")) / 2
    if half * 2 >= span[1] - span[0]:
        return (span[0] + span[1]) / 2
    return min(max(x, span[0] + half), span[1] - half)


def caption(
    ax,
    string: str,
    x: float,
    y: float,
    span: tuple[float, float],
    size: float = SMALL_SIZE,
    color: str = MUTED_COLOR,
) -> None:
    """A short note under a box, clamped so that it stays on the canvas."""
    text(ax, string, (fit_x(string, x, span, size), y), size=size, color=color, valign="top")


def title(ax, string: str, pos: tuple[float, float]) -> None:
    """Draw a figure's own heading."""
    text(ax, string, pos, size=TITLE_SIZE, weight=TITLE_WEIGHT)


def box(
    ax,
    xy: tuple[float, float],
    size: tuple[float, float],
    label: str = "",
    sublabel: str = "",
    fill: str = FILL_PLAIN,
    edge: str = LINE_COLOR,
    width: float = BOX_WIDTH,
    text_color: str = LINE_COLOR,
    label_size: float = FONT_SIZE,
    dashed: bool = False,
) -> tuple[float, float]:
    """Draw a labelled block with its lower-left corner at `xy`, and return its centre.

    Returning the centre is what lets a caller hang an arrow off a box without recomputing the
    geometry, which is the single most common source of a figure that is one unit out.
    """
    # A label wider than its box is the single most common way one of these figures ships
    # broken, and it is invisible from the code: matplotlib centres the text and lets it hang out
    # over both borders without complaint. So refuse, and name the label that did not fit.
    for string, size_pt in ((label, label_size), (sublabel, SMALL_SIZE)):
        if not string:
            continue
        widest = max(text_width(line, size_pt) for line in string.split("\n"))
        if widest > size[0] - 0.25:
            raise ValueError(
                f"label {string.splitlines()[0]!r} needs {widest:.2f} units, box is "
                f"{size[0]:.2f}: split it over two lines or widen the box"
            )

    ax.add_patch(
        Rectangle(
            xy,
            size[0],
            size[1],
            facecolor=fill,
            edgecolor=edge,
            linewidth=width,
            linestyle="--" if dashed else "-",
            zorder=2,
        )
    )
    centre = (xy[0] + size[0] / 2, xy[1] + size[1] / 2)
    if label and sublabel:
        # Stack the two blocks and centre the pair, counting lines. Offsetting by a fixed
        # fraction of one line height instead assumes both labels are one line, and silently
        # overlaps them the first time either is two: matplotlib grows a multi-line label
        # symmetrically about the point it is given.
        label_lines = len(label.split("\n"))
        sub_lines = len(sublabel.split("\n"))
        label_block = label_lines * text_height(label_size)
        sub_block = sub_lines * text_height(SMALL_SIZE)
        gap = 0.45 * text_height(SMALL_SIZE)
        total = label_block + gap + sub_block
        if total > size[1]:
            raise ValueError(
                f"label {label.splitlines()[0]!r} plus its sublabel need {total:.2f} units of "
                f"height, box is {size[1]:.2f}"
            )
        text(
            ax,
            label,
            (centre[0], centre[1] + total / 2 - label_block / 2),
            size=label_size,
            color=text_color,
        )
        text(
            ax,
            sublabel,
            (centre[0], centre[1] - total / 2 + sub_block / 2),
            size=SMALL_SIZE,
            color=MUTED_COLOR,
        )
    elif label:
        text(ax, label, centre, size=label_size, color=text_color)
    return centre


def arrow(
    ax,
    start: tuple[float, float],
    end: tuple[float, float],
    color: str = LINE_COLOR,
    width: float = ARROW_WIDTH,
    dashed: bool = False,
    both: bool = False,
    curve: float = 0.0,
) -> None:
    """Draw a flow arrow from `start` to `end`.

    `curve` bends the arrow, for the cases where a straight line would cross a box. Positive
    curves to the left of the direction of travel.
    """
    ax.add_patch(
        FancyArrowPatch(
            start,
            end,
            arrowstyle="<->" if both else "-|>",
            mutation_scale=13,
            color=color,
            linewidth=width,
            linestyle="--" if dashed else "-",
            connectionstyle=f"arc3,rad={curve}",
            shrinkA=0,
            shrinkB=0,
            zorder=3,
        )
    )


def rule(
    ax,
    y: float,
    span: tuple[float, float],
    label: str = "",
    color: str = LINE_COLOR,
    dashed: bool = True,
) -> None:
    """Draw a horizontal boundary across the figure, such as the syscall line."""
    ax.plot(
        [span[0], span[1]],
        [y, y],
        color=color,
        linewidth=RULE_WIDTH,
        linestyle=(0, (6, 4)) if dashed else "-",
        zorder=1,
    )
    if label:
        text(
            ax,
            label,
            (span[1], y + text_height(SMALL_SIZE) * 0.5),
            halign="right",
            valign="bottom",
            size=SMALL_SIZE,
            color=color,
        )


# ----------------------------------------------------------------------------------------
# Plot helpers
# ----------------------------------------------------------------------------------------


def style_axes(ax, xlabel: str = "", ylabel: str = "", grid: str = "y") -> None:
    """Apply the house look to one set of axes.

    `grid` selects which gridlines are drawn: "y" for a chart read across categories, "x" for the
    same chart drawn horizontally, "both" for a curve read off two axes, and "none" where the
    gridlines would cross the artwork.
    """
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(LINE_COLOR)

    if xlabel:
        ax.set_xlabel(xlabel, fontsize=LABEL_SIZE, family=PLOT_FONT)
    if ylabel:
        ax.set_ylabel(ylabel, fontsize=LABEL_SIZE, family=PLOT_FONT)

    ax.tick_params(labelsize=TICK_SIZE, colors=LINE_COLOR)
    for label in ax.get_xticklabels() + ax.get_yticklabels():
        label.set_family(PLOT_FONT)

    if grid != "none":
        ax.grid(True, axis=grid, color=GRID_COLOR, linewidth=GRID_WIDTH)
        # Gridlines behind the artwork, always. A gridline crossing a bar reads as a boundary
        # inside the bar, which is exactly the thing the reader is trying to compare.
        ax.set_axisbelow(True)


def plot_title(ax, string: str) -> None:
    """Title one set of axes, in the plot font."""
    ax.set_title(string, fontsize=LABEL_SIZE, family=PLOT_FONT, weight=TITLE_WEIGHT)


def legend(ax, loc: str = "best", ncol: int = 1) -> None:
    """Draw a frameless legend in the plot font."""
    handles, labels = ax.get_legend_handles_labels()
    if not handles:
        return
    ax.legend(
        handles,
        labels,
        loc=loc,
        ncol=ncol,
        frameon=False,
        prop={"family": PLOT_FONT, "size": TICK_SIZE},
    )


def annotate(ax, string: str, xy, xytext, color: str = LINE_COLOR, halign: str = "left") -> None:
    """Point at something on a plot and say what it is."""
    ax.annotate(
        string,
        xy=xy,
        xytext=xytext,
        fontsize=TICK_SIZE,
        family=PLOT_FONT,
        color=color,
        ha=halign,
        arrowprops={"arrowstyle": "->", "color": color, "linewidth": CONSTRUCTION_WIDTH},
    )


def bar_labels(
    ax, bars, values, fmt="{:,.0f}", color: str = LINE_COLOR, size: float = TICK_SIZE
) -> None:
    """Write each bar's value above it.

    Every one of these charts exists because an appendix quotes the number, so the number has to
    be readable off the figure rather than estimated from the axis.
    """
    for bar, value in zip(bars, values):
        ax.annotate(
            fmt.format(value),
            xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
            xytext=(0, 3),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=size,
            family=PLOT_FONT,
            color=color,
        )


# ----------------------------------------------------------------------------------------
# Rendering
# ----------------------------------------------------------------------------------------


def _write(fig, paths: list[Path]) -> None:
    """Quantize one rendered figure and write it to every path in `paths`."""
    # Render to memory rather than to disk: the palette pass below still has to run, and the
    # figure is written once per path afterwards.
    buffer = io.BytesIO()
    try:
        fig.savefig(buffer, format="png", dpi=DPI, facecolor=BACKGROUND)
    finally:
        # Close even on failure; matplotlib figures are a process-wide resource.
        plt.close(fig)

    # The background is opaque, so dropping the alpha channel costs nothing.
    image = Image.open(buffer).convert("RGB").quantize(colors=PALETTE_COLORS)

    # One drawing, written to every lecture that embeds it, which is what keeps the copies
    # identical. Directories are created on demand so a new lecture needs no setup.
    for path in paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, "PNG", optimize=True)


def _render_diagram(diagram: Diagram, paths: list[Path]) -> None:
    """Draw a block diagram onto its declared canvas and write it out."""
    xmin, ymin, xmax, ymax = diagram.canvas
    fig, ax = plt.subplots(
        figsize=((xmax - xmin) * INCHES_PER_UNIT, (ymax - ymin) * INCHES_PER_UNIT)
    )

    diagram.draw(ax)

    # Pin the view to the declared canvas instead of letting matplotlib fit the content, and
    # drop every margin so the saved pixels are exactly the canvas.
    ax.set_xlim(xmin, xmax)
    ax.set_ylim(ymin, ymax)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.subplots_adjust(left=0, bottom=0, right=1, top=1)
    _write(fig, paths)


def _render_plot(plot: Plot, paths: list[Path]) -> None:
    """Draw a matplotlib figure onto its declared page and write it out."""
    fig, axes = plt.subplots(1, plot.panels, figsize=plot.size, squeeze=False)
    panels = list(axes[0])

    # A one-panel plot gets an axes, not a list of one. Every builder here would otherwise open
    # with the same unpacking line.
    plot.draw(panels[0] if plot.panels == 1 else panels)

    fig.tight_layout()
    _write(fig, paths)


def render(figure: Diagram | Plot, paths: list[Path]) -> None:
    """Draw a figure and write it to every path in `paths`."""
    if isinstance(figure, Diagram):
        _render_diagram(figure, paths)
    else:
        _render_plot(figure, paths)
