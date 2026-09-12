# L02 - The Command Line, and the System Underneath It

## Agenda
* The shell as a program: what a pipeline actually is, and what the kernel does to build one.
* The filesystem hierarchy, and why `/usr` looks the way it does for a reason nobody likes.
* Processes, signals, and the tree; what PID 1 is for and what happens if it exits.
* `/proc` and `/sys`: not directories, not files, and not the same thing as each other.
* `/dev`, device nodes, and what a major and minor number identify.
* BusyBox against coreutils, measured rather than asserted.
* `dmesg`, `ps`, `top` and `lsof`: the diagnostics this target actually has, and the ones it does
  not.
* Live: writing a script that reports the target's own configuration, out of `/proc` alone.

---

## Lecture plan
Worked in this order:

1. **A pipeline, taken apart.** `ps | grep sh | wc -l`, and what the kernel was asked to do:
   three `fork`s, two `pipe`s, four `dup2`s, three `exec`s. Draw the file descriptors. The point
   is that the shell is an ordinary program using ordinary system calls, and that "the command
   line" is not a feature of the kernel at all.
2. **Where things live.** The filesystem hierarchy in five minutes, honestly: `/bin` and `/usr/bin`
   are the same thing now and the split was an accident of a full disk in 1971. What matters for
   embedded is which directories must exist before `init` runs, and the answer is fewer than
   people expect.
3. **The process tree.** `ps`, parents and children, orphans and `init` adopting them. Then the
   demonstration worth doing live, which has a surprise in it. Run `kill -9 1` and watch
   **nothing happen**: PID 1 is immune to any signal it has not installed a handler for, and the
   kernel discards it silently. Then make PID 1 *exit* instead, and the machine dies immediately
   with `Attempted to kill init!`. The pair is the clearest statement there is of what PID 1 is
   for, and the first half is what stops people believing it is an ordinary process.
4. **`/proc` is a lie, and a useful one.** `cat /proc/uptime`, then `strace cat /proc/uptime`,
   and count the reads: there is no file, no disk, and no bytes anywhere until you read. Run this
   on the host, inside the container, because **the target has no `strace`**; BusyBox has no such
   applet, and noticing that is step 6 arriving early. Then `/sys`, and the distinction: `/proc`
   grew organically and holds whatever anyone put there, `/sys` is generated from the driver
   model and has one value per file. L10 is where `/sys` stops being trivia.
5. **`/dev`, and the numbers.** `ls -l /dev` and the two numbers where a size would be. Say now
   that these are what a character device driver registers, because L05 opens with them.
6. **Measure BusyBox.** `ls -l /bin/busybox` on the target against `du -sh /usr/bin` on the host.
   Two megabytes against several hundred. Then `busybox --list | wc -l`, which is **402**. Then
   find what it cannot do, and there is a list: no `strace`, no `ss`, no `vmstat`, no
   `journalctl`. Three of those are absent because BusyBox has no such applet and one because
   this system has no systemd at all. That is the trade rather than a defect.
7. **Live coding.** A script that answers "what is this machine" from `/proc` alone: CPU count,
   memory, uptime, kernel, command line, and how many context switches it has done since boot.

Two predictions worth making. Before step 3, ask what happens when PID 1 exits. Before step 6, ask
how many applets BusyBox has; the answer is in the hundreds and almost everyone guesses in the
tens.

**If the hour runs short, compress step 2**, not step 4. The hierarchy is a lookup table and reads
fine on paper. The `/proc` demonstration does not survive being read, because the whole point is
watching `strace` show that no file was opened.

---

## Before the lecture
* Have `make boot` working and a shell on the target. If it does not, that is an L01 problem and
  worth fixing first.
* Read [Appendix A](./appendix/a_shell_and_processes.md), which is the shell, the process tree
  and the hierarchy.

## After the lecture
* Read [Appendix B](./appendix/b_proc_sys_dev.md), which is `/proc`, `/sys` and `/dev` in detail.
* Work through [Appendix C](./appendix/c_exercises.md), ending with the **Cross-check**, which
  asks you to derive a context-switch rate by hand and then have your script compute it.
* Finish the lab in [`lab/`](./lab), and make `make test L=L02` report **PASSED**.

---

## What you should be able to do afterwards
* Describe what the kernel is asked to do when a shell builds a two-stage pipeline.
* Say what `/proc/uptime` is, and demonstrate that reading it opens no file on any disk.
* State the difference between `/proc` and `/sys` in terms of where their contents come from.
* Read `ls -l /dev/null` and say what each field means, including the two that are not a size.
* Find, on a running system, the kernel version, the boot command line, the CPU count, the memory
  size, and the number of context switches since boot.
* Say what BusyBox trades away, with a number rather than an adjective.
* Say what `kill -9 1` does, and what does end a Linux system.

---

## Questions to test yourself
* `cat /proc/uptime` prints two numbers. Where were those numbers a microsecond before you ran it?
* Why can `cd` not be an ordinary program in `/bin`?
* A file in `/sys` contains `1`. What are you allowed to assume about what writing `0` to it does?
* What is the difference between a process that is stopped, a process that is sleeping, and a
  process that is a zombie? Which of the three can you kill?
* You run `kill -9 1` as root and the system carries on. Why, and what would have ended it?
* Your target has `/dev/ttyAMA0` with major 204 and minor 64. What do those two numbers select?
* Why does an initramfs need `/proc` to exist as an empty directory before anything mounts it?

---

## Reference
* [Appendix A](./appendix/a_shell_and_processes.md) is the shell and the process tree;
  [Appendix B](./appendix/b_proc_sys_dev.md) is `/proc`, `/sys` and `/dev`.
* [Appendix C](./appendix/c_exercises.md) contains the exercises.
* [L01 Appendix A.8](../L01/appendix/a_the_four_pieces.md#a8-where-to-look-on-a-running-system)
  introduced four of these files; this lecture is the rest of them.
* `busybox --help` on the target lists what this particular userland can do.

---

## Next lecture
* The kernel as a program: what it is made of and how its source is arranged.
* Kconfig, and what "configuring a kernel" actually chooses between.
* Why the kernel you built is 24 MB, and what that buys.
* Measuring what a single config option costs, in bytes and in modules.

L02 was about interrogating a system somebody else configured. L03 is about becoming the person
who configured it.

---
