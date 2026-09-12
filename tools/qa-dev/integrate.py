#!/usr/bin/env python3
"""Graft the qa-dev device model onto a QEMU source tree.

This is done with targeted edits rather than with a context diff, deliberately. A .patch against
four files in a tree of seventy-five thousand fails on a whitespace change three releases later
and leaves a reader looking at a .rej file, which is a bad first hour of a course. Each edit
below states what it expects to find, refuses to guess when it does not find it, and does nothing
at all when it has already been applied, so running it twice is safe and running it against the
wrong QEMU says so in one line.

Four things have to happen for "-device qa-dev" to work on the virt machine:

    1. The device model and its register map have to be in the tree.
    2. The build has to compile the device model.
    3. The virt machine has to allow the device on its dynamic platform bus. Without this,
       QEMU refuses the device at run time with a message about it not being a dynamic sysbus
       device, which reads like the device is broken rather than unlisted.
    4. Something has to generate the device's device tree node. Without this, QEMU exits with
       "Device qa-dev can not be dynamically instantiated", and, more to the point, L10 has
       nothing to probe from.

The fourth is the one that earns the custom device. QEMU writes the node, with the address and
the interrupt it actually assigned, into the DTB it hands the kernel; so the reader's driver in
L10 finds its hardware the same way a driver on a real board does, and the numbers in the node
are numbers nobody typed anywhere.
"""

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def edit(path, anchor, addition, description, *, after=True, marker=None):
    """Insert `addition` next to `anchor` in `path`, once.

    `marker` is a short string that identifies the addition independently of its exact text. It
    matters: the first version of this script tested for the whole addition verbatim, which meant
    that editing so much as a comment inside the inserted block made the test miss and the block
    got inserted a second time. QEMU then failed to build with a redefinition error pointing at a
    line nobody had touched. Identify an insertion by something that will not change.

    Returns True if the file was changed, False if the addition was already there.
    """
    text = path.read_text()

    if (marker or addition.strip()) in text:
        print(f"  already done: {description}")
        return False

    if anchor not in text:
        fail(
            f"{path}: could not find the anchor for {description}.\n"
            f"       Expected to find: {anchor!r}\n"
            f"       This usually means the QEMU version does not match the pin in "
            f"ci/versions.sh."
        )

    if text.count(anchor) != 1:
        fail(
            f"{path}: the anchor for {description} appears {text.count(anchor)} times; "
            f"it has to be unique."
        )

    replacement = anchor + addition if after else addition + anchor
    path.write_text(text.replace(anchor, replacement))
    print(f"  done: {description}")
    return True


BEGIN = "/* qa-dev: begin generated block. ci/qemu.sh rewrites this; do not edit here. */\n"
END = "/* qa-dev: end generated block. */\n"


def insert_block(path, anchor, block, description):
    """Insert a multi-line `block` before `anchor`, replacing any block inserted before.

    Sentinels rather than a verbatim test, so that editing the block and re-running replaces the
    old one instead of adding a second copy next to it.
    """
    text = path.read_text()

    if BEGIN in text and END in text:
        start = text.index(BEGIN)
        end = text.index(END) + len(END)
        if text[start:end] == BEGIN + block + END:
            print(f"  already done: {description}")
            return False
        text = text[:start] + text[end:]
        print(f"  replacing the previous block: {description}")

    if anchor not in text:
        fail(f"{path}: could not find the anchor for {description}.")

    path.write_text(text.replace(anchor, BEGIN + block + END + anchor))
    print(f"  done: {description}")
    return True


