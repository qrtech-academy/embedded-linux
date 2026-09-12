# Appendix A - Kernel Memory
Where a driver gets memory, which allocator to ask, and what each of them fails like.
[Appendix B](./b_mmio_and_resources.md) is how a driver reaches its hardware.

The one idea to carry through: **in the kernel, choosing an allocator is choosing a failure mode.**
Userspace has `malloc`, which either works or the process dies. Up here you pick between allocators
that fail in different ways at different sizes under different conditions, and the flag you pass is
a statement about where your code is running.

---

## A.1 Two things called an address

A **physical address** is where something is on the bus. A **virtual address** is what your code
may dereference. The MMU maps the second to the first.

In userspace you never see a physical address and rarely think about the distinction. In the kernel
you see both, and confusing them is the most common cause of a crash in a first driver. The types
help a little:

| Type              | Holds                           | Dereference it?            |
| ----------------- | ------------------------------- | -------------------------- |
| `void *`          | A kernel virtual address        | Yes                        |
| `phys_addr_t`     | A physical address              | **No.** It is a number     |
| `resource_size_t` | A physical address or a size    | **No**                     |
| `void __iomem *`  | A mapped device register window | Only with `readl`/`writel` |
| `char __user *`   | A userspace virtual address     | **No.** `copy_*_user` only |

Four of the five are not pointers you may follow, and two of them are spelled like pointers.
`__iomem` and `__user` are annotations that compile to nothing; what makes them useful is `sparse`,
a static checker that does understand them:

```bash
make C=1 M=$PWD modules      # run sparse over your module
```

