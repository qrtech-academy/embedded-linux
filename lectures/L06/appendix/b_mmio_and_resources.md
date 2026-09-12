# Appendix B - MMIO and Resource Management
How a driver reaches its hardware: finding the address, claiming it, mapping it, and reading it
without the compiler or the processor helpfully rearranging what you asked for.

Every listing here was produced on this course's target, against the `qa-dev` device whose register
map is [`tools/qa-dev/qa-dev.h`](../../../tools/qa-dev/qa-dev.h).

---

## B.1 Where the address comes from

On an embedded system, nothing discovers it. Somebody wrote it down, and in a device tree that
somebody is the board's author. `qa-dev`'s node, as QEMU generated it:

```text
platform-bus@c000000 {
        ranges = <0x00 0x00 0xc000000 0x2000000>;
        #address-cells = <0x01>;
        #size-cells = <0x01>;

        qa-dev@0 {
                compatible = "qacademy,qa-dev-1.0";
                reg = <0x00 0x1000>;
                interrupts = <0x00 0x70 0x04>;
        };
};
```

**`reg = <0x00 0x1000>` does not say the device is at address zero.** It says the device begins at
offset 0 *on its parent bus*, and is 0x1000 bytes long. To get a physical address you translate
through the parent's `ranges`, which reads: child 0x0 maps to parent 0xC000000, for 0x2000000
bytes. So:

$$0\text{x}0 + 0\text{x}c000000 = \mathbf{0\text{x}c000000}$$

A reader who takes `reg` at face value maps address 0 and reads nothing useful. That translation is
the Cross-check, and L10 is where `platform_get_resource` does it for you.

**The cells are 32-bit big-endian**, whatever the machine's own endianness. On the target the
properties are raw bytes:

```sh
od -An -tx1 -v /sys/firmware/devicetree/base/platform-bus@c000000/qa-dev@0/reg
```

Reading them with `od -tx4` is the obvious shortcut and is wrong: it decodes four bytes as a
*native-endian* integer, so on this little-endian target every cell comes back byte-swapped and
`0x0C000000` reads as `0x0000000C`. That number is plausible enough to act on, which is what makes
it worth knowing. The lab's `run.sh` reassembles bytes by hand for exactly this reason.

![Four boxes in a row showing one address being translated: reg holding 0x00 and 0x1000, ranges mapping child 0x0 to 0x0C000000, ioremap taking that physical address, and readl returning 0x51414456. Below, a note that a wrong mapping fails two ways and only one of them is loud.](./images/address_translation.png)

---

## B.2 Claiming the region

```c
region = request_mem_region(base, QA_DEV_MMIO_SIZE, "qa_mmio");
if (!region)
        return -EBUSY;
```

**This maps nothing and prevents nothing.** It is an entry in a registry. What it buys you is that
a *second* driver calling it for an overlapping range gets NULL, so two drivers cannot both believe
they own the same device and work intermittently.

It is bookkeeping that the hardware knows nothing about. A driver that skips it and calls `ioremap`
directly works fine, right up until the day a second driver does the same.

