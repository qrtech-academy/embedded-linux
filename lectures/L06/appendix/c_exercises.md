# Appendix C - Exercises
Ten, ending with the Cross-check. Do them in order; C.7 onwards need the target running.

Where an exercise can be checked mechanically, a **Check yourself** line says how.

**One warning before you start.** C.9 asks you to point a driver at addresses that are not the
device. One of them will oops the machine. That is intended, it is survivable here, and
[Appendix B.6](./b_mmio_and_resources.md#b6-what-a-wrong-address-does) says what to expect. Do not
run that exercise against anything you cannot reboot in two seconds.

---

## C.1 Recall: two kinds of address

**a)** For each of `void *`, `phys_addr_t`, `void __iomem *` and `char __user *`, say whether you
may dereference it, and if not, what you must use instead.

**b)** `__iomem` and `__user` compile to nothing. What are they for, and what tool makes them
useful?

**c)** `/proc/iomem` lists physical ranges. Does an entry there mean the range is mapped? Does its
absence mean the hardware is not present?

**d)** Your driver stores the value returned by `ioremap` in a `void *` rather than a
`void __iomem *`. It compiles and works. Name what you have lost.

---

## C.2 Recall: the allocators

**a)** Choose an allocator for each, and give the reason in one sentence:

* A 48-byte per-device state structure.
* A 2 MB buffer for software processing, no hardware involvement.
* A 16 KB buffer a device will DMA into.
* A 1 MB buffer that hardware never sees.

**b)** `kmalloc(131072, GFP_KERNEL)` succeeds on your desk every time and fails on a customer's
machine after three weeks of uptime. Explain, and name the file that shows you why.

**c)** Why can `kvmalloc` not be used for a DMA buffer, given that it might have returned
`kmalloc` memory?

**d)** Which free function goes with which allocator? What happens if you mismatch them?

---

## C.3 Hand calculation: GFP flags

For each, say which GFP flag is correct and what goes wrong with `GFP_KERNEL`:

**a)** Allocating a bounce buffer inside `read()`.

**b)** Allocating inside an interrupt handler.

**c)** Allocating while holding a spinlock.

**d)** Allocating in a module's init function.

Then:

**e)** `GFP_ATOMIC` is described in some places as "high priority". In what sense is that
backwards? Which of the two is *more* likely to return NULL, and why?

**f)** A driver uses `GFP_KERNEL` inside a spinlock and has run in production for two years. Is it
correct? What would make the problem appear, and which config option this course enables would
have reported it on the first run?

---

## C.4 Hand calculation: translating a device tree address

A device tree contains:

```text
/ {
        #address-cells = <2>;
        #size-cells = <2>;

        bus@40000000 {
                #address-cells = <1>;
                #size-cells = <1>;
                ranges = <0x0 0x0 0x40000000 0x1000000>;

                widget@2000 {
                        reg = <0x2000 0x100>;
                };
        };
};
```

**a)** What physical address do `widget`'s registers start at, and how many bytes long are they?

**b)** How many 32-bit cells does `widget`'s `reg` property occupy, and how do you know?

**c)** How many cells does the `ranges` property occupy? Account for each one.

**d)** A colleague reads `reg = <0x2000 0x100>` and maps `0x2000`. What do they map, and what will
they most likely see when they read it?

**e)** The bus node's `ranges` is `<0x0 0x0 0x40000000 0x1000000>`. Rewrite it as a sentence.

---

## C.5 Design: ordering

**a)** Your driver writes `CTRL` to start a conversion and immediately reads `STATUS` to see
whether it finished. Which accessors do you use, and what happens if you use `_relaxed` for both?

**b)** Your driver writes sixteen configuration registers and then a single `GO` bit. Where does a
barrier actually need to be, and what does that buy over using ordered accessors throughout?

**c)** Why is a missing barrier one of the worst classes of bug to diagnose? Answer in terms of
what you observe rather than what is happening.

**d)** `qa-dev` rejects byte accesses to its 32-bit registers rather than widening them. Argue for
that decision from the point of view of somebody writing a driver for real silicon.

---

## C.6 Design: coherent or streaming

None of this runs on `qa-dev`, which has no DMA engine. Argue it on paper from
[A.6](./a_kernel_memory.md#a6-a-third-thing-called-an-address).

For each buffer, say whether you would reach for `dma_alloc_coherent` or for `dma_map_single`, and
give the reason in terms of how often each side touches it:

**a)** A sixteen-entry descriptor ring. The driver writes an entry, the device reads it, the device
writes a status word back, and this happens thousands of times a second.

**b)** A 64 KB block of samples that the device fills once and the driver then hands to userspace.

**c)** A four-byte doorbell the driver writes and the device polls.

**d)** Your driver maps a buffer `DMA_FROM_DEVICE`, and while the transfer is running it reads the
first word "just to see whether data has started arriving". Nothing ever goes wrong in testing.
What did the code do, why did testing not catch it, and on what kind of machine does it break?

