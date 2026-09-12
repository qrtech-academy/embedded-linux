# Embedded Linux and Kernel Drivers
Repository for the course **Embedded Linux and Kernel Drivers**.

Twelve lectures, one per week, for embedded engineers who write C and have never written it for
a kernel. The course goes from what a Linux system on a board is made of, through the commands
that interrogate a running one, to a device driver you write yourself: memory-mapped registers,
interrupts, locking, a device tree node, a kernel framework, and finally what all of that does to
latency on a real-time kernel.

---

## Everything Here Runs in an Emulator, and That Is the Design
There is no board. Every lecture, every lab and every measurement runs on `qemu-system-aarch64`,
and the device your driver talks to is one this repository ships the source of.

That is a real cost and it is worth naming before you start. You will not learn here what a
floating input feels like, what a badly seated ribbon cable does to an I2C bus, or how long a
board takes to come back after you brick its bootloader. Those are things only hardware teaches.

What it buys is everything else. The device has a register that no real device has: it records
the exact instant it raised its interrupt line, and lets your driver read that instant back. That
one register turns interrupt latency from something you infer into something you subtract, and
L12 is built on it. Beyond that, every reader gets the same machine, a wrong `writel` costs you a
reboot that takes two seconds rather than a trip to a bench, and `git clone` plus three `make`
targets is the whole of the setup.

---

## About the Course
The course covers Linux as embedded engineers meet it: as a kernel you configure and build, a
userland you assemble, and a driver you write for hardware nobody has written one for yet.

Topics include:
* What an embedded Linux system is made of, and the boot chain that assembles it.
* Open source licences, and what shipping a product built on this kernel obliges you to publish.
* The command line, taught as the set of questions you can ask a running kernel.
* Kernel architecture, the source tree, and Kconfig.
* Kernel modules: building them, loading them, and the C environment they run in.
* Character device drivers, and the userspace interface a driver actually presents.
* Kernel memory allocation, memory-mapped I/O, DMA, and managed resources.
* Concurrency, locking, and the contexts in which you are not allowed to sleep.
* Interrupts, deferred work, wait queues, and time.
* The driver model, the device tree, and how a driver finds its hardware.
* Kernel frameworks, and why a driver that is a character device is usually a driver in the
  wrong subsystem.
* Real-time Linux: where latency comes from, what `PREEMPT_RT` changes, and what makes a driver
  hostile to it.

Unlike an introductory Linux course, this one assumes you can already write C and read a
datasheet, and spends its time on the parts that are specific to kernel space.

---

## During the Course

Every lecture has a lab, and from L04 onwards they are one driver, grown. You start with a module
that prints a line, and finish with a driver that probes off a device tree node, services
interrupts, exposes its device through a kernel framework, and has had its latency measured under
two different preemption models.

The code you write is yours. This repository ships the specification in prose, the Kbuild files,
the KUnit suites and the on-target test scripts, and never the driver itself.

---

## Learning Outcomes
After completing the course, participants should be able to:
* Name the four pieces of an embedded Linux system and say what each one does at boot.
* Read an open source licence well enough to say what a product built on it must publish.
* Configure and cross-build a kernel, and say what a given config option costs.
* Write, build and load an out-of-tree kernel module.
* Write a character device driver, and say what its `read()` must do that a userspace `read()`
  need not.
* Choose an allocator and a GFP flag from the context the code runs in.
* Map a device's registers and access them without the compiler or the CPU reordering the
  accesses out from under you.
* Say what address a device doing DMA actually sees, and why a buffer you may dereference is not
  automatically a buffer you may hand to hardware.
* Pick a lock from what it protects and from where the contention comes from, and say why
  sleeping in an interrupt handler is not a style question.
* Write an interrupt handler, defer the work that does not belong in it, and block a reader until
  the data exists.
* Write a device tree node for a device, and a driver that probes from it with no address in it.
* Say which kernel framework a device belongs to, and what registering with it gives you free.
* Explain where latency comes from on a Linux system, what `PREEMPT_RT` changes about it, and
  what a measurement taken under an emulator is not evidence of.

---

## Getting Started
Everything builds inside a container, so the only thing you install is Docker.

```bash
make env       # Build the container image. Once, and slow.
make kernel    # Cross-build the arm64 kernel. Once, and slower.
make qemu      # Build QEMU with the course's device in it. Once.
make rootfs    # Build the BusyBox initramfs.
make boot      # Boot the target and get a shell. Ctrl-A X quits.
```

`make help` lists every target. If you would rather install the toolchain natively, set
`QA_NO_CONTAINER=1` and install the packages listed in [docker/Dockerfile](./docker/Dockerfile);
nothing in the course requires the container except the reproducibility of it.