The registry is visible, and this is the payoff for
[L01's exercise](../../L01/appendix/c_exercises.md) that looked for `qa-dev` in `/proc/iomem` and
found nothing:

```text
# grep qa_mmio /proc/iomem
0c000000-0c000fff : qa_mmio
```

The name in that listing is the string you passed, so make it the driver's name and not something
generic. Release with `release_mem_region(base, size)`; failing to means the next `insmod` gets
`-EBUSY` from your own previous load, which is a confusing way to discover a leak.

---

## B.3 Mapping it

```c
regs = ioremap(base, QA_DEV_MMIO_SIZE);
if (!regs)
        return -ENOMEM;
```

`ioremap` creates a kernel virtual mapping for a physical range and returns `void __iomem *`.

**It is not memory, and the distinction is not pedantry.** Four things are true of device registers
and false of memory:

* **Reads have side effects.** Reading `QA_DEV_SAMPLE` removes a sample from the FIFO. Reading it
  twice is not the same as reading it once.
* **Writes may not be merged or reordered.** Two writes to the same register are two operations.
* **It must not be cached.** `ioremap` maps it uncached; a cached mapping would let the processor
  satisfy a read from a stale line and postpone a write indefinitely.
* **There is no storage.** Nothing was allocated. `iounmap` returns the mapping, not any memory.

Which is why the compiler must not be trusted with it. Given an ordinary pointer, a compiler may
eliminate a read whose value you ignore, merge two writes, or hoist a read out of a loop. All three
are correct for memory and all three break a driver.

---

## B.4 `readl` and `writel`

```c
u32 id = readl(regs + QA_DEV_ID);
writel(0xdeadbeef, regs + QA_DEV_SCRATCH);
```

These are the only legal way to touch an `__iomem` pointer. They compile to a single load or store
plus the barriers the architecture needs, and they are not optimised away.

| Accessor         | Width   |
| ---------------- | ------- |
| `readb`/`writeb` | 8 bits  |
| `readw`/`writew` | 16 bits |
| `readl`/`writel` | 32 bits |
| `readq`/`writeq` | 64 bits |

**Use the width the device documents.** `qa-dev` accepts 32-bit accesses only and rejects anything
else rather than quietly widening it, which is deliberate: a driver that gets away with a byte
write to a word register here would not get away with it on real hardware.

The address arithmetic is plain byte arithmetic on the returned pointer, so `regs + QA_DEV_ID` with
the offsets from the register map is exactly right, and casting to a struct of `u32` fields is a
common alternative that works until a register map has a gap in it.

---

## B.5 Ordering, and the `_relaxed` variants

`writel` carries a barrier; `writel_relaxed` does not. What the barrier orders is the part worth
getting right.

Accesses from one CPU to one device's registers, through a mapping `ioremap` made, arrive at the
device in program order either way. Write a control register and then read the status register,
relaxed or not, and the device sees the write first. What the barrier orders is a register access
against *ordinary memory*: `writel` waits for every earlier store to RAM before its own store, and
`readl` completes before any later load from RAM begins. That matters the moment the device reads
memory itself. Fill a descriptor in RAM, then write the register that tells the device to fetch it:

```c
desc->len = len;                          /* ordinary memory */
writel(DOORBELL_GO, regs + DOORBELL);     /* ordered after it */
```

Without the barrier the processor may let the register write overtake the store to the descriptor,
and the device fetches a descriptor from before your own update. `qa-dev` reads no memory, so every
access this course's labs make is to one device, and the difference never shows on this target.

The relaxed forms exist because barriers cost time, and a driver writing a burst of registers where
only the last one matters can use `_relaxed` for the burst and an ordered access at the end. **Use
the ordered forms until you have measured a reason not to.** A missing barrier produces a driver
that works on one machine and fails on another, which is the single worst class of bug to debug.

This is the same memory ordering that is a property of the processor on its own; here there is
hardware on the other end that also has an opinion.

---

## B.6 What a wrong address does

Worth knowing before you guess one, and the answer is not "you read a wrong number".

**A wrong-but-mapped address reads plausibly.** Pointing the lab's module at `0xC` rather than
`0xC000000` produces:

```text
qa_mmio: id=0x00000000 version=0x0000
```

No error, no fault, just zeros. A driver that did not check its identity register would carry on
and misbehave later.

**A wrong-and-unmapped address aborts the machine.** Pointing it one page past the device, at
`0xC001000`, produces this:

```text
Internal error: synchronous external abort: 0000000096000010 [#1] PREEMPT SMP
Modules linked in: qa_mmio(O+)
CPU: 0 UID: 0 PID: 67 Comm: insmod Tainted: G           O       6.12.30
pc : qa_mmio_init+0x98/0xff8 [qa_mmio]
Call trace:
 qa_mmio_init+0x98/0xff8 [qa_mmio]
 do_one_initcall+0x84/0x360
```

`insmod` is killed, the module is left half-loaded so it can be neither used nor removed, and the
sensible next step is a reboot. On this target that costs two seconds; on a board on a bench it
costs a walk across the room, and on a product in the field it costs a truck.

Three lessons, and the third is the one worth carrying:

* **Always check an identity register** if the device has one. `qa-dev` has `QA_DEV_ID` for this,
  and reading `0x51414456` is what tells you the mapping landed where you meant.
* **The failure mode depends on the address**, so "it did not crash" is not evidence that a
  mapping is right.
* **This is what the emulator is for.** L01 said the course cannot teach you what a bricked board
  feels like; the other side of that trade is that you can point a driver at a wrong address here
  and find out what happens, which is not an experiment anyone runs twice on real hardware.

---

## B.7 The whole sequence, and its unwind

Acquire in order, release in reverse, and unwind only what you actually got:

```c
region = request_mem_region(base, QA_DEV_MMIO_SIZE, "qa_mmio");
if (!region)
        return -EBUSY;

regs = ioremap(base, QA_DEV_MMIO_SIZE);
if (!regs) {
        ret = -ENOMEM;
        goto err_region;
}

if (readl(regs + QA_DEV_ID) != QA_DEV_ID_MAGIC) {
        ret = -ENODEV;
        goto err_map;
}
return 0;

err_map:
        iounmap(regs);
err_region:
        release_mem_region(base, QA_DEV_MMIO_SIZE);
        return ret;
```

Two acquisitions, two labels, in reverse. Add a third and you add a third label; the pattern does
not get cleverer, it gets longer, and by the time a real driver has a clock, a regulator, a reset
line and three mappings it is twenty lines of unwinding that must stay in step with the acquire
path.

That is the argument for `devm_`, which
[Appendix A.7](./a_kernel_memory.md#a7-devm_-and-what-it-is-attached-to) explains and which this
lecture cannot use, because every `devm_` function needs a `struct device *` and a bare module does
not have one. [L10](../../L10/README.md) is where one appears and this ladder is deleted.

---