**`/proc/iomem` is a map of the first kind.** It lists physical ranges that a driver has claimed.
[L01's exercise](../../L01/appendix/c_exercises.md) looked there for `qa-dev` and found nothing,
because nothing had claimed it. B.2 is where that changes.

Two is the whole story while the CPU moves every byte, which is true of everything this course
builds. A device that reads memory by itself introduces a third, and A.6 is that one.

---

## A.2 The allocators

Four, and the differences that matter are contiguity, size limit and failure mode.

| Function      | Gives you                   | Physically contiguous | Practical limit                     | Can sleep       |
| ------------- | --------------------------- | --------------------- | ----------------------------------- | --------------- |
| `kmalloc`     | A small object              | **Yes**               | ~4 MB, fragmenting well before that | Depends on flag |
| `kzalloc`     | The same, zeroed            | Yes                   | Same                                | Depends on flag |
| `vmalloc`     | A large buffer              | **No**                | Large                               | **Always**      |
| `kvmalloc`    | Tries `kmalloc`, falls back | Only if it got lucky  | Large                               | Yes             |
| `alloc_pages` | Whole pages                 | Yes                   | Order-limited                       | Depends on flag |

**`kmalloc` is what you want**, almost always. It comes from the slab allocator, it is fast, and it
returns physically contiguous memory, which is what hardware doing DMA needs.

**Its size limit is not the one documented.** The hard cap is a few megabytes, but the practical
limit is much lower and it is not a constant: `kmalloc` must find *physically contiguous* pages,
and after a system has been up for a while, physical memory is fragmented. An allocation of 128 KB
that succeeds every time on your desk can fail on a machine that has been running for a month.
**This is the failure that does not appear in testing**, and it is why anything large should be
`vmalloc` or `kvmalloc`.

**`vmalloc` gives virtually contiguous memory built from pages that are not physically adjacent.**
That is fine for a big software buffer and useless for DMA, which sees physical addresses. It is
also slower to allocate and costs page table entries.

**`kvmalloc` is the sensible default for "large, and I do not need contiguity"**: it tries
`kmalloc` and falls back to `vmalloc`. Note that you therefore do not know which you got, so it
must not be used for anything that needs physical contiguity.

Free with the matching call: `kfree`, `vfree`, `kvfree`, `__free_pages`. Mismatching them is a bug
that usually survives testing.

---

## A.3 GFP flags say where you are, not how much you want

The flag is the second argument to `kmalloc` and it is the part people treat as decoration. It is
not a priority. **It tells the allocator what it is allowed to do to satisfy you**, and the thing
that matters most is whether it may put you to sleep.

| Flag         | Means                                              | Use in                                      |
| ------------ | -------------------------------------------------- | ------------------------------------------- |
| `GFP_KERNEL` | May sleep: may reclaim, may swap, may wait for I/O | Process context only                        |
| `GFP_ATOMIC` | **May not sleep.** Takes from an emergency pool    | Interrupt handlers, code holding a spinlock |
| `GFP_NOWAIT` | May not sleep and may not use the emergency pool   | Where failure is fine                       |
| `GFP_DMA32`  | Restrict to memory a 32-bit device can reach       | DMA with an addressing limit                |

Two consequences follow, and they are the whole of why this matters:

**`GFP_KERNEL` in the wrong place is a bug even when it works.** Calling it while holding a
spinlock, or from an interrupt handler, means the kernel may try to sleep in a context where
sleeping deadlocks the machine. It will often get away with it, because memory was available and it
never needed to sleep. It will fail on the day the system is under pressure.
`CONFIG_DEBUG_ATOMIC_SLEEP`, which this course enables, turns that into a loud complaint instead;
[L07](../../L07/README.md) is where you make it complain on purpose.

**`GFP_ATOMIC` is more likely to fail, not less.** It cannot reclaim, so it takes from a small
reserve. Code using it must handle failure, and must not use it merely because it seemed safer.

The rule that follows is short: **choose the flag from the context you are in, not from how badly
you want the memory.** If you cannot say whether your code can sleep, that is the question to
answer first, and L07 is about answering it.

---

## A.4 What a driver actually allocates

For the driver this course builds, in order of appearance:

* **A small state structure**, one per device. `kzalloc(sizeof(*priv), GFP_KERNEL)` in probe.
* **A bounce buffer** for `copy_to_user`, as in [L05](../../L05/appendix/b_the_driver.md). Small,
  short-lived, `GFP_KERNEL`, because `read` runs in process context.
* **Nothing at all for the registers.** Device registers are not memory and are not allocated. B.3
  is what happens instead, and it is the distinction this lecture turns on.

That last point is worth being explicit about, because the syntax hides it. After `ioremap` you
hold something spelled like a pointer to memory, and it is not memory: there is no storage behind
it, reads have side effects, and the number of bytes you "allocated" is zero.

---

## A.5 The page allocator underneath

`kmalloc` is built on the **slab allocator**, which is built on the **page allocator**. You can see
all three:

```text
# head -5 /proc/meminfo
MemTotal:         481248 kB
MemFree:          448524 kB

# head -3 /proc/slabinfo        # what the slab is caching, and how much
# cat /proc/buddyinfo           # free pages, by order
```

`/proc/buddyinfo` is the one worth knowing, because it is where the fragmentation in A.2 becomes
visible: it lists how many free blocks exist at each order, from single pages up. A machine with
plenty of free memory and nothing above order 4 cannot satisfy a large `kmalloc`, and
`/proc/meminfo` will not tell you that.

`alloc_pages(gfp, order)` asks for $2^{order}$ contiguous pages directly. Drivers rarely need it;
it appears when you want a whole page for DMA or a ring, and it returns a `struct page *` rather
than an address, which is a different currency again.

---

## A.6 A third thing called an address

A.1 said there were two. There are two until a device reads memory by itself, and then there is a
third: the **bus address**, which is the number the device puts on the bus to reach your buffer. It
has its own type, `dma_addr_t`, and the rule about it is the same rule as for `phys_addr_t`. **It is
a number, the CPU may not dereference it, and it is not necessarily the physical address.**

On a simple SoC it usually is the physical address, and that is the trap. An IOMMU between the
device and memory translates it; a bus can apply a fixed offset. So a driver that computes
`virt_to_phys(buf)` and writes the result into a device register works on the board you have and
corrupts memory on the one with an IOMMU, and it corrupts it silently, somewhere else, later.
**Never hand a device an address you calculated. Ask for one.**

Asking is the DMA API, and there are two ways to ask.

### Coherent, for what both sides touch constantly

```c
void *cpu;
dma_addr_t handle;

cpu = dma_alloc_coherent(dev, size, &handle, GFP_KERNEL);
/* cpu is yours to dereference; handle is what you write into the device. */

/* ... the device's lifetime happens here ... */

dma_free_coherent(dev, size, cpu, handle);
```

One call allocates and maps. You get both addresses, and coherency stops being your problem: what
the CPU writes, the device sees. The cost is that the memory is usually mapped uncached or otherwise
made special, so the CPU reads it slowly. Use it for descriptor rings and status words, which both
sides poke at constantly and neither reads in bulk. `dmam_alloc_coherent` is the `devm_` version,
and A.7 is about why that matters.

**Coherent does not mean ordered**, and the two get confused. It means the device will not read a
stale value; it does not mean your writes reach memory in the order you made them. Filling a
descriptor and then writing the register that tells the device to look at it is exactly the pattern
[B.5](./b_mmio_and_resources.md#b5-ordering-and-the-_relaxed-variants) is about, and it needs the
same barrier here as it does there.

### Streaming, for a buffer you already had

```c
dma_addr_t handle = dma_map_single(dev, buf, size, DMA_TO_DEVICE);

if (dma_mapping_error(dev, handle))
        return -ENOMEM;
/* ... the transfer happens ... */
dma_unmap_single(dev, handle, size, DMA_TO_DEVICE);
```

Here the buffer already exists and you are lending it out. The direction is one of `DMA_TO_DEVICE`,
`DMA_FROM_DEVICE` and `DMA_BIDIRECTIONAL`, and it is not documentation: it tells the kernel whether
to flush the CPU's caches, invalidate them, or both. Getting it wrong is a data bug, not an error.

**And mapping can fail**, which is the line first drivers leave out. `dma_map_single` returns
`DMA_MAPPING_ERROR` rather than setting an errno, so the check is `dma_mapping_error` and there is
no other way to spot it.

### The rule the section is for

**Between the map and the unmap, the buffer belongs to the device.** Reading it or writing it from
the CPU in that window is a bug. If you have to look, `dma_sync_single_for_cpu` borrows it back and
`dma_sync_single_for_device` returns it.

This is the same shape of rule as `__iomem` in [B.3](./b_mmio_and_resources.md#b3-mapping-it) and as
atomic context in [L07](../../L07/README.md): a statement about which side owns something, enforced
by nothing at compile time. It is worth taking seriously precisely because breaking it is so quiet.
A machine whose caches happen to be coherent with its devices runs the broken code correctly
forever, which means your desk, your CI and your emulator can all agree it is fine.

### Why any of this exists

The cache. Your store may still be sitting in a dirty line the device cannot see, so the device
reads memory and gets the old value. In the other direction the CPU holds a clean line, the device
overwrites the memory underneath it, and the CPU never notices. Mapping and unmapping are where the
flush and the invalidate happen, and the direction is how the kernel knows which it needs.

Note what this says about Appendix B. MMIO needs none of it, because `ioremap` maps device registers
uncached by construction: there is no cache line to be stale. A DMA buffer is ordinary cached RAM,
and that single difference is the whole of this section.

### What you may not hand a device

* **`vmalloc` or `kvmalloc` memory.** A.2 said it in a line; here is why. The buffer is virtually
  contiguous and physically is not, so a device given the address of the first page walks straight
  off the end of it into whatever page happens to follow. The kernel refuses this one rather than
  letting it through: `dma_map_single_attrs` checks `is_vmalloc_addr` and returns
  `DMA_MAPPING_ERROR` with a warning. Use `kmalloc`, `alloc_pages`, or `dma_alloc_coherent`.
* **Anything on the kernel stack.** Two reasons, and the first is the one above wearing a
  disguise: this course's kernel sets `CONFIG_VMAP_STACK=y`, as arm64 does by default, so the stack
  is itself virtually mapped and `is_vmalloc_addr` catches a stack buffer too. The second reason
  outlives that config. A DMA buffer wants a cache line to itself, and a local variable shares its
  line with whatever the compiler put next to it, so an invalidate that is correct for your buffer
  destroys a neighbour's data. Allocate it; do not declare it.
* **Memory the device cannot reach.** A device with 32 address lines cannot address anything above
  4 GB, whatever the CPU can. `dma_set_mask_and_coherent(dev, DMA_BIT_MASK(32))` in `probe` is how
  you say so, and after it the kernel allocates low or bounces through a temporary buffer for you.
  That is where `GFP_DMA32` in the A.3 table comes from, and why you should not normally be reaching
  for that flag yourself.

### Two more, in a sentence each

**Scatter-gather.** For a buffer that is many pages and need not be one run,
`dma_map_sg`/`dma_unmap_sg` map a whole `struct scatterlist` at once. The count it returns can be
smaller than the count you passed, because the kernel merges entries that turned out to be adjacent,
and iterating over the number you passed instead of the number you got back is the standard bug.

**dmaengine.** On many SoCs your device does not master the bus at all; a separate DMA controller
does, and you request a channel from it with `dma_request_chan()` and describe a transfer. That
controller already has a driver, and the argument for using it instead of poking its registers is
exactly the argument [L11](../../L11/README.md) makes about every framework.

### There is no lab for this, and that is worth saying

`qa-dev` has no DMA engine. It is a sixteen-deep FIFO and an interrupt line, and every sample in
this course arrives through `readl`. So nothing above is measured on the target and nothing above is
in `make test`; this section is reading, held to the same standard
[L12 Appendix B](../../L12/appendix/b_measurement.md) holds its histograms to.

Where you meet it first is the first real device whose FIFO is shallower than the burst it produces.
At that point the interrupt-per-sample loop you build in [L08](../../L08/README.md) stops keeping
up, and the answer is not a faster handler. It is to stop moving the data with the CPU.

---

## A.7 `devm_`, and what it is attached to

The kernel has a managed version of most allocation functions:

```c
priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
```

Nothing frees that explicitly. It is released automatically when **the device it is attached to is
unbound from its driver**, which is the exact event: not when the module unloads, not when the
process exits, but when the driver stops being responsible for that device.

That is what makes it valuable, because it turns the error ladder in
[L05 A.7](../../L05/appendix/a_character_devices.md#a7-unwinding-in-reverse) into nothing: if
`probe` fails halfway through, everything acquired so far is released for you, in reverse order,
without your writing any of it.

**And it is why you cannot use it in this lecture.** Every `devm_` function takes the device it
attaches to, nearly always as a `struct device *` first argument:

```c
void __iomem *devm_ioremap(struct device *dev, resource_size_t offset, resource_size_t size);
```

A bare module is not a device. It has no `struct device`, nothing is bound to it, and there is no
unbind event for a destructor to hang from. So L06's lab writes the unwind path by hand, knowing it
is temporary. [L10](../../L10/README.md) turns the module into a platform driver, which arrives
with a `struct device *` in its `probe`, and the ladder is deleted there.

Writing it once by hand first is deliberate. `devm_` is easy to use and easy to misunderstand as
"the kernel tidies up after you"; it is not, it is a destructor list attached to one specific
object's lifetime, and knowing what that object is matters the first time something is released
earlier or later than you expected.

---