**e)** A colleague proposes `kvmalloc(65536, GFP_KERNEL)` for the buffer in (b), reasoning that
64 KB is large enough to risk `kmalloc` failing on a fragmented system. They are right about the
fragmentation. Why is the suggestion still wrong, and what does the kernel do about it?

---

## C.7 Code: map the device

Write `lectures/L06/lab/qa_mmio.c`. It must:

* Take an unsigned long module parameter `base`, the physical address of the registers, readable
  through sysfs and with no default that works. **Refuse to load if it was not given**, with
  `-EINVAL` and a message saying so, rather than mapping address 0.
* Claim the region with `request_mem_region`, naming it after the module.
* Map it with `ioremap`.
* Read `QA_DEV_ID` and `QA_DEV_VERSION` and print them as
  `id=0x%08x version=0x%04x`.
* **Refuse to continue if the identity register is wrong**, with `-ENODEV`.
* Write `0xDEADBEEF` to `QA_DEV_SCRATCH`, read it back, and print `scratch ok (0x...)` if it
  matches.
* Unwind correctly from every failure point, and release everything on unload.

The register offsets are in [`lab/qa-dev.h`](../lab/qa-dev.h), which is a copy of the device's own
register map; read it as you would a datasheet.

**Check yourself:** `make test L=L06` reports **PASSED**, with nine checks. It works the address out
of the device tree itself and passes it to your module, so if your arithmetic in C.10 disagrees with
the harness, one of you is wrong and it is worth finding out which.

---

## C.8 Code: prove the mapping, three ways

Reading a correct constant is weaker evidence than it looks. With your module loaded:

**a)** Find your region in `/proc/iomem`. What name does it appear under, and where did that name
come from?

**b)** `QA_DEV_ID` reads `0x51414456`. Decode those four bytes as ASCII. Why is an identity
register conventionally something you can recognise by eye?

**c)** Reading a constant correctly does not prove the mapping is writable, or that it is not
aliased onto something else. Which part of your module tests that, and what exactly would fail if
`ioremap` had returned a read-only mapping?

**d)** Unload and reload the module without rebooting. Then comment out `release_mem_region` in
your exit path, rebuild, and try again. What does the second `insmod` say, and why is that error
message a good one?

---

## C.9 Design: what a wrong address does

**Read the warning at the top of this appendix first.**

**a)** Load your module with `base=0xC` instead of the correct address. What does it read, and what
does your identity check do about it? What would a driver *without* that check have done next?

**b)** Now load it with `base=0xC001000`, one page past the device. Record what happens: the
message, what happened to `insmod`, and whether the module can afterwards be used or removed.

**c)** You now have two different failure modes from two wrong addresses. State the general lesson
about using "it did not crash" as evidence that a mapping is correct.

**d)** Both experiments cost you a reboot at most. Write two sentences on what the same two
experiments would cost on a board on your bench and on a product in the field, and relate that to
[L01's](../../L01/README.md) argument about what this course gives up by having no hardware.

---

## C.10 Cross-check: an address worked out by hand

The signature exercise: derive a physical address on paper, predict what is at it, then look.

**a) Read the node.** On the target, find the device tree node and print its `reg`, and its
parent's `ranges`, as raw bytes:

```sh
dt=/sys/firmware/devicetree/base
node=$(find $dt -name 'qa-dev@*' -type d | head -1)
od -An -tx1 -v "$node/reg"
od -An -tx1 -v "$(dirname "$node")/ranges"
```

Write out the cells by hand, four bytes each, most significant byte first.

**b) Translate.** From those cells alone, compute the physical address of the registers and the
size of the window. Show the arithmetic; it is one addition, and the point is knowing which two
numbers to add.

**c) Predict.** From [`lab/qa-dev.h`](../lab/qa-dev.h), say what you expect to read at offset 0 and
at offset 4, as 32-bit values, before you run anything.

**d) Measure.** Load your module with the address you computed and read the two values off
`dmesg`.

**e) Reconcile.** Answer each:

* Did your address match what the harness computed? If not, which of you translated wrongly, and
  what does `run.sh` do that you did not?
* Now do part **a)** again with `od -An -tx4` instead of `-tx1`. You get different numbers. Which
  is right, what is `-tx4` doing, and why is the wrong answer *plausible* rather than obviously
  broken?
* Compare `reg`'s first cell against the address you ended up using. They differ by a large
  constant. Where did that constant come from, and which node declares it?
* You now know the address. Nothing in your driver's source contains it. Where is it, and what has
  to happen for a driver to stop being told and start finding out? Name the lecture.

**f)** Suppose the device tree said `reg = <0x1000 0x1000>` instead. Recompute the address, and say
what you would now expect `QA_DEV_ID` to read and why.

---
