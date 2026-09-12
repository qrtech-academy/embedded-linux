# Appendix A - The Kernel as a Program, and Its Source Tree
This appendix is the first half of L03: what kind of program the kernel is, what its one public
interface is and what follows from that, and how twenty-four million lines of C are arranged so
that you can find things in them. The configuration half is [Appendix B](./b_kconfig_and_kbuild.md).

---

## A.1 What kind of program the kernel is

You have written programs. The kernel is a program, and almost every assumption you carry from the
first to the second is wrong. Five differences matter.

**It has no `main` and never returns.** It has an entry point that the bootloader jumps to, it
brings itself up, and then it stops being a thing that is "running" at all. After boot the kernel
is a body of code that gets entered: by a system call, by an interrupt, by a fault. Between those
it is not executing. L04's modules are the same shape, which is why `module_init` returning does
not mean the module is finished.

**It is one address space, shared by everything in it.** There is no isolation between subsystems.
A null pointer dereference in a sound driver corrupts the same address space the filesystem code
is using. This is what "monolithic" means, and it is worth being precise: **monolithic is a claim
about the address space, not about modularity.** The kernel is intensely modular in its source
organisation; it just does not enforce any of those boundaries at run time.

**It cannot fault the way a process can.** A userspace segfault kills one process and the system
carries on, because the kernel is there to clean up. When the kernel dereferences a bad pointer
there is nobody above it. What happens instead is an **oops**: the kernel prints a register dump
and a backtrace and tries to kill the offending task. If it cannot, because the fault was in
something no task owns, it panics.

**It has no C library.** Compiled `-nostdinc`, `-ffreestanding`, against its own headers. There is
no `printf`, no `malloc`, and no floating point. L04 covers the consequences; the point here is
that "the toolchain" and "the kernel" are two of L01's four pieces and not one, and this is why.

**Its stack is small and fixed.** 16 KB on arm64, for the entire call chain, and nothing grows it.
Run off the end and the best you can hope for is a guard page and a panic.

---

## A.2 The one public interface, and the one that is not

This is the most consequential fact in the lecture, and it is two facts that people routinely
merge into one wrong one.

**The system call interface is stable forever.** A binary from 1998 still runs.
Linus enforces this with unusual ferocity, and the rule is short: *we do not break userspace.* If
a change makes a working program stop working, the change is reverted, however correct it was.

**The internal API has no stability guarantee whatsoever.** Function signatures change, structures
gain and lose fields, whole subsystems are replaced. Between two point releases, code inside the
kernel may be rearranged freely.

Both are deliberate, and together they explain almost everything about how kernel development
works:

* **An in-tree driver is maintained for you.** When somebody changes an internal API they update
  every caller in the tree, including your driver, because the tree must always build.
* **An out-of-tree driver is maintained by you, forever.** Nobody changing an API knows your
  driver exists. This is the real cost of staying out of tree, and it is a much larger cost than
  the licensing argument in L01. `vermagic` and `CONFIG_MODVERSIONS` in L04 are the mechanisms
  that turn the resulting mismatch into an error message rather than into corruption.
* **"Why is there no stable driver ABI" is a settled question**, and the documented answer is in
  `Documentation/process/stable-api-nonsense.rst`. The short version is that a stable internal ABI
  would freeze design mistakes permanently, and the project has decided it would rather move the
  callers.

---

## A.3 The subsystem map

Roughly, the kernel is:

| Subsystem          | Responsible for                                 | Source     |
| ------------------ | ----------------------------------------------- | ---------- |
| Process management | Creating, scheduling and destroying tasks       | `kernel/`  |
| Memory management  | Address spaces, page tables, allocation         | `mm/`      |
| Virtual filesystem | The common file interface over many filesystems | `fs/`      |
| Networking         | Sockets, protocols, packet handling             | `net/`     |
| Device drivers     | Everything that talks to hardware               | `drivers/` |
| Architecture       | The parts that differ per CPU family            | `arch/`    |

Userspace reaches all of it through system calls. Drivers reach hardware directly. The layer that
matters most to this course is the one that is not in the table: **the driver model**, which is
how a driver is matched to a device, and which lives partly in `drivers/base/` and partly in every
bus. L10 is about it.

---

## A.4 The tree, by the numbers

The pinned source for this course is Linux 6.12.30. Measured:

|                        | Count      |
| ---------------------- | ---------: |
| Files                  | 86,660     |
| C and header files     | 59,998     |
| Lines of C             | 24,631,623 |
| Lines of C and headers | 34,693,754 |

