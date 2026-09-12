# Paper A - Solutions

Model answers for [`paper_a.md`](./paper_a.md), with marks shown per part.

**Code questions are answered as checklists** of what a correct answer must contain, not as
listings. Two correct answers will not look alike, syntax is not marked, and a worked listing here
would be a solution to the lecture lab that asks for the same thing.

Every measured number quoted here was taken on the course's own target, and each comes from the
lecture that publishes it: the FIFO sequence in Question 5 is L05's Cross-check (Appendix C.9),
the run in Question 7 is one of the ten in L07 Appendix A.2, the interrupt numbers in Question 8
are those of L08 Appendix A.1, and the latencies in Question 10 are those of L12 Appendix A.8.

---

## Question 1 - The image, and the licence on it (12 marks)

**a) (3)** Bootloader, kernel, root filesystem, toolchain.

The **toolchain** is the one that does not ship. What it determines about the other three is the
**ABI**: the C library and its version are baked into every binary built with it, so a glibc binary
cannot run on a musl root filesystem, and a binary built against a newer glibc will not run on an
older one. One mark for the four names, one for identifying the toolchain, one for naming the ABI
consequence rather than saying "it compiles them".

**b) (4)** Two thirds of a mark each, rounded in the candidate's favour:

| Component                 | Must publish                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------------ |
| Bootloader                | Complete corresponding source, including the board port, its config and build instructions |
| Kernel                    | The same, including the in-tree driver, the `.config` and the device tree sources          |
| BusyBox                   | Source at the version shipped                                                              |
| MQTT library (Apache-2.0) | Nothing. Carry the licence text and the NOTICE file                                        |
| Control daemon            | Nothing                                                                                    |
| Out-of-tree driver        | Nothing, if kept proprietary                                                               |

The in-tree driver being *inside* the kernel tree is the point of that row: it is part of the work
whose source must be published, and a candidate who lists it separately as "ours, so nothing" has
missed it.

**c) (2)** No, it changes nothing. **The obligation runs to whoever receives the binary and is not
conditional on modification.** One mark for "no", one for stating the rule. "We did not change it"
is the plausible wrong answer and scores zero; it does make compliance trivial, since the answer is
the upstream tarball at the version shipped, and a candidate who says that earns the second mark.

**d) (3)** The daemon is settled by the **syscall exception**, which the kernel's `COPYING`
declares at its head and `LICENSES/exceptions/Linux-syscall-note` states: user programs using
kernel services by normal system calls are not derived works. That is a clarification granted by
the copyright holder, not something that falls out of the GPL, and a candidate who says so earns
full credit for that half.

The driver is not settled because it is compiled against kernel headers and linked into the
kernel's address space, so the derivative-work argument that the syscall exception excludes for
applications applies to it directly. It is contested rather than decided; the kernel enforces a
version of the argument mechanically through `EXPORT_SYMBOL_GPL` without the question ever being
litigated.

One mark for naming the syscall note, by `COPYING` or by `Linux-syscall-note`, one for the
address-space distinction, one for identifying the second as contested rather than asserting an
answer.

---

## Question 2 - Asking a running kernel a question (8 marks)

**a) (2)** They did not exist. There is no file and no storage: opening the path selects a kernel
function, and reading it runs that function, which formats a string from live kernel variables at
that instant. Closing the file discards it. One mark for "nowhere", one for the mechanism.

**b) (3)** Any two of, one and a half marks each:

* **Every file appears to have size zero**, because the kernel does not know the length until it
  generates the answer. A program that trusts `stat` to size a buffer reads nothing.
* **Two reads give two different answers**, with no consistency guarantee between them. A program
  computing a rate from one read of a counter has computed nothing.
* **Most of it cannot be mapped or sought from the end.** A program that `mmap`s it, or seeks to
  the end to find its length, fails.
* **A read can be expensive**, walking kernel structures under a lock. Polling in a tight loop is
  measurably costly.

**c) (2)** `/proc` grew organically and holds whatever anyone put there, so its files share no
format. `/sys` is generated from the driver model, with the rule of one value per file. **`/sys` is
the documented ABI**, recorded in `Documentation/ABI/`. One mark each.

**d) (1)** Major and minor. Major selects the **driver**; minor selects **which device of that
driver's**. Both halves needed for the mark.

---

## Question 3 - Configuring a kernel, and what it costs (10 marks)

