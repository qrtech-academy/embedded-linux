# L01 - Embedded Linux, and the Licence You Ship With It

## Agenda
* What is actually on the flash of a product that runs Linux, in four pieces, and what each one
  does at power-on.
* The boot chain from the on-chip ROM to the first userspace process, and the three steps QEMU's
  `-kernel` lets you skip.
* Cross-compilation: why `gcc` on your laptop is the wrong compiler, and what a sysroot is for.
* Buildroot and Yocto in five minutes, which is all they get in this course and why.
* Copyleft against permissive, and the one question a licence actually answers.
* The kernel's syscall exception, `MODULE_LICENSE`, and a licence boundary the linker enforces.
* Live: `make kernel`, `make qemu`, `make rootfs`, `make boot`, and a shell on a machine you just
  built.

---

## Lecture plan
Worked in this order:

1. **What is on the flash.** Four pieces: bootloader, kernel, root filesystem, and the toolchain
   that is not on the flash at all but determines everything that is. Draw it once. Almost every
   question later in the course is a question about which of the four a thing belongs to.
2. **Power-on to prompt.** ROM, SPL, U-Boot, kernel, `init`. Five steps, and the interesting part
   is that each one exists because the previous one did not have enough memory to do the next
   one's job. Then say plainly that `make boot` skips the first three, and what that costs: this
   course never teaches you to recover a bricked bootloader, because it never lets you brick one.
3. **The compiler is not your compiler.** `aarch64-linux-gnu-gcc` against `gcc`, the triplet, and
   the sysroot. The demonstration worth doing live is `file` on a binary from each, because the
   difference is one line of output and it is the whole idea.
4. **Buildroot and Yocto, briefly.** What problem they solve, why they are two answers to it, and
   why this course builds its root filesystem out of one statically linked BusyBox instead. Say
   out loud that this is not what a product does.
5. **The licence question.** One question: *if I give somebody this binary, what am I obliged to
   give them along with it?* Work GPL-2.0-only, LGPL-2.1, MIT and Apache-2.0 through it. Then the
   two boundaries that matter for the rest of the course: the syscall exception, which is why the
   application you ship on top of Linux is yours, and `EXPORT_SYMBOL_GPL`, which is where the
   argument stops being philosophy and becomes a link error.
6. **Build the machine, live.** `make env`, `make kernel`, `make qemu`, `make rootfs`, `make boot`.
   It takes long enough that this is the moment to run it, talk over it, and come back to a prompt.

Two predictions worth making before you reach them. Before step 3, ask the room what `gcc -o hello
hello.c` produces on an x86 laptop and whether the target can run it. Before step 6, ask how big
a kernel image for a machine with one serial port and one timer ought to be; the answer is
**24 MB**, almost everyone guesses low, and the reason it is that large is the subject of L03.

**If the hour runs short, compress step 4**, not step 5. Buildroot and Yocto read perfectly well
on paper. The licensing argument does not, because the part that lands is the argument in the
room about where the boundary falls.

---

## Before the lecture
* Install Docker. Nothing else. On Windows, install it under WSL2 and work from the WSL side of
  the filesystem; a bind mount from `/mnt/c` is slow enough to be worth avoiding.
* Run `make env`. It takes a few minutes and it is the only step that needs the network for
  anything other than a download.
* Read [Appendix A](./appendix/a_the_four_pieces.md), which is the anatomy of an embedded Linux
  system and the boot chain that assembles it.

## After the lecture
* Read [Appendix B](./appendix/b_licences.md). It is the one appendix in this course with no code
  in it, and it is the one most likely to come up in a design review.
* Work through [Appendix C](./appendix/c_exercises.md), ending with the **Cross-check**.
* Finish the lab in [`lab/`](./lab), and make `make test L=L01` report **PASSED**.

---

## What you should be able to do afterwards
* Name the four pieces of an embedded Linux system, and say for any given file which one it
  belongs to.
* Walk the boot chain from power-on to the first userspace process, and say what each step does
  that the one before it could not.
* Say what `-kernel` skips, and therefore what this course does not teach you.
* Explain what a toolchain triplet names, and why a sysroot is not the same thing as the host's
  `/usr/include`.
* Answer the licence question for a given component: what must be published, to whom, and when.
* Say why an application that only makes system calls is not a derivative work of the kernel, and
  why a kernel module usually is.
* Predict whether a module will load, given its `MODULE_LICENSE` and the symbols it uses.

---

## Questions to test yourself
* A colleague says "we ship Linux, so all our code has to be open source". What is wrong with
  that sentence, and what is the part of it that is right?
* Your product has a bootloader, a kernel, a BusyBox root filesystem and one proprietary daemon
  you wrote. A customer asks for the source. What do you have to give them?
* Why does the boot chain have an SPL at all, given that U-Boot could do the same job?
* What does `aarch64-linux-gnu` tell you that `aarch64` alone does not?
* A driver is licensed MIT and calls a function exported with `EXPORT_SYMBOL_GPL`. What happens,
  and at which point: compile, link, load, or run?
* Why is the kernel image 24 MB when the machine it boots has one serial port and one timer?

---

## Reference
* [Appendix A](./appendix/a_the_four_pieces.md) is the anatomy and the boot chain.
* [Appendix B](./appendix/b_licences.md) is the licensing material.
* [Appendix C](./appendix/c_exercises.md) contains the exercises.
* The build targets are documented in the [root README](../../README.md#getting-started), and
  `make help` lists them all.

---

## Next lecture
* The command line, taken as the set of questions you are able to ask a running kernel.
* `/proc` and `/sys`: not directories, and not files either.
* What a two-megabyte userland gives up, measured against the one on your laptop.
* Why PID 1 is different from every other process, and what happens if it exits.

The machine you built today is the machine you spend the next eleven weeks inside. L02 is about
learning to ask it what it is doing.

---