Twenty-four million lines is not a number to be impressed by; it is a number to have a strategy
about. The strategy is that **you never read the kernel, you read one file in it**, and the tree
is arranged so that you can find that file.

Where the bulk actually is:

| Directory        | Files  | Size   | What is in it                                         |
| ---------------- | -----: | -----: | ----------------------------------------------------- |
| `drivers/`       | 34,970 | 1.1 GB | Device drivers. Two thirds of everything              |
| `arch/`          | 17,417 | 153 MB | One subdirectory per CPU architecture                 |
| `Documentation/` | 10,123 | 74 MB  | Genuinely worth reading, and usually current          |
| `tools/`         | 7,700  | 85 MB  | Userspace tools shipped with the kernel               |
| `include/`       | 6,206  | 56 MB  | Headers, including the ones a module compiles against |
| `sound/`         | 2,781  | 52 MB  | ALSA                                                  |
| `fs/`            | 2,480  | 51 MB  | Filesystems, one subdirectory each                    |
| `net/`           | 1,992  | 38 MB  | The network stack                                     |
| `kernel/`        | 592    | 15 MB  | Scheduler, timers, modules, tracing                   |
| `mm/`            | 196    | 5.8 MB | Memory management                                     |

Two observations worth making out loud.

**`drivers/` is two thirds of the kernel**, and within it, `drivers/gpu` alone is 553 MB, half of
`drivers/` and a third of the whole tree. A course about embedded Linux will never open that
directory. This is why arm64 `defconfig` takes an hour to build, and why
[`kernel/trim.config`](../../../kernel/trim.config) exists.

**`arch/` is where portability lives, and where it stops.** `arch/arm64/` holds the entry code,
the page table format, the memory model and the syscall table. Everything above it is written once.
When something behaves differently on your target than on your laptop, `arch/` is usually why.

---

## A.5 Finding things

Four techniques, in the order you should reach for them.

**Know the layout.** A driver for hardware of type X is in `drivers/X/`. A filesystem is in
`fs/<name>/`. An architecture detail is in `arch/<arch>/`. This answers most questions with no
searching at all.

**Search for the string the user sees.** If `dmesg` printed something, that string is in the tree:

```bash
grep -rn "loading out-of-tree module taints kernel" kernel/
```

This is the single most effective kernel debugging technique there is, and it works because the
kernel prints in English and does not localise.

**Search for the interface, not the implementation.** To find who implements something, find who
registers it. `grep -rl "struct platform_driver" drivers/rtc/` finds every RTC platform driver.
Searching for `platform_driver_register` finds three, because the rest register through the
`module_platform_driver()` macro and never spell the function out.

**Read `Documentation/`.** It is unusually good and unusually current, and
`Documentation/driver-api/` in particular is the reference for most of what this course teaches.

