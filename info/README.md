# Course Information

## Instructor
Erik Pihl ([erik.axel.pihl@gmail.com](mailto:erik.axel.pihl@gmail.com))

---

## Prerequisites
Participants are expected to arrive already comfortable with:
* Programming in C at the level of writing and debugging a few hundred lines: pointers, structs,
  arrays, function pointers, and manual memory management.
* Bit manipulation, and reading a register map out of a datasheet.
* Working on a command line: files, paths, redirection, pipes, and running `make`.
* What an interrupt is, at the level of the hardware: a line, a handler, and a return.

None of that is taught from scratch. It is refreshed where a lab needs it, briefly and in the
appendices rather than at length.

What the course does teach from nothing is everything above the C: what a kernel is as a program,
what a module is as a thing you load into a running one, what a driver owes to the userspace on
one side and the hardware on the other, and why almost every rule in kernel programming turns out
to be a rule about which context the code is running in.

**The code is C, and this is not a C course.** Everything you write is ordinary C99 with a kernel
API in front of it. There are no templates, no exceptions and no standard library; that last one
is a bigger change than it sounds and L04 spends a section on it.

**No board, no JTAG, no bricking anything.** There is nothing to install but Docker. Everything
runs under `qemu-system-aarch64`, nothing needs root on your own machine, and a driver that
wedges the target costs you a two-second reboot. See
[Everything Here Runs in an Emulator](../README.md#everything-here-runs-in-an-emulator-and-that-is-the-design)
for what that costs and what it buys.

**Where this course sits.** It is written to be read on its own. It assumes, and does not derive,
the process, scheduler and address-translation theory that L03 and L07 lean on, and the memory
ordering that L06 states without proving; where a lecture needs one of them, it says so.
[Embedded C](https://github.com/qrtech-academy/embedded-c) covers the C itself, which this course
does not teach.

---

# Course Plan - Embedded Linux and Kernel Drivers

Twelve lectures, one per week. **Each lecture is one hour: roughly twenty minutes of material,
thirty minutes of live coding, and ten to close.** The appendices are read before the session, not
during it, and they are where the material lives. The hour produces one piece of the driver;
everything else the lecture asks for is self-study afterwards, judged by the same on-target test
suite.

### Part I - The system
| Week | Lecture | Topic                                                    |
| ---- | ------- | -------------------------------------------------------- |
| 1    | L01     | Embedded Linux, and the licence you ship with it         |
| 2    | L02     | The command line, and the system underneath it           |
| 3    | L03     | The kernel: architecture, source tree, and configuration |

### Part II - Writing a driver
| Week | Lecture | Topic                                 |
| ---- | ------- | ------------------------------------- |
| 4    | L04     | Kernel modules                        |
| 5    | L05     | Character device drivers              |
| 6    | L06     | Memory, MMIO, and resource management |

### Part III - Concurrency, interrupts and time
| Week | Lecture | Topic                        |
| ---- | ------- | ---------------------------- |
| 7    | L07     | Concurrency and locking      |
| 8    | L08     | Interrupts and deferred work |
| 9    | L09     | Sleeping, waiting, and time  |

### Part IV - Fitting into the kernel
| Week | Lecture | Topic                                |
| ---- | ------- | ------------------------------------ |
| 10   | L10     | The device model and the device tree |
| 11   | L11     | Kernel frameworks                    |
| 12   | L12     | Real-time Linux                      |
Twelve rather than ten, and the two extra hours are both in the second half. The first draft of
this course put interrupts, wait queues and timers in one lecture, and kernel frameworks and real
time in another. Both of those hours were overfull in a way that would have shown up as the same
failure: the lab gets cut, and the lab is where the lecture actually happens.

**L08 and L09 were one lecture.** Splitting them is not splitting one topic in half; it is
admitting there were two. L08 is about the half of the mechanism that the hardware drives: a line
goes high, a handler runs, and everything about that handler is constrained by the fact that it
interrupted something. L09 is about the half the software drives: a reader that has asked for data
that does not exist yet, and has to be put to sleep and woken again. They meet in the lab, where
L08's handler wakes L09's sleeper, and that meeting is much better as the payoff of two hours than
as the middle twenty minutes of one.

**L11 and L12 were one lecture.** The frameworks material is a survey and the real-time material
is an argument, and an hour that tries to be both ends up being a list. Separating them also puts
them in the right order for the argument to land: `PREEMPT_RT` turns most spinlocks into sleeping
locks, and that sentence means nothing in the abstract. It means a great deal about the driver the
reader finished in L11, with the lock they added in L07 and the threaded handler they wrote in
L08 still in it.

One pairing is still a pairing, and is worth defending. **L01 puts open source licensing next to
the boot chain** rather than in a lecture of its own, because both answer the same question, which
is what you are actually shipping when you ship a product with Linux in it. A licence lecture that
stands alone gets read as an administrative detail; standing next to the four pieces of the image,
it reads as a property of three of them.

Three topics are not covered here. **Yocto and Buildroot** get a section in L01 and no more, because
teaching either honestly costs two lectures that would come out of the driver material, and this
course's answer to "how do I build a distribution" is that it is a different subject with
different tools. **Networking drivers** are absent for the same reason: the network stack is the
largest subsystem in the kernel and a driver for it is not a first driver. **CPU isolation and IRQ
affinity** are absent from L12 for a different reason: this course's target is a two-CPU QEMU guest,
and isolating one of two CPUs from a scheduler that is itself emulated would produce numbers that
say nothing about a real machine. A claim about pinning that the target cannot demonstrate is worse
than no claim, and L12 is the lecture that argues that.

---

## Lecture Content

### L01 - Embedded Linux, and the Licence You Ship With It
What an embedded Linux system is made of, how it assembles itself at power-on, and what the
licences on the pieces oblige you to hand over.

Topics include:
* The four pieces: bootloader, kernel, root filesystem, toolchain
* The boot chain from ROM through SPL and U-Boot to the kernel, and what `-kernel` skips
* Cross-compilation, the sysroot, and what an ABI is a promise about
* Buildroot and Yocto, what each is for, and why neither is taught here
* Copyleft and permissive licences; GPL-2.0-only, LGPL, MIT, BSD, Apache-2.0
* Derivative works, the kernel's syscall exception, and where the boundary actually falls
* `MODULE_LICENSE`, `EXPORT_SYMBOL_GPL`, and a licence boundary the linker enforces
* SPDX identifiers, and what "complete corresponding source" means in practice

Lab: build a kernel and an initramfs, boot them, get a shell; then audit a source tree for what
you would be obliged to publish.

---

### L02 - The Command Line, and the System Underneath It
The general Linux command line, taught as the set of questions you can ask a running kernel.

Topics include:
* The shell: redirection, pipes, exit status, and what a pipeline actually is
* The filesystem hierarchy, and which directories have to exist before `init` runs
* Processes, signals, and the process tree
* `/proc` and `/sys` as the kernel's own interface, and the difference between them
* `/dev`, device nodes, and what a major and minor number identify
* BusyBox against coreutils, and what a two-megabyte userland gives up
* Init: what PID 1 is for, BusyBox init and systemd
* `dmesg`, `ps`, `top` and `lsof`; and which of `strace`, `ss` and `journalctl` a BusyBox
  target does not have, and why

Lab: a script that reports the target's own configuration entirely out of `/proc` and `/sys`.

---

### L03 - The Kernel: Architecture, Source Tree, and Configuration
What the kernel is as a program, how its source is arranged, and how you choose what goes into
the one you build.

Topics include:
* Monolithic with modules: what that means and what the alternatives cost
* The subsystem map, and the syscall boundary as the kernel's only public interface
* Kernel and user address space, and why a pointer from one is not usable in the other
* The source tree: where a subsystem, a driver, an architecture and a header live
* Mainline, stable, long-term stable, and vendor trees
* Kconfig: symbols, dependencies, `select` against `depends on`, and `=y` against `=m`
* `defconfig`, `menuconfig`, `savedefconfig`, and config fragments
* Kbuild: `ARCH`, `CROSS_COMPILE`, `O=`, `Image`, `vmlinux`, and `modules_install`
* The DTB, the initramfs, and the kernel command line

Lab: configure and build a minimal kernel, then measure what one config option costs.

---

### L04 - Kernel Modules
The smallest useful thing you can write for a kernel, and the environment it runs in.

Topics include:
* `module_init` and `module_exit`, and what "init" means for code with no `main`
* `MODULE_LICENSE`, `MODULE_AUTHOR`, `MODULE_DESCRIPTION`, and kernel tainting
* Out-of-tree Kbuild, and in-tree `Kconfig` plus `Makefile`
* `insmod`, `rmmod`, `modprobe`, `depmod`, and what the difference between the first and third is
* Module parameters, and the sysfs directory a module gets for free
* `EXPORT_SYMBOL` against `EXPORT_SYMBOL_GPL`, and the link error a licence causes
* `printk` levels, `pr_*`, `dev_*`, and dynamic debug
* The kernel C environment: no libc, no floating point, and a stack you can overflow
* The Linux kernel coding style, and why this repository does not use it

Lab: a module that loads; then a second module that links against a symbol the first exports.

---

### L05 - Character Device Drivers
The oldest and simplest interface a driver can present to userspace, and everything it implies.

Topics include:
* Major and minor numbers, `alloc_chrdev_region`, and `cdev`
* `struct file_operations`, and which members a driver has to provide
* `open`, `release`, `read`, `write`, `llseek`, and what each returns
* `copy_to_user` and `copy_from_user`, and why dereferencing a user pointer is a bug
* Error codes: which `-Exxx` a driver returns and what userspace does with it
* The misc device, and when to take the shortcut
* `ioctl`, the `_IO`/`_IOR`/`_IOW` encoding, and why a new one is usually a mistake
* `class_create`, `device_create`, udev, and how a node appears in `/dev`
* sysfs attributes and debugfs, and which of the two is an ABI

Lab: a character device over a ring buffer, with a KUnit suite for the buffer and a userspace
tester for the device.

---

### L06 - Memory, MMIO, and Resource Management
Where a driver gets memory, how it reaches its hardware, and how it gives both back.

Topics include:
* The kernel memory map, and physical against virtual addresses
* The page allocator, the slab, and what `kmalloc` is built on
* `kmalloc`, `kzalloc`, `vmalloc`, `kvmalloc`, `alloc_pages`, and choosing between them
* GFP flags, and `GFP_ATOMIC` against `GFP_KERNEL` as a statement about context
* `request_mem_region`, `/proc/iomem`, and what claiming a region actually prevents
* `ioremap`, `__iomem`, and why the compiler must not treat a register as memory
* `readl` and `writel`, ordering, and the `_relaxed` accessors
* `devm_*` managed resources, and the error-unwind ladder they replace
* The DMA API, for the device that reads memory itself: the bus address, coherent against
  streaming mappings, and what you may not hand a device

Lab: map the device's registers, read its identity, then rewrite the whole thing with `devm_*`
and delete the unwind path.

---

### L07 - Concurrency and Locking
Every way two pieces of kernel code can run at once, and what to do about each.

Topics include:
* Where concurrency comes from: SMP, preemption, interrupts, timers, and workqueues
* Atomic operations, and what "atomic" does and does not promise
* Memory barriers, and why the compiler is as much of a problem as the CPU
* Spinlocks, the `_irq` and `_irqsave` variants, and what each disables
* Mutexes, semaphores, and reader-writer semaphores
* Atomic context: what may not sleep, `might_sleep()`, and why the rule is not a style question
* Deadlock, lock ordering, and lockdep
* RCU and per-CPU data, as the answers when the data is read far more than written

Lab: race the ring buffer on purpose, watch it corrupt, fix it, then make lockdep report an ABBA
deadlock you built deliberately.

---

### L08 - Interrupts and Deferred Work
The half of the mechanism the hardware drives: a line goes high, and whatever was running stops.

Topics include:
* The interrupt path: the line, the GIC, the IRQ domain, the mapping, and the Linux IRQ number
* `/proc/interrupts`, and what each column is actually counting
* `request_irq`, `free_irq`, and the handler's signature
* `IRQ_HANDLED` against `IRQ_NONE`, shared lines, and how a spurious interrupt gets diagnosed
* Level and edge triggering, and the acknowledge that has to happen in the right order
* What a handler may not do, and what happens when it does it anyway
* Why the work has to be deferred, and the four places to defer it to
* Softirqs, tasklets and why they are deprecated, and workqueues
* Threaded interrupt handlers, `IRQF_ONESHOT`, and why this is the default answer now

Lab: take the device's periodic interrupt, acknowledge it correctly, count it, and move the real
work out of the handler; then compare a workqueue against a threaded handler on the same driver.

---

### L09 - Sleeping, Waiting, and Time
The half the software drives: a reader that wants data which does not exist yet.

Topics include:
* What sleeping is: the task state machine, and the difference between blocked and busy
* Wait queues, `wait_event_interruptible`, and the condition that is re-tested after every wake
* The lost wakeup, and why the naive flag-and-sleep is a bug rather than a race you rarely hit
* Completions, and when they are the simpler answer
* Blocking `read()`, `O_NONBLOCK`, and returning `-EAGAIN` at the right moment
* `poll` and `select`, and what a driver has to implement to support them
* Signals, `-ERESTARTSYS`, and the interruptible sleep that is interrupted
* Jiffies, `HZ`, and why a jiffy is not a unit of time you should quote
* `ktime`, monotonic against real time, and which one a driver measures with
* `udelay` and `mdelay` against `msleep` and `usleep_range`, and the context that decides
* Kernel timers and hrtimers, and what each one's resolution actually is

Lab: block a reader in `read()` until L08's handler has data for it, wake it correctly, then
implement `poll` and drive the whole thing from userspace with `select`.

---

### L10 - The Device Model and the Device Tree
How a driver finds its hardware without being told where it is.

Topics include:
* Bus, device and driver, and the match that puts the three together
* kobjects, sysfs, and the reference counting underneath a device's lifetime
* `probe` and `remove`, and what may and may not be done in each
* The platform bus, and what "platform device" actually means
* `of_match_table`, module aliases, and how autoloading happens
* Device tree syntax: nodes, properties, `compatible`, `reg`, `interrupts`, phandles
* `#address-cells`, `#size-cells`, and `ranges`
* Bindings, dt-schema, and where the DTB enters the boot flow
* Overlays, and what they are and are not good for

Lab: turn the driver into a platform driver that probes off the device tree, with every address
and interrupt number deleted from the source.

---

### L11 - Kernel Frameworks
Why your driver probably should not be a character device.

Topics include:
* What registering with a subsystem gives you: a stable ABI, existing tools, power management
* The cost of the shortcut: an `ioctl` of your own invention is an ABI you now maintain forever
* GPIO and pinctrl, and what a `gpiochip` has to provide
* clk and regulator, and why a driver should not be turning power on by writing a register
* I2C and SPI, and regmap as the thing that makes a register map declarative
* IIO for anything that samples, and its buffered and triggered modes
* input, MTD and watchdog, in one sentence each
* How to tell which subsystem a device belongs to, and what to do when the answer is none of them

Lab: register the device with two frameworks so that standard userspace tools drive it, and
delete the character device you have been carrying since L05.

---

### L12 - Real-Time Linux
What all of it costs in latency, and what a real-time kernel changes about the answer.

Topics include:
* What "real time" means, and why it is a statement about the worst case and not the average
* Where latency comes from: interrupt disable, preemption disable, and the long critical section
* Priority inversion, and the classic failure it caused on Mars
* The preemption models: none, voluntary, `PREEMPT`, and `PREEMPT_RT`
* What `PREEMPT_RT` actually changes: sleeping spinlocks, threaded interrupts, priority inheritance
* Which locks do not become sleeping locks, and why `raw_spinlock_t` still exists
* RCU, per-CPU data, and the assumptions that stop holding
* Scheduling policies: `SCHED_FIFO`, `SCHED_RR`, `SCHED_DEADLINE`, and the throttle that saves you
* `cyclictest`: what it measures, and what it structurally cannot see
* The four habits that make a driver hostile to real time, all four of which are in your driver

Lab: measure your driver's latency in two parts, interrupt to handler from the device's own
timestamp register and handler to userspace from the clock both share, under load, on a `PREEMPT`
kernel and then a `PREEMPT_RT` one; plot both histograms and account for the difference between
them.

---

## Course Material

### Literature
* Consists of the appendices attached to each lecture, which are the course material rather than
  a summary of it.
* [Linux Device Drivers, Third Edition](https://lwn.net/Kernel/LDD3/) is the classic reference and
  is free. It is also from 2005, and a good half of its API has been renamed or removed since;
  read it for the model, not for the function names.
* [The kernel's own documentation](https://docs.kernel.org/) is the authority, and the version
  that matters is the one matching the kernel you built.
* [Bootlin's kernel source browser](https://elixir.bootlin.com/linux/latest/source) is how to read
  the tree without cloning it.

### Software
* [Docker](https://docs.docker.com/get-docker/):
    * The only thing you install. Every build in the course runs inside the image built by
      `make env`.
    * On Windows, install it under WSL2 and work from the WSL side of the filesystem.
* [Visual Studio Code](https://code.visualstudio.com/download):
    * Primary editor. The Dev Containers extension will attach to the course image directly.
* Everything else, including the cross toolchain, QEMU and the kernel source, is downloaded and
  built by `make`. Nothing is installed outside `build/`.

---
