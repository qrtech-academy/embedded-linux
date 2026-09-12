# Appendix B - The Device Tree
Where the description of the hardware comes from, how to read one, and how a driver gets its
addresses out of it without containing any.

[L06](../../L06/appendix/b_mmio_and_resources.md#b1-where-the-address-comes-from) did the
translation by hand once. This is the rest of the format, and the machinery that does it for you.

---

## B.1 Why it exists

An x86 PC can discover itself. PCI is enumerable, ACPI describes the rest, and one kernel image
boots on any machine.

An SoC can do none of that. There is no bus to walk that reveals a UART at `0x09000000` raising
interrupt 33. Somebody has to say so, and before 2011 that somebody was C code in `arch/arm/`, one
file per board, thousands of them, all of which had to be compiled into the kernel and maintained
by the kernel community. The device tree moved that description out of the kernel and into a data
file.

The consequence is the one that matters commercially: **one kernel image, many boards.** The
bootloader passes a different DTB and the same binary boots different hardware.

---

## B.2 The syntax

```text
/ {
        #address-cells = <2>;
        #size-cells = <2>;

        platform-bus@c000000 {
                compatible = "qemu,platform", "simple-bus";
                #address-cells = <1>;
                #size-cells = <1>;
                ranges = <0x00 0x00 0xc000000 0x2000000>;
                interrupt-parent = <0x8003>;

                qa-dev@0 {
                        compatible = "qacademy,qa-dev-1.0";
                        reg = <0x00 0x1000>;
                        interrupts = <0x00 0x70 0x04>;
                };
        };
};
```

| Element            | Is                                                             |
| ------------------ | -------------------------------------------------------------- |
| `name@address`     | A node. The part after `@` matches the first address in `reg`  |
| `property = value` | A property. Values are byte strings, printed as cells or text  |
| `<...>`            | Cells: 32-bit big-endian words                                 |
| `"..."`            | A string, or a list of them separated by nulls                 |
| `<&label>`         | A phandle: a pointer to another node                           |

Node names are conventional and carry no meaning to the kernel; **`compatible` is what matters.**

---

## B.3 `compatible`

The match key, and a list rather than a string:

```text
compatible = "qemu,platform", "simple-bus";
```

**Most specific first.** A driver matches if its `of_match_table` contains any of the strings, and
where its table contains several, the entry for the earliest string wins. So a node can say "I am
exactly this chip, and failing that I behave like this generic thing", and a kernel with only the
generic driver still works. The order does not rank one driver above another: if a driver for each
string is loaded, whichever the bus tries first binds.

The convention is `vendor,model`. The vendor prefix is registered in
`Documentation/devicetree/bindings/vendor-prefixes.yaml`, and making one up is how a binding gets
rejected upstream.

**A driver matches on the string, not on the node name.** Change `qa-dev@0` to `widget@0` and
everything still works; change one character of `qacademy,qa-dev-1.0` and `probe` is never called.
That is the most common reason a driver silently does not load, and the diagnosis is to compare the
two strings by eye:

```text
# tr -d '\0' < /sys/firmware/devicetree/base/platform-bus@c000000/qa-dev@0/compatible
qacademy,qa-dev-1.0
```

---

## B.4 `reg`, cells, and `ranges`

`reg` is a list of address-and-size pairs, but **how many cells each takes is declared by the
parent**, not by the node itself:

```text
parent:  #address-cells = <1>;  #size-cells = <1>;
child:   reg = <0x00 0x1000>;         -> one region: address 0x0, size 0x1000
```

With `#address-cells = <2>` the same property would be one address of two cells and no size, or an
error. **You cannot read a `reg` without looking at its parent**, and that is the single most
common mistake in reading a device tree by hand.

`ranges` translates a child address into the parent's address space, as a list of
`<child-address parent-address size>`:

```text
ranges = <0x00 0x00 0xc000000 0x2000000>;
```

Here the child address takes 1 cell, the parent address 2 (the root declares
`#address-cells = <2>`), and the size 1. So: child `0x0` maps to parent `0x0_0c000000`, for
`0x2000000` bytes. The device at child offset `0x0` is therefore at physical **`0xC000000`**.

An empty `ranges;` means the child addresses *are* the parent's, with no translation. No `ranges`
property at all means the node is not memory-mapped through its parent, and children cannot be
translated.

**The cells are big-endian, always**, regardless of the machine. Reading them with `od -tx4` on a
little-endian host byte-swaps every one, so `0x0C000000` reads as `0x0000000C`, which is plausible
enough to act on. Use `-tx1` and reassemble, or use a tool that knows.

---

## B.5 Interrupts

```text
interrupts = <0x00 0x70 0x04>;
interrupt-parent = <0x8003>;
```

`interrupts` is interpreted **by the interrupt controller**, not by the kernel generally, and how
many cells it takes and what they mean is that controller's business. For a GIC it is three:

| Cell | Meaning                                | Here                  |
| ---- | -------------------------------------- | --------------------- |
| 0    | Type: 0 = SPI, 1 = PPI                 | 0, a shared interrupt |
| 1    | Number within that type                | 0x70 = 112            |
| 2    | Flags: 1 = rising edge, 4 = level high | 4, level triggered    |

The GIC's own numbering adds the 32-entry SPI base, so this is hardware interrupt **144**, and
Linux allocates its own number on top of that. All three appear in one line of
`/proc/interrupts`, which [L08](../../L08/appendix/a_interrupts.md#a1-three-numbers-not-one) takes
apart.

`interrupt-parent` is a phandle naming which controller, inherited by children if not overridden.

---

## B.6 Getting it into your driver

The point of the whole format:

```c
priv->regs = devm_platform_ioremap_resource(pdev, 0);
priv->irq  = platform_get_irq(pdev, 0);
```

`devm_platform_ioremap_resource` does, in one call, what
[L06](../../L06/appendix/b_mmio_and_resources.md#b7-the-whole-sequence-and-its-unwind) spent a
page on: takes `reg` entry 0, which the kernel already translated through every `ranges` between
the node and the root when it created the device, claims the region, maps it, and registers a
destructor for all of it.

`platform_get_irq` parses `interrupts`, finds the controller through `interrupt-parent`, creates
the mapping and returns the Linux number. **It returns a negative error, not zero, on failure**, so
it is checked with `< 0`. Treating 0 as the failure value is a bug that never shows on a board
where the call succeeds, and on the first board where it fails, passes the negative error on to
`devm_request_irq` as if it were a number, deferral included.

Other properties are read with the `of_property_*` family:

```c
u32 depth;
if (of_property_read_u32(pdev->dev.of_node, "fifo-depth", &depth))
        depth = 16;                     /* absent: use the default */
```

Note the idiom: a missing optional property is not an error, it is a default. A missing *required*
property is an error and should say which property, by name, in `dev_err`.

---

## B.7 Bindings

A **binding** is the documentation of what properties a `compatible` string implies. They live in
`Documentation/devicetree/bindings/`, and since about 2018 they are YAML schemas rather than prose,
which means they can be checked mechanically:

```bash
make dt_binding_check          # are the schemas themselves valid
make dtbs_check                # do the shipped device trees match them
```

This matters more than it sounds. **A device tree is an ABI.** A DTB written for one kernel is
expected to work on later ones, because the bootloader that supplies it may not be updated with the
kernel. So a binding, once accepted, is a promise, and getting one reviewed upstream is
deliberately harder than getting a driver reviewed.

Two consequences for a driver author:

* **Do not invent properties for things that are not hardware description.** A debug flag or a
  buffer size that is a policy choice is a module parameter, not a device tree property.
* **Read the binding before the driver.** For an unfamiliar device the binding tells you what the
  hardware is; the driver tells you only what one author did about it.

---

## B.8 Where the DTB comes from, and overlays

At boot, the bootloader loads the DTB into memory and passes its address to the kernel in a
register. [L01](../../L01/appendix/a_the_four_pieces.md#a3-what-the-kernel-is-handed-and-by-whom)
drew that handover; this is the file it was handing over.

On this course's target there is no bootloader: **QEMU generates the DTB itself**, including the
`qa-dev` node, and hands it to the kernel exactly as U-Boot would. The node's address and interrupt
are whatever QEMU assigned when it placed the device, which is why nobody typed them anywhere. You
can dump what it produced:

```bash
qemu-system-aarch64 -machine virt,dumpdtb=virt.dtb ... -device qa-dev
dtc -I dtb -O dts virt.dtb
```

**Overlays** are fragments applied to a base DTB at run time, which is how an expansion board or a
cape describes itself without a new base tree. They are genuinely useful for that and are commonly
reached for as a way to hand-patch a tree during development, which works and is worth knowing is a
development technique rather than a shipping one.

---

## B.9 Reading one on a running system

The whole tree is under `/sys/firmware/devicetree/base`, one directory per node and one file per
property:

```text
/sys/firmware/devicetree/base/platform-bus@c000000/qa-dev@0/
    compatible      "qacademy,qa-dev-1.0"
    reg             00 00 00 00 00 00 10 00
    interrupts      00 00 00 00 00 00 00 70 00 00 00 04
```

Strings come out with trailing nulls, so `tr -d '\0'` is usually wanted. Numeric properties are raw
big-endian bytes and need reassembling by hand, per B.4.

The other view is `/sys/bus/platform/devices/`, where each node with a `compatible` has become a
device named from its translated address. Those two views are the same information from the two
sides of B.1: what the firmware said, and what the kernel made of it.

---