For reading rather than searching, [Bootlin's Elixir](https://elixir.bootlin.com/linux/latest/source)
cross-references every identifier in the tree, in a browser, without cloning anything.

---

## A.6 Reading one real driver

The shape of a Linux driver is worth meeting before you write one.
`drivers/rtc/rtc-digicolor.c` is **224 lines**, drives the real-time clock on an SoC none of us
will ever own, and is a good first driver to read for exactly that reason: there is nothing
special about it. It is the ordinary shape.

Its skeleton, with the real line numbers from the pinned tree:

```c
static int __init dc_rtc_probe(struct platform_device *pdev)      /* 176: found my hardware */
{
        rtc->regs = devm_platform_ioremap_resource(pdev, 0);      /* 185: map registers   */
        rtc->rtc_dev = devm_rtc_allocate_device(&pdev->dev);      /* 189: join a framework */
        irq = platform_get_irq(pdev, 0);                          /* 193: which interrupt? */
        ret = devm_request_irq(&pdev->dev, irq, dc_rtc_irq, 0,    /* 196: take it          */
                               pdev->name, rtc);
        return devm_rtc_register_device(rtc->rtc_dev);            /* 205: go live          */
}

static const __maybe_unused struct of_device_id dc_dt_ids[] = {   /* 208: what I handle    */
        { .compatible = "cnxt,cx92755-rtc" },
        { }
};

static struct platform_driver dc_rtc_driver = {
        .driver = {
                .of_match_table = of_match_ptr(dc_dt_ids),        /* 217: how I am matched */
        },
};
module_platform_driver_probe(dc_rtc_driver, dc_rtc_probe);        /* 220                   */
```

**Every line of that maps onto a lecture in this course, in order.** `devm_` and `ioremap` are
L06. `platform_get_irq` and `devm_request_irq` are L08. `of_match_table` and `compatible` are L10.
`devm_rtc_register_device` is L11. There is no `read()` and no `/dev` node written by hand, and
that absence is L11's argument.

Notice what is *not* in it: no addresses, no interrupt numbers, no unwind path. The addresses come
from the device tree, and the `devm_` prefix means the cleanup is registered rather than written.
A driver written the way L05 teaches would be half again as long and would have a ladder of `goto`
labels at the bottom. Both of those disappearances are deliberate and both are lectures.

**The RTC actually on this target is a different one**, `drivers/rtc/rtc-pl031.c`, 470 lines. It is
worth knowing that it is matched by a different mechanism: it is an ARM PrimeCell, so it is
identified by ID registers in the hardware itself rather than by a `compatible` string, and it uses
`amba_driver` rather than `platform_driver`. Bus-specific matching is L10's subject; the reason to
mention it now is that if you go looking at the driver for the clock in your own machine, you will
find it does not look like the skeleton above, and that is not because one of them is wrong.

You can see it running:

```text
# dmesg | grep pl031
rtc-pl031 9010000.pl031: registered as rtc0
# grep pl031 /proc/interrupts
 15:          0          0  GIC-0  34 Level     rtc-pl031
```

Zero interrupts on both CPUs, because nothing has set an alarm. L08 is where that column starts
moving.

---

## A.7 Versions, and which tree you are on

| Tree      | Meaning                                    | Lifetime        |
| --------- | ------------------------------------------ | --------------- |
| Mainline  | Linus's tree. New features land here first | Continuous      |
| `-stable` | Backported fixes for the current release   | ~2 months       |
| **LTS**   | A release designated long-term stable      | 2 to 6 years    |
| Vendor    | An SoC vendor's fork of some older release | Until they stop |

**This course pins 6.12.30**, which is an LTS release. The `.30` is the stable increment: 6.12 was
the feature release, and 6.12.30 is that plus thirty rounds of backported fixes and no new
features. Stable releases take only fixes, judged against documented rules in
`Documentation/process/stable-kernel-rules.rst`, of which the important one is that a fix must
already be in mainline before it can be backported.

**The vendor tree is where embedded work actually happens, and it is the source of most of the
pain.** A typical SoC ships with a vendor kernel that is a fork of a release three or four years
old, with several thousand out-of-tree patches. It boots your board and mainline does not. What
follows from that:

* A fix from mainline may not apply, because the code around it has moved.
* An upgrade is a port, not an update.
* Everything you write against vendor-specific APIs is stranded when you do upgrade.

The engineering response is to push whatever you can upstream and to prefer mainline interfaces
even when the vendor offers a shortcut. This course teaches mainline interfaces throughout, and
that is the reason.

---

## A.8 What "24 MB" is made of

L01 measured the kernel this course builds at **about 24 MB** and left the size unexplained. The
explanation belongs here.

`vmlinux` is the linked kernel as an ELF object: **31,468,440 bytes**. `Image` is that stripped of
ELF structure and laid out for the bootloader to load: **24,943,104 bytes**. The difference is
symbol tables and ELF metadata that the boot process does not need.

Inside it, the largest contributors on this build:

| Section     | Size       | What it is                                       |
| ----------- | ---------: | ------------------------------------------------ |
| `.text`     | 13,021,184 | Executable code                                  |
| `.rodata`   | 4,369,606  | Constants, string literals, tables               |
| `.rela.dyn` | 3,341,232  | Relocations, applied once at boot and then freed |
| `.init.*`   | 1,029,519  | Code and data used once at boot and then freed   |

The last two rows are worth a moment, because you can watch them happen:

```text
[    5.001253] Freeing unused kernel memory: 4672K
```

Every function marked `__init` and every variable marked `__initdata` is placed in a section that
is discarded once boot is over, and on arm64 so is the table of relocations the kernel applies to
itself when it boots at a randomised address. On this build that is **4,672 KB returned to the
system**, the whole stretch from `__init_begin` to `__init_end`, which is more than the entire
BusyBox userland. L04 uses the same annotations.

**And the reason it is 24 MB rather than 3 MB is configuration.** Nothing in the size is
mysterious: it is the sum of what was compiled in, and what was compiled in was chosen by a
`.config` with **5,725 lines** in it. Appendix B is about that file, and the Cross-check is about
learning to predict what one line of it is worth.

---