def main():
    if len(sys.argv) != 2:
        fail("usage: integrate.py <path-to-qemu-tree>")

    tree = Path(sys.argv[1]).resolve()
    if not (tree / "hw" / "arm" / "virt.c").is_file():
        fail(f"{tree} does not look like a QEMU source tree.")

    # 1. The source. Copied rather than symlinked, because meson resolves symlinks into the
    #    build directory in ways that make a rebuild after an edit unreliable.
    (tree / "include" / "hw" / "misc").mkdir(parents=True, exist_ok=True)
    shutil.copy2(HERE / "qa-dev.h", tree / "include" / "hw" / "misc" / "qa-dev.h")
    shutil.copy2(HERE / "qa-dev.c", tree / "hw" / "misc" / "qa-dev.c")
    print("  done: copied qa-dev.c and qa-dev.h into the tree")

    # 2. The build. Unconditional rather than behind a CONFIG symbol: adding a Kconfig entry
    #    means editing a fifth file for no benefit, since the device is a plain sysbus device
    #    that costs a couple of kilobytes in the one binary this course builds.
    edit(
        tree / "hw" / "misc" / "meson.build",
        "system_ss.add(when: 'CONFIG_APPLESMC', if_true: files('applesmc.c'))\n",
        "system_ss.add(files('qa-dev.c'))  # QAcademy teaching device.\n",
        "registered qa-dev.c with the build",
        marker="files('qa-dev.c')",
    )

    # 3. The virt machine's allowlist.
    edit(
        tree / "hw" / "arm" / "virt.c",
        "    machine_class_allow_dynamic_sysbus_dev(mc, TYPE_RAMFB_DEVICE);\n",
        "    machine_class_allow_dynamic_sysbus_dev(mc, TYPE_QA_DEV);\n",
        "allowed qa-dev on the virt platform bus",
        marker="machine_class_allow_dynamic_sysbus_dev(mc, TYPE_QA_DEV)",
    )
    edit(
        tree / "hw" / "arm" / "virt.c",
        '#include "hw/display/ramfb.h"\n',
        '#include "hw/misc/qa-dev.h"\n',
        "included the register map in virt.c",
        marker='#include "hw/misc/qa-dev.h"',
    )

    # 4. The device tree node.
    #
    #    The platform bus node declares #address-cells = <1> and #size-cells = <1>, so one cell
    #    each is right here and would not be on a bus with a 64-bit window. The interrupt is a
    #    level-triggered SPI, which matches how the device drives its line: it holds it high
    #    until the guest clears IRQ_STATUS, rather than pulsing it. That is a decision with
    #    consequences the reader meets in L08, and the "level" in this node is where the kernel
    #    learns about it.
    fdt_node = """
/*
 * add_qa_dev_fdt_node: create the device tree node for the QAcademy teaching device.
 *
 * QEMU assigns the address and the interrupt when it places the device on the platform bus, so
 * they are read back here rather than being constants. The node this produces is what the
 * reader's driver matches on in L10.
 */
static int add_qa_dev_fdt_node(SysBusDevice *sbdev, void *opaque)
{
    PlatformBusFDTData *data = opaque;
    PlatformBusDevice *pbus = data->pbus;
    void *fdt = data->fdt;
    const char *parent_node = data->pbus_node_name;
    char *nodename;
    uint32_t reg_attr[2];
    uint32_t irq_attr[3];
    uint64_t mmio_base;
    uint64_t irq_number;

    mmio_base = platform_bus_get_mmio_addr(pbus, sbdev, 0);
    nodename = g_strdup_printf("%s/qa-dev@%" PRIx64, parent_node, mmio_base);
    qemu_fdt_add_subnode(fdt, nodename);

    qemu_fdt_setprop_string(fdt, nodename, "compatible", QA_DEV_DT_COMPATIBLE);

    reg_attr[0] = cpu_to_be32(mmio_base);
    reg_attr[1] = cpu_to_be32(QA_DEV_MMIO_SIZE);
    qemu_fdt_setprop(fdt, nodename, "reg", reg_attr, 2 * sizeof(uint32_t));

    irq_number = platform_bus_get_irqn(pbus, sbdev, 0) + data->irq_start;
    irq_attr[0] = cpu_to_be32(GIC_FDT_IRQ_TYPE_SPI);
    irq_attr[1] = cpu_to_be32(irq_number);
    irq_attr[2] = cpu_to_be32(GIC_FDT_IRQ_FLAGS_LEVEL_HI);
    qemu_fdt_setprop(fdt, nodename, "interrupts", irq_attr, 3 * sizeof(uint32_t));

    g_free(nodename);
    return 0;
}

"""
    sysbus_fdt = tree / "hw" / "core" / "sysbus-fdt.c"
    insert_block(
        sysbus_fdt,
        "static int no_fdt_node(SysBusDevice *sbdev, void *opaque)\n",
        fdt_node.lstrip("\n"),
        "added the device tree node generator",
    )
    edit(
        sysbus_fdt,
        "    TYPE_BINDING(TYPE_RAMFB_DEVICE, no_fdt_node),\n",
        "    TYPE_BINDING(TYPE_QA_DEV, add_qa_dev_fdt_node),\n",
        "bound qa-dev to its node generator",
        marker="TYPE_BINDING(TYPE_QA_DEV,",
    )
    edit(
        sysbus_fdt,
        '#include "hw/arm/fdt.h"\n',
        '#include "hw/misc/qa-dev.h"\n',
        "included the register map in sysbus-fdt.c",
        marker='#include "hw/misc/qa-dev.h"',
    )


if __name__ == "__main__":
    main()
