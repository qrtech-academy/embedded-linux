# L06 - Memory, MMIO, and Resource Management

## Agenda
* The kernel's memory map, and the difference between an address and a mapping.
* `kmalloc`, `vmalloc`, `kvmalloc`, `alloc_pages`: four allocators and how to pick.
* GFP flags as a statement about context, not about urgency.
* `request_mem_region`, `/proc/iomem`, and what claiming a region does and does not prevent.
* `ioremap` and `__iomem`: why a register is not memory and must not be treated as such.
* `readl` and `writel`, ordering, and when `_relaxed` is safe.
* `devm_*`, the error path it deletes, and why you cannot use it yet.
* Live: map `qa-dev`, read its identity, and prove the mapping is right.
* Reading afterwards, not in the hour: the DMA API, for the device that reads memory itself.

---

## Lecture plan
Worked in this order:

1. **Two things called an address.** A physical address is where the hardware is. A virtual
   address is what your code may dereference. In userspace these are far apart and you never see
   the first; in the kernel they are still far apart and you now see both, and confusing them is
   the single most common cause of an early-boot crash. `/proc/iomem` lists the first kind.
2. **Four allocators.** `kmalloc` gives physically contiguous memory and is what you want,
   `vmalloc` gives virtually contiguous memory for large allocations that do not need to be
   physically contiguous, `alloc_pages` gives whole pages, and `kvmalloc` tries the first and
   falls back to the second. Sizes and failure modes for each; the rule of thumb is that
   `kmalloc` above about 128 KB starts to fail under fragmentation and that is not an error you
   will see in testing.
3. **GFP is about context.** `GFP_KERNEL` may sleep while the kernel reclaims memory.
   `GFP_ATOMIC` may not, and therefore may fail when `GFP_KERNEL` would have succeeded. The flag
   is not a priority; it is you telling the allocator whether you are somewhere it is allowed to
   put you to sleep. L07 and L08 are about knowing which of those you are in, and this is the
   first place getting it wrong has a consequence.
4. **Claiming the region.** `request_mem_region` does not map anything and does not stop anyone
   touching the hardware. It is a registry, and what it prevents is a second driver claiming the
   same range and both of them working intermittently. Then it appears in `/proc/iomem`, which is
   the payoff for L01's exercise where that lookup found nothing.
5. **Mapping it.** `ioremap` turns a physical range into a virtual one you may dereference, and
   returns `void __iomem *`. The annotation is not decoration: `sparse` checks it, and the reason
   it exists is that a register is not memory. It has no cache semantics you want, reads have side
   effects, and the compiler is entitled to reorder, merge or eliminate accesses to ordinary
   memory. `readl` and `writel` are what stop it.
6. **Ordering.** `writel` carries a barrier; `writel_relaxed` does not. Say when the difference
   matters, which is whenever a register access must be ordered against ordinary memory, such as a
   descriptor the device is about to fetch; accesses to one device's registers arrive in order
   either way. Note that this is the same memory-ordering problem the processor has on its own,
   now with hardware on the other end.
7. **Live coding.** Compute `qa-dev`'s physical address from its device tree node, by hand. Map
   it. Read `QA_DEV_ID` and check it against `0x51414456`. Then write and read back `SCRATCH`,
   because a mapping that reads a constant correctly may still be wrong.
8. **Then show what you are not allowed to use yet.** `devm_ioremap_resource` would delete the
   whole unwind ladder from step 7. Write its signature on the board and let the room find the
   obstacle: **every `devm_` function takes the device it attaches to, and you do not have one.**
   A bare module is not a device. Say what `devm_` actually does, which is attach a destructor to a
   device's lifetime rather than make the problem go away, and that L10 is where a device appears
   and this ladder gets deleted. Ending the lecture on a ladder you have been told is temporary is
   better than pretending it is the final form.

**If the hour runs short, compress step 6.** Do not compress step 7; the hand calculation is the
Cross-check and the lecture is where it becomes worth doing.

---

## Before the lecture
* Read [Appendix A](./appendix/a_kernel_memory.md), which is kernel memory and the allocators.
  A.6 is the one section that can wait until afterwards; see below for why.
* Read [Appendix B](./appendix/b_mmio_and_resources.md), which is MMIO, `ioremap`, and
  resource management.
* Have `make test L=L05` passing. This lecture's driver grows out of that one.

## After the lecture
* Read [Appendix A.6](./appendix/a_kernel_memory.md#a6-a-third-thing-called-an-address), which is
  the DMA API. It is deliberately not in the hour: `qa-dev` cannot do DMA, so there is nothing to
  demonstrate live and nothing to measure, and the section says what that costs.
* Work through [Appendix C](./appendix/c_exercises.md), ending with the **Cross-check**: compute
  `qa-dev`'s physical address from `reg` and the platform bus `ranges` by hand, predict what
  `QA_DEV_ID` will read, then map it and find out.
* Extend the lab so `make test L=L06` reports **PASSED**.

---

## What you should be able to do afterwards
* Tell a physical address from a virtual one in unfamiliar driver code, from the types alone.
* Choose an allocator from the size and the contiguity requirement, and say what it fails like.
* Choose a GFP flag from the context you are in, and say what `GFP_ATOMIC` costs you.
* Say what `request_mem_region` prevents and what it does not.
* Map a device's registers and read them without the compiler reordering or eliding the access.
* Explain what `__iomem` is for, given that it compiles to nothing.
* Say when `writel_relaxed` is safe and when it is not.
* Say what `devm_*` buys, what it is attached to, and why a bare module cannot use it.
* Say why a `vmalloc` buffer cannot be handed to a device, and which two calls give you
  one that can.

---

## Questions to test yourself
* A device tree node says `reg = <0x0 0x1000>` and its parent's `ranges` is
  `<0x0 0x0 0xC000000 0x2000000>`. What physical address do the registers start at?
* You `ioremap` a region and read the ID register; it returns `0xFFFFFFFF`. Name three different
  causes, and say how you would tell them apart.
* Why can `kmalloc(GFP_KERNEL)` not be called from an interrupt handler?
* What does `__iomem` do at run time?
* Your driver fills a descriptor in memory and then tells the device to fetch it with
  `writel_relaxed`. It works on one machine and not another. What is the likely cause?
* `devm_kzalloc` memory is freed when? Name the exact event, and say what has to exist before you
  can call it at all.
* You map a buffer with `dma_map_single(..., DMA_FROM_DEVICE)` and read it before unmapping. On
  your desk it works every time. What have you actually done, and where does it stop working?

---

## Reference
* [Appendix A](./appendix/a_kernel_memory.md) is memory, ending with
  [A.6](./appendix/a_kernel_memory.md#a6-a-third-thing-called-an-address) on DMA and
  [A.7](./appendix/a_kernel_memory.md#a7-devm_-and-what-it-is-attached-to) on `devm_`;
  [Appendix B](./appendix/b_mmio_and_resources.md) is MMIO and resources;
  [Appendix C](./appendix/c_exercises.md) contains the exercises.
* [`tools/qa-dev/qa-dev.h`](../../tools/qa-dev/qa-dev.h) is the register map, and is the only
  place it exists. Read it as you would a datasheet.
* [L01 Appendix A.8](../L01/appendix/a_the_four_pieces.md#a8-where-to-look-on-a-running-system)
  is where the device tree node was first shown, with the numbers you now have to translate.

---

## Next lecture
* Every way two pieces of kernel code can run at once, which is more ways than you expect.
* Why the ring buffer you wrote in L05 is already broken.
* Spinlocks and mutexes, and the question that chooses between them.
* A deadlock you build on purpose, and the tool that reports it.

---