**a) (3)** `CONFIG_GPIO_SYSFS` is **absent entirely** from the final `.config`. Not `n`, and not
`# CONFIG_GPIO_SYSFS is not set`: the line the candidate added is discarded.

The prompt is `bool "..." if EXPERT`, so with `EXPERT` off the symbol **has no prompt**, and a
symbol with no prompt cannot be set by a user or by a fragment. `olddefconfig` gives it its default,
which is absent.

One mark for "not there at all", two for the prompt-behind-`EXPERT` reasoning. A candidate who says
"it is set to n" has the common misconception and earns one mark at most.

**b) (3)** `depends on B` means the symbol is not offered unless B is on: a **precondition, which is
checked**. `select B` means turning this symbol on **forces B on: an imperative, which is not
checked**.

**`select` is the one that can produce a violating `.config`**, because it does not evaluate the
selected symbol's own `depends on`. Selecting B when B depends on C and C is off leaves `B=y` with
its own requirements unmet, and the failure surfaces as a compile or link error in unrelated code.
One mark per definition, one for identifying `select` with the mechanism.

**c) (2)** Yes, it is set, provided its `depends on` is met. A hidden prompt means the symbol is
**not asked about**, not that it is off; it then takes its `default`, here `y`. One mark for "yes",
one for the distinction between "nobody was asked" and "the value is n".

**d) (2)** The kernel boots normally, prints its usual messages, and then **panics**, because the
driver it needs to read the root filesystem is stored on the root filesystem:

```text
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
```

One mark for the circularity, one for the shape of the message. Wording need not be exact; "unable
to mount root fs" is enough.

---

## Question 4 - A module, written out (12 marks)

**a) (7)** Marked against this checklist. Order and layout are free.

| Element                                                                         | Marks |
| ------------------------------------------------------------------------------- | ----- |
| An init function returning `int`, and an exit function returning `void`         | 1     |
| Both registered, with `module_init` and `module_exit`                           | 1     |
| A message on load and a message on unload, using a `pr_*` wrapper               | 1     |
| `static char *who = "world";` with `module_param(who, charp, ...)`              | 1     |
| A mode of `0444`, or any read-only mode. `0644` is the trap and costs this mark | 1     |
| `MODULE_LICENSE`, plus author and description                                   | 1     |
| `#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt` **before** the includes           | 1     |

Deduct nothing for a missing header, a missing `__init`/`__exit`, or `MODULE_PARM_DESC`. Deduct the
mode mark for a writable mode, since the question states the requirement explicitly.

**b) (2)** **Nothing of the candidate's is running.** The module is *resident and idle*: code and
data occupying kernel memory, waiting to be called by something else. One mark for "nothing
running", one for "resident". A candidate who says "the module keeps running" has the central
misconception of the lecture and earns zero here.

**c) (1)** It places the function in a section that is **discarded once initialisation is
complete**, returning that memory to the system; the boot message `Freeing unused kernel memory` is
this happening. Naming the section-and-free behaviour earns the mark; "it marks it as init code"
does not.

**d) (2)** Any two of: the kernel version; `SMP`, so a kernel built without SMP has different
locking primitives; the preemption model; `mod_unload`; `modversions`; the architecture. Half a
mark each.

The mismatch is an error rather than a warning because **the kernel has no stable internal ABI**: a
structure that gained a field between two releases would be read at the wrong offsets, and the
result would be silent memory corruption rather than a refusal. One mark for turning corruption
into an error message.

---

## Question 5 - The character device contract (12 marks)

**a) (5)** One mark per line. Capacity 256, starting empty.

| Step      | Returns   | Level after |
| --------- | --------- | ----------- |
| write 200 | 200       | 200         |
| write 100 | **56**    | 256         |
| read 512  | 256       | 0           |
| read 512  | `-EAGAIN` | 0           |
| write 300 | 256       | 256         |

![A grouped bar chart of the five calls, showing what each asked for against what it returned. The second write asks for 100 and returns 56, a short write rather than an error; the second read returns no bar at all and is marked -EAGAIN, because an empty FIFO is not end of file.](./images/fifo_sequence.png)

**b) (2)** It returns **56**, a short write. The FIFO is not full when the call arrives, so
`-ENOSPC` does not apply; the contract is that a short count is normal, not an error, and the caller
is expected to read the return value. One mark for 56, one for naming the contract.

`-ENOSPC` and `100` are the two plausible wrong answers.

**c) (3)** Three quarters of a mark each:

| Situation                           | Return    | Userspace sees                         |
| ----------------------------------- | --------- | -------------------------------------- |
| Non-blocking, nothing buffered      | `-EAGAIN` | `read` returns -1, `errno` is `EAGAIN` |
| Write with the buffer full          | `-ENOSPC` | -1, `errno` is `ENOSPC`                |
| `copy_to_user` fails                | `-EFAULT` | -1, `errno` is `EFAULT`                |
| A read of zero bytes                | 0         | `read` returns 0, `errno` is unchanged |

The last is not an error at all. L05's `read` returns 0 for a `count` of 0 (Appendix B.2): nothing
was asked for, so nothing is wrong. `-EINVAL` is the plausible wrong answer and scores nothing for
that line.

**d) (2)** Any three of these four, two thirds of a mark each, capped at 2:

* The page may not be present; userspace memory is demand-paged, and a direct dereference faults
  where no handler expects it.
* The address may not belong to the caller, and may point into kernel memory, so a driver that
  copies from it hands kernel memory to a program that asked for it.
* The mapping can change under you; another thread can `munmap` it between check and copy.
* Faulting it in may sleep, which is legal here and not in every context the code might be reused
  in.

---

## Question 6 - An address, translated and mapped (12 marks)

**a) (2)** **Two cells**: one address and one size. You know because the **parent** declares
`#address-cells = <1>` and `#size-cells = <1>`; the node itself does not say. One mark for "two",
one for "the parent declares it". The second mark is the examinable half.

**b) (3)** `reg`'s first cell is the child address `0x0`. The parent's
`ranges = <0x00 0x00 0xC000000 0x2000000>` maps child `0x0` to parent `0x0_0c000000`. So:

$$0\text{x}0 + 0\text{x}c000000 = 0\text{x}c000000$$

The window is `0x1000`, 4096 bytes. Two marks for the address with working shown, one for the size.
A candidate who answers `0x0` has taken `reg` at face value and earns zero for this part; follow
that error through into part **c)** rather than penalising it twice.

**c) (3)** Either:

* the address is mapped but is not the device, and the identity register reads **plausible zeros**
  with no error at all; or
* the address is not backed by anything, and the read raises a **synchronous external abort**,
  killing `insmod` and leaving the module half-loaded.

One mark each. The third mark is for saying that **the zeros are worse to debug**: the abort is
immediate, loud and points at the faulting instruction, whereas a driver reading zeros carries on
and misbehaves somewhere else later.

**d) (2)** Type `0` is an **SPI**; number `0x70` is **112**; flag `4` is **level-triggered, active
high**. The GIC number is $112 + 32 = 144$. One mark for the three fields, one for 144.

**e) (2)** `devm_platform_ioremap_resource(pdev, 0)`.

One mark for the call, one for naming what it replaced: the address the driver used to compute by
hand (the OF core translated `reg` through every `ranges` when it created the device, so the
driver now only asks for resource 0), `request_mem_region`, `ioremap`, and the matching releases
in the error path and in `remove`.

---

## Question 7 - A race, traced (10 marks)

**a) (1)** $4 \times 20{,}000 = 80{,}000$.

**b) (2)** $80{,}000 - 63{,}562 = 16{,}438$ lost, which is
$16{,}438 / 80{,}000 = 20.5\%$. One mark each.

**c) (3)** **Three**: a load, an add, and a store.

The interleaving: CPU A loads the counter and gets *n*. CPU B loads the counter, also gets *n*.
Both add one and both store *n+1*. Two increments happened and the counter advanced by one. One
mark for "three", two for an interleaving that actually loses an update; a candidate who says "they
happen at the same time" without the load-load-store-store detail earns one.

**d) (2)** **No, the bug is absent at no size.** What differs is that the threads do not overlap for
long enough to collide: at 200 iterations the work finishes inside the window it takes the other
threads to get going, so the interleaving never occurs.

One mark for "not absent", one for the overlap explanation. This is the question that distinguishes
a candidate who has understood the lecture, and the plausible wrong answer, "the race needs more
iterations to become likely", earns one mark for being nearly right about the mechanism and missing
that it is about *duration of overlap* rather than *number of attempts*.

**e) (2)** For the counter alone, **yes**: `atomic_inc` makes the load-add-store indivisible and
fixes it completely.

With a running maximum alongside, **no**. The invariant now spans two variables and must hold
across a read-compare-write sequence, which per-variable atomicity does not provide.

The rule: **atomics protect one variable; locks protect an invariant.** If the property you need
mentions more than one variable, you need a lock. One mark for the pair of answers, one for the
rule.

