# Diagrams

Every figure in this course is drawn from code, so changing a label or a measured number is an
edit and a rebuild rather than a redraw. The PNGs are committed, because GitHub renders the
lectures straight from the repository; nothing here runs when a reader builds a kernel.

## Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r diagrams/requirements.txt
```

`make diagrams` does this for you the first time it runs.

## Rebuilding

```bash
make diagrams                                     # every figure, into the lecture trees
.venv/bin/python diagrams/build.py --list         # what can be built
.venv/bin/python diagrams/build.py boot_chain     # one figure
.venv/bin/python diagrams/build.py --outdir /tmp/preview   # look before overwriting
```

`--outdir` writes `<figure>.png` flat into a directory of your choice and leaves the repository
untouched, which is the sane way to iterate on a figure. **Then open the PNG and look at it.**
Colliding labels, a caption that runs off the canvas and a sublabel sitting on top of the line
above it are all invisible from the code that drew them, and every one of them has happened here.

A rebuild is byte-identical, which is what makes `git diff --exit-code` after `make diagrams`
mean something: a figure whose source changed but whose PNG did not is a failed build rather than
a lecture illustrated with last month's numbers.

## Layout

| File              | What it holds                                                                                                                                     |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `style.py`        | Every colour, weight, font and output size, and the two figure kinds. Restyling everything is one edit here.                                      |
| `measured.py`     | Every number that appears on a chart, with the appendix that publishes it.                                                                        |
| `structure.py`    | Block diagrams: the boot chain, the three kernel interfaces, the module lifecycle, the read contract, the device model, the framework comparison. |
| `flow.py`         | One value through the transformations that change it: a config option, an address, an interrupt number.                                           |
| `timing.py`       | Two things on one time axis: the lost update, the lost wakeup, acknowledgement ordering, the three timestamps.                                    |
| `measurements.py` | Charts of numbers this course measured.                                                                                                           |
| `build.py`        | Figure name to figure plus output paths, and the command line.                                                                                    |

## The two kinds of figure

**A `Diagram`** is block art on a declared canvas in abstract units, at a fixed number of inches
per unit. Declaring the canvas rather than cropping to the content is what lets figures read in
sequence line up, and what keeps a label the same size in a crowded figure as in a sparse one.

**A `Plot`** is a matplotlib chart, on a page in inches, laid out by `tight_layout`. Every number
in one comes from `measured.py`.

## Where the numbers come from

`measured.py` is the single source, and it cites the appendix that publishes each block. **No
figure carries a literal of its own.** A measurement redone is edited there, every chart using it
is redrawn, and the appendix is the only other place to change.

Two charts are written into `exam/images/` rather than into a lecture: `ikconfig_sizes` and
`fifo_sequence` are the worked answers to L03's and L05's cross-checks, and an answer printed
beside the exercise that asks for it makes the exercise pointless. In the solutions to the papers
that ask the same question, they are exactly what a marker wants.

## Adding a figure

1. Write a builder in one of the modules above. A diagram builder takes `(ax)`; a plot builder
   takes `(ax)`, or a list of axes if it declares more than one panel. Wrap it in a
   `style.Diagram` with the canvas it needs, or a `style.Plot` with its page size.
2. Put the geometry in named constants at the top of the module. That is what makes a figure
   cheap to adjust later.
3. If it shows a measured number, add the number to `measured.py` first, with its source.
4. Add an entry to `FIGURES` in `build.py` naming every path the figure is written to. A figure
   embedded by more than one lecture gets more than one path, and writing every copy from one
   source is what keeps them identical.
5. Embed it in the appendix with real alt text describing what the figure shows.
   `ci/markdown.sh` rejects an empty one, and a line that is only an image is exempt from the
   100-column rule, because Markdown has no line-continuation syntax and real alt text is longer
   than that.

## Let the layout helpers refuse

Three of these raise rather than draw something wrong, and each exists because the wrong version
shipped once during authoring and was only caught by opening the PNG:

* **`style.row_lefts`** raises if a row of boxes does not fit its span, instead of overlapping
  them.
* **`style.box`** raises if a label is wider than its box or if a label and sublabel are taller
  than it. Matplotlib centres text and lets it hang out over both borders without complaint.
* **`style.caption`** clamps a caption so it cannot cross the edge of the canvas. The caption
  under the leftmost or rightmost box in a row is the one that runs off, because it is centred on
  a box that is already at the margin.

The general rule: **size boxes from their text with `style.fit_width`, never by choosing a
number.** A sublabel is routinely longer than the name above it, and a box one character too
narrow looks fine in the source.

## Notes

* Figures are written as palette PNGs, not RGBA. Line art and flat fills on white use a few
  hundred colours at most, so this costs nothing visually and roughly halves what gets committed.
  Median cut is deterministic, so a rebuild stays byte-identical.
* There is no schemdraw dependency here, unlike the sibling courses that draw real circuits. This
  course has no schematics: its figures are block diagrams, timelines and charts, all of which
  are rectangles, arrows and axes.
* The figures are black on white, which is hard to read in GitHub's dark theme. So is every other
  image in this repository. If that ever needs fixing, it is a change to the colours in
  `style.py` and nowhere else.