Once a lab is written, `make build` compiles it and `make test` boots it and runs its tests.
Both narrow to one lecture with `L=`:

```bash
make build L=L06
make test L=L06
```

Every target skips loudly rather than failing when what it needs does not exist yet, which for
most of this repository's life is most of it. A skip names the target that would fix it.

---

## Structure

```text
book/        The course typeset as a book with LuaLaTeX; make -C book builds the PDF
ci/          Scripts behind every make target
diagrams/    The figure pipeline; every PNG is generated from here and committed
docker/      The container image every build runs inside
exam/        Two written papers and their model answers. Optional; nothing depends on them
info/        Course information, prerequisites, and the lecture-by-lecture plan
kernel/      Kconfig fragments. The kernel source is downloaded, not vendored
lectures/    Lecture plans, appendices, exercises and labs
tools/       The qa-dev device model, and the target's init and test runner
```

---

## The Figures Are Drawn From Code
Nineteen figures, at least one per lecture, live under `lectures/*/appendix/images/` and are
generated by [`diagrams/`](./diagrams/README.md). None of them is decoration: half are block
diagrams of something the prose can only describe one step at a time, and the rest are charts of
numbers this course measured on its own target.

**Every number on every chart comes from `diagrams/measured.py`**, which cites the appendix that
publishes it. No figure carries a literal of its own, so a measurement redone is one edit and a
rebuild. `make diagrams` regenerates them byte for byte, and CI fails if a committed figure is out
of date, because a lecture illustrated with a figure whose source has moved on is worse than one
with no figure at all.

---

## Two Written Papers, and What They Are Not
Nothing in this course is marked. Assessment is the lab after every lecture, checked on the target
by `make test`, and eight to ten exercises per lecture ending in a Cross-check that makes you
compute a number by hand and then measure it.

[`exam/`](./exam/README.md) holds two four-hour papers, and they check something else: **what you
can reconstruct on paper, with nothing in front of you.** Ten questions each, mixing prose with
kernel C you either write or repair, and no machine in the room to tell you which it is.

**They exist purely so that participants can test their own knowledge after the course. They gate
nothing, they are not a qualification, and no part of the course requires them.** Nothing in this
repository depends on them, and neither `make build` nor `make test` knows they exist.

**Take one after the course is over.** Both papers draw on all twelve lectures, so sitting one
partway through examines material nobody has taught you yet.

**The papers ship with model answers, and the labs do not.** That is not an inconsistency. A lab,
and every Code exercise, is checkable by running it, so an answer to read would replace the work;
an exam answer is for whoever marks the paper, and a paper nobody can mark tests nothing. The exam
solutions answer the code questions as marking checklists rather than as listings, so they do not
become back-door solutions to the labs. The exercises that are argued or worked on paper, the
Recall, Hand calculation and Design exercises and the by-hand half of each Cross-check, have worked
answers in Appendix A of [the book](#the-book).

---

## Code Formatting
C is formatted with `clang-format` against the [.clang-format](./.clang-format) shared by every
QAcademy course, and Python with `black`. `make format` formats in place; `make format-check`
fails if anything is not formatted.

This means the kernel code in this repository does **not** follow the Linux kernel's own coding
style, and would be rejected upstream on that basis alone. That is a deliberate trade for
consistency with the rest of QAcademy, and
[L04's appendix](./lectures/L04/appendix/a_modules.md) shows the same function in both styles so
that opening a file in `drivers/` is not a surprise.

---

## The Book
The whole course is also a book: [Embedded Linux and Kernel Drivers](./book/embedded-linux.pdf),
the twelve lectures as twelve chapters, then worked solutions to every exercise that is not code,
and the two papers with their model answers. It is built from the sources in
[`book/`](./book/README.md), which also say how to build it yourself (`make -C book`) and how a new
edition is released.

---

## License
The source code is released under the [MIT License](./LICENSE): the lab headers, Kbuild files and
test scripts, the QEMU device model, the kernel configuration fragments, the figure pipeline, the
build and CI scripts, and the book's build files. A file that carries an `SPDX-License-Identifier`
line is licensed as that line says; the KUnit suite and the userspace test programs are
GPL-2.0-only.

The course material is licensed under [CC BY-NC-SA 4.0](./LICENSE-CONTENT): the lectures,
exercises and exam papers, the other Markdown documents, the figures, and the book typeset from
them. You may share and adapt it for any non-commercial purpose, with credit, as long as what you
share carries the same license. The code examples printed in the lectures and in the book may also
be used under the MIT License, except excerpts quoted from the kernel's own source, which remain
under its license, GPL-2.0.

---