---

## Question 8 - An interrupt, acknowledged (10 marks)

**a) (3)** One mark each:

* The **device tree cell**, `112`, written by whoever described the board.
* The **GIC hardware number**, `144`, which is 112 plus the 32-entry SPI base.
* The **Linux IRQ number**, `17`, allocated at run time when the mapping is created and unrelated
  to either. It changes if the machine is booted with a different set of devices.

**b) (4)** Checklist:

| Element                                                                       | Marks |
| ----------------------------------------------------------------------------- | ----- |
| Reads its own status register first                                           | 1     |
| Returns `IRQ_NONE` when nothing of its own is pending                         | 1     |
| Acknowledges by writing **back the value it read**                            | 1     |
| Drains the FIFO until the level reads zero, and returns `IRQ_HANDLED`         | 1     |

Deduct the acknowledgement mark for writing `0xFFFFFFFF` or an invented mask, since that clears
bits set after the read and loses those events. The order of the acknowledgement and the drain is
not marked here; part **c)** is where it is examined.

**c) (2)** An event arriving between the acknowledge and the drain sets the status bit again *and*
adds to the FIFO the handler is about to empty. The handler services it and returns with the status
bit still set, producing **one spurious interrupt with nothing to do**.

**No data is lost.** One mark for the sequence, one for stating that this ordering is the safe one.
A candidate who says data is lost has it backwards; that is the *other* ordering.

**d) (1)** The line stays asserted, so the handler is re-entered immediately and forever. `insmod`
never returns and the machine is unrecoverable. Either "interrupt storm" or "the machine wedges"
earns the mark.

---

## Question 9 - A reader put to sleep (8 marks)

**a) (3)** The reader evaluates `fifo_empty()` and finds it true. **The interrupt fires here**: the
handler adds data and calls `wake_up`, which finds nothing asleep on the queue and does nothing at
all. The reader then sets its state and calls `schedule()`, and sleeps waiting for a wakeup that
has already happened: until the next one, and forever if there is none.

Two marks for the interleaving, one for placing the interrupt precisely between the test and the
state change. A candidate who says "there is a race" without locating it earns one.

**b) (2)** One mark each:

* **Because of the failure in a):** the macro queues the task and sets its state *before* testing
  the condition, so a wake arriving during that window finds the task on the queue. Testing a
  condition rather than a flag is what allows the test to happen after queueing.
* **Because a wake does not mean the condition is true:** several readers may be woken and the
  first to run may take all the data, and spurious wakes happen. The macro loops and re-tests.

**c) (2)** Half a mark each: the bytes and their count; sleep until data arrives; `-EAGAIN`;
`-ERESTARTSYS`.

**Zero is never correct** and a candidate who offers it for the second or third case loses that half
mark and should have it pointed out.

**d) (1)** The **delay** family (`udelay`, `mdelay`), which busy-waits and works in any context; and
the **sleep** family (`msleep`, `usleep_range`), which gives up the CPU and needs process context.

The question: **can this code sleep?** Both halves needed for the mark.

---

## Question 10 - Frameworks, and the trade (6 marks)

**a) (2)** Any three of, two thirds of a mark each: no way for a program that does not know about it
to find it; no documented interface; no existing tools; no power management; no way to express what
the device *is*; an `ioctl` ABI the author now maintains indefinitely, including its 32-on-64
compatibility.

**b) (2)** It had to implement a **channel specification** saying the value is a voltage, indexed,
with `IIO_CHAN_INFO_RAW`, and a **`read_raw` callback** returning the value.

It did **not** have to implement a `/dev` node, a `read()`, an `open()`, an `ioctl`, or any sysfs
plumbing. One mark each way round.

**c) (2)** **Neither is better in the abstract, and the question cannot be answered without the
requirement.** A throughput-oriented system should prefer `PREEMPT`, whose mean is 19% lower. A
system with a deadline should prefer `PREEMPT_RT`, whose worst case is 2.3 times lower, because a
deadline is a statement about the maximum and an average is not evidence about it.

Full marks for an answer that names the requirement as the deciding factor and reads both columns.
One mark for an answer that picks `PREEMPT_RT` and defends it only by the maximum without noticing
the mean got worse. **Zero for an answer that compares the means alone**, which is the trap.

A candidate may reasonably argue that the difference is within run-to-run noise and that neither
conclusion is safe from one measurement; that earns full marks and is the better answer.

---
