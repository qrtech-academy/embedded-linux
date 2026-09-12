#!/usr/bin/env python3
"""Regenerate the lecture figures.

    python3 diagrams/build.py                     # every figure, into the lecture trees
    python3 diagrams/build.py boot_chain          # one figure
    python3 diagrams/build.py --outdir /tmp/x     # preview, without touching the repo
    python3 diagrams/build.py --list              # what can be built

Adding a figure: write a builder in one of the modules next to this one, then add an entry to
FIGURES below naming every path that should receive it.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import flow  # noqa: E402
import measurements  # noqa: E402
import structure  # noqa: E402
import style  # noqa: E402
import timing  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def exam_images() -> Path:
    """The exam's own image directory.

    Two figures live here rather than in a lecture: they are the worked answers to L03's and
    L05's cross-checks, and printing an answer beside the exercise that asks for it would make
    the exercise pointless. In the solutions to the papers that ask the same question, they are
    exactly what a marker wants.
    """
    return ROOT / "exam/images"


def images(lecture: str) -> Path:
    """The image directory of one lecture's appendix, e.g. `images("L01")`."""
    return ROOT / "lectures" / lecture / "appendix/images"


# figure name -> (figure, output paths). A figure with several paths is one that several lectures
# embed; listing them here is what keeps those copies identical rather than merely similar.
FIGURES: dict[str, tuple[object, list[Path]]] = {
    "boot_chain": (structure.BOOT_CHAIN, [images("L01") / "boot_chain.png"]),
    "kernel_interfaces": (structure.KERNEL_INTERFACES, [images("L02") / "kernel_interfaces.png"]),
    "kconfig_flow": (flow.KCONFIG_FLOW, [images("L03") / "kconfig_flow.png"]),
    "ikconfig_sizes": (measurements.IKCONFIG_SIZES, [exam_images() / "ikconfig_sizes.png"]),
    "module_lifecycle": (structure.MODULE_LIFECYCLE, [images("L04") / "module_lifecycle.png"]),
    "fifo_sequence": (measurements.FIFO_SEQUENCE, [exam_images() / "fifo_sequence.png"]),
    "read_contract": (structure.READ_CONTRACT, [images("L05") / "read_contract.png"]),
    "address_translation": (flow.ADDRESS_TRANSLATION, [images("L06") / "address_translation.png"]),
    "lost_update": (timing.LOST_UPDATE, [images("L07") / "lost_update.png"]),
    "race_loss": (measurements.RACE_LOSS, [images("L07") / "race_loss.png"]),
    "irq_numbers": (flow.IRQ_NUMBERS, [images("L08") / "irq_numbers.png"]),
    "ack_ordering": (timing.ACK_ORDERING, [images("L08") / "ack_ordering.png"]),
    "lost_wakeup": (timing.LOST_WAKEUP, [images("L09") / "lost_wakeup.png"]),
    "sleep_cost": (measurements.SLEEP_COST, [images("L09") / "sleep_cost.png"]),
    "device_model": (structure.DEVICE_MODEL, [images("L10") / "device_model.png"]),
    "framework_stack": (structure.FRAMEWORK_STACK, [images("L11") / "framework_stack.png"]),
    "sysfs_cost": (measurements.SYSFS_COST, [images("L11") / "sysfs_cost.png"]),
    "three_timestamps": (timing.THREE_TIMESTAMPS, [images("L12") / "three_timestamps.png"]),
    "latency": (measurements.LATENCY, [images("L12") / "latency.png"]),
}


def main() -> int:
    """Build the figures named on the command line, or all of them."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "figures", nargs="*", metavar="FIGURE", help="Figures to build. Default: all of them."
    )
    parser.add_argument(
        "--outdir", type=Path, help="Write <FIGURE>.png here instead of into the lecture trees."
    )
    parser.add_argument("--list", action="store_true", help="List the known figures and exit.")
    args = parser.parse_args()

    if args.list:
        for name in FIGURES:
            print(name)
        return 0

    # Check every name before drawing anything, so a typo fails at once rather than halfway
    # through a rebuild with some figures already overwritten.
    names = args.figures or list(FIGURES)
    unknown = [name for name in names if name not in FIGURES]
    if unknown:
        parser.error(f"unknown figure(s): {', '.join(unknown)}\nknown: {', '.join(FIGURES)}")

    for name in names:
        figure, paths = FIGURES[name]
        if args.outdir:
            paths = [args.outdir / f"{name}.png"]
        style.render(figure, paths)
        for path in paths:
            print(f"wrote {path.relative_to(ROOT) if ROOT in path.parents else path}")

    return 0


# Run only when executed as a script, never on import, and hand the return value to the shell as
# the exit status.
if __name__ == "__main__":
    raise SystemExit(main())
