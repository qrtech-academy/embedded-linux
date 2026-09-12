# Appendix A - The Shell, the Process Tree, and Where Things Live
This appendix is the first half of L02's material: what the shell actually is, what it asks the
kernel to do when you type a pipeline, how processes relate to one another, and what the
filesystem hierarchy is for. The second half, the three pseudo-filesystems through which all of
this is visible, is [Appendix B](./b_proc_sys_dev.md).

The framing for the whole lecture is worth stating once. **Every command you type is a question
you are asking the kernel, or an instruction you are giving it.** The shell is not part of the
kernel and has no special powers; it is an ordinary program that makes the same system calls your
own programs make. Once that is genuinely believed rather than merely accepted, most of the
command line stops needing to be memorised.

---

## A.1 The shell is an ordinary program

`/bin/sh` on the target is a symlink to BusyBox, which is a normal ELF binary with no privileges
of any kind. It reads a line, works out what you meant, and makes system calls. That is all.

The consequence people find surprising is that **most of what a shell appears to do is not done
by the shell at all**. Wildcards are expanded by the shell before the program ever runs, so `rm *`
hands `rm` a list of filenames and `rm` never sees a `*`. Redirection is done by the shell before
`exec`, so a program has no idea its output is going to a file. And the program you ran received
none of the syntax: by the time `main` starts, `argv` holds the expanded, redirection-free result.

There is a short list of things the shell *must* do itself, and the list is short for one reason:
they change the shell's own state, and a child process cannot change its parent. `cd` is the
canonical example. If `cd` were a program in `/bin`, the shell would fork, the child would change
*its* directory, and the child would exit. Nothing would have happened. So `cd` is built in, and
so are `export`, `exit`, `umask` and a handful of others.

```text
$ type cd
cd is a shell builtin
```

---

## A.2 What a pipeline actually is

`ps | grep sh | wc -l` looks like one thing. It is three processes, two pipes, and a specific
sequence of system calls. This is the single most useful thing in the lecture to have drawn.

A **pipe** is a kernel object with two file descriptors: one you write to, one you read from.
`pipe()` creates it. It has no name and no presence in the filesystem.

A process gets a new program by **forking** and then **exec'ing**: `fork()` produces a copy of the
current process, and `exec()` replaces that copy's program while keeping its file descriptors.
That last clause is what makes everything work. File descriptors survive `exec`, so the shell can
arrange a child's descriptors *before* the child becomes the program it will run, and the program
starts life already plumbed.

For the two-stage pipeline `A | B`:

```text
  shell
    |
    +-- pipe()             creates fds [r, w]
    |
    +-- fork() ------------> child A
    |                          dup2(w, 1)      stdout now writes into the pipe
    |                          close(r); close(w)
    |                          exec("A")       A starts, unaware of any of this
    |
    +-- fork() ------------> child B
    |                          dup2(r, 0)      stdin now reads from the pipe
    |                          close(r); close(w)
    |                          exec("B")
    |
    +-- close(r); close(w)   the shell must close its own copies
    +-- wait() for both
```

**The closes are not tidiness.** A pipe's read end returns end-of-file only when *every* copy of
the write end is closed. If the shell keeps its copy open, `B` waits forever for an EOF that never
comes, and the pipeline hangs. This is the most common bug in hand-written pipeline code and it is
worth knowing before you write any.

Two consequences follow that explain things people find odd:

* **The stages run concurrently, not in sequence.** `A` is not finished when `B` starts. A pipeline
  reading a huge file starts producing output immediately.
* **The pipe has a fixed-size buffer**, 64 KB by default. When it fills, the writer blocks. That is
  the entire flow-control mechanism, and it is why `yes | head -1` never fills memory. What ends it
  is the reader leaving: once `head` exits, nothing holds the read end open, and `yes`'s next write
  kills it with `SIGPIPE`.

---

## A.3 Exit status, and how the shell knows what happened

Every process returns one byte to its parent. Zero means success and anything else does not; `$?`
holds the last one.

```text
$ true; echo $?
0
$ false; echo $?
1
```

That single byte is the entire contract between a program and a script, and it is why
`command && next` and `command || fallback` work. In a pipeline, `$?` is the status of the *last*
stage only, which means `grep foo file | wc -l` reports success even when `grep` found nothing.
This bites people writing CI scripts, and the fix is `set -o pipefail`, which this repository's own
scripts use for exactly that reason.

**A signal is reported differently.** A process killed by signal N reports as `128 + N`, so a
program killed by `SIGKILL` (9) gives 137. That number appears in
[`ci/test.sh`](../../../ci/test.sh), which uses it to tell a target that hung from a target whose
tests failed.

---

## A.4 The filesystem hierarchy, honestly

The layout is conventional rather than enforced; the kernel cares about almost none of it.

| Path    | Holds                               | Notes                                           |
| ------- | ----------------------------------- | ----------------------------------------------- |
| `/bin`  | Essential user commands             | On most systems now a symlink to `/usr/bin`     |
| `/sbin` | Essential system commands           | Same                                            |
| `/lib`  | Shared libraries and kernel modules | `/lib/modules/$(uname -r)/`                     |
| `/etc`  | Configuration, text, machine-local  | Never binaries                                  |
| `/dev`  | Device nodes                        | Populated by devtmpfs, see B.5                  |
| `/proc` | Process and kernel information      | Not files, see B.1                              |
| `/sys`  | The driver model                    | Not files either, see B.4                       |
| `/tmp`  | Scratch, usually cleared at boot    |                                                 |
| `/var`  | State that changes: logs, spools    | The part of the tree you cannot mount read-only |
| `/usr`  | Everything not needed to boot       | Historically a separate partition               |
| `/root` | Root's home directory               | Not `/`                                         |

The `/bin` against `/usr/bin` split is worth ninety seconds because people assume it encodes a
principle. It does not. In 1971 the Unix authors filled a disk, mounted a second one at `/usr`,
and moved the overflow there; the split has been rationalised ever since. Modern distributions
have merged them back, and `/bin` is a symlink.

**What matters for embedded** is which directories must exist before `init` runs, and the answer
is short: mount points for whatever you intend to mount, and the path named by `rdinit=`. Our own
root filesystem creates `/proc`, `/sys`, `/dev`, `/tmp`, `/lab` and `/root` as empty directories in
[`ci/rootfs.sh`](../../../ci/rootfs.sh), and that is genuinely all that is needed. An empty
directory is required because **mounting onto a path that does not exist fails**, and `/init`
mounting `/proc` is one of the first things that happens.

---

## A.5 Processes: the tree, and the states

Every process except PID 1 has a parent, so processes form a tree.

```text
$ ps -o pid,ppid,stat,comm
  PID  PPID STAT COMMAND
    1     0 S    init
   56     1 S    run.sh
   70    56 R    ps
```

`STAT` is the state, and four of them matter:

| State | Means                                                | Consumes CPU |
| ----- | ---------------------------------------------------- | ------------ |
| `R`   | Running, or ready to run and waiting for a CPU       | Yes          |
| `S`   | Interruptible sleep: waiting for something, killable | No           |
| `D`   | Uninterruptible sleep: usually waiting on I/O        | No           |
| `Z`   | Zombie: exited, but its parent has not collected it  | No           |

**`D` is the one that alarms people.** A process in `D` cannot be killed, not even with signal 9,
because it is inside a system call that is not at a point where a signal can be delivered. It is
almost always waiting for hardware. If it is stuck there permanently, something below it is
broken, and the process is a symptom rather than the problem.

**A zombie is not a leak of anything except a process ID.** When a process exits, its memory is
freed immediately, but its exit status has to be kept until its parent asks for it with `wait()`.
That retained status is the zombie. A parent that never calls `wait()` accumulates them, and the
fix is always in the parent.

**An orphan is different and is not a problem.** If a parent exits first, its children are
re-parented to PID 1, which is expected to `wait()` for them. That is the mechanism by which
daemons end up owned by init, and it is why `PPID` of `1` is normal rather than suspicious.

---

## A.6 Signals

A signal is a number delivered to a process, which either has a handler for it, or gets the
default behaviour.

| Signal    | Number | Default            | Catchable                                             |
| --------- | ------ | ------------------ | ----------------------------------------------------- |
| `SIGINT`  | 2      | Terminate          | Yes. This is Ctrl-C                                   |
| `SIGKILL` | 9      | Terminate          | **No**                                                |
| `SIGSEGV` | 11     | Terminate and dump | Yes                                                   |
| `SIGTERM` | 15     | Terminate          | Yes. The polite one, and what `kill` sends by default |
| `SIGSTOP` | 19     | Stop               | **No**                                                |
| `SIGCHLD` | 17     | Ignore             | Yes. Sent to a parent when a child exits              |

`SIGKILL` and `SIGSTOP` cannot be caught, blocked or ignored, which is what makes them the last
resort. Everything else can be handled, and a program that handles `SIGTERM` to flush its state
before exiting is a program that behaves correctly when the system shuts down.

The relevance to the rest of this course is that **a driver's blocking `read()` has to cope with a
signal arriving while it waits.** That is L09's subject, and the reason a user pressing Ctrl-C
expects something to happen is this table.

---

## A.7 PID 1, and two ways it is not an ordinary process

PID 1 is the first userspace program the kernel starts, named by `rdinit=` or `init=` on the
kernel command line, or found at one of a few default paths. On our target it is
[`tools/target/init`](../../../tools/target/init), which is a shell script.

It is special in exactly two ways, and both are worth demonstrating.

**It is immune to signals it has not handled.** The kernel discards any signal sent to PID 1 for
which PID 1 has installed no handler, including `SIGKILL`. So:

```text
# kill -9 1
# echo "still here"
still here
```

Nothing happens. No error, no message, no dead system. This surprises nearly everyone, and it is
the reason "just kill init" is not how you shut a machine down. The rule exists because the kernel
cannot function without PID 1, so it refuses to let anything remove it by accident.

**It may not exit.** The one thing PID 1 must never do is return. If it does, the kernel stops
immediately:

```text
init: I am PID 1, and I am about to exit
[    3.183995] Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000000
```

That is what a real init's infinite loop is for, and it is why
[`tools/target/init`](../../../tools/target/init) ends in either `exec /bin/sh` or `poweroff -f`
and never simply falls off the end. **A script that runs to completion as PID 1 panics the
machine**, which is a memorable way to discover you forgot the last line.

The pair together is the point. You cannot kill init, and init must not leave.

---

## A.8 BusyBox, measured

The entire userland of this target is one binary. Not one binary per command; one binary:

```text
# ls -l /bin/busybox
-rwxr-xr-x    1 root     root       2108608 ... /bin/busybox
# busybox --list | wc -l
402
```

**402 commands in 2,108,608 bytes**, statically linked, with no libc alongside it. Every command
in `/bin` is a symlink to that one file, and BusyBox decides what to do by looking at `argv[0]`.

```text
# ls -l /bin/ls
lrwxrwxrwx    1 root     root            12 ... /bin/ls -> /bin/busybox
```

Compare against a desktop: GNU coreutils alone is around 5 MB for roughly 100 commands, before
libc, and a full `/usr/bin` is hundreds of megabytes. The ratio is not subtle.

**What it costs is real and specific, and comes in three kinds.**

*Missing applets.* Some tools simply are not there. On this target:

| Tool         | Present | Why                                                            |
| ------------ | ------- | -------------------------------------------------------------- |
| `dmesg`      | Yes     | BusyBox applet                                                 |
| `ps`, `top`  | Yes     | BusyBox applets, with fewer options than the ones you know     |
| `lsof`       | Yes     | BusyBox applet, and much reduced: it lists fds and little else |
| `free`       | Yes     | BusyBox applet                                                 |
| `strace`     | **No**  | Not a BusyBox applet at all; it is a separate program          |
| `ss`         | **No**  | Same                                                           |
| `vmstat`     | **No**  | Same                                                           |
| `journalctl` | **No**  | It is systemd's, and this system has no systemd                |

Check for yourself with `busybox --list | grep -x vmstat`, which prints nothing.

The last two rows are two different absences and it is worth keeping them apart. `strace`, `ss`
and `vmstat` are absent because nobody wrote a BusyBox applet for them and you could cross-compile
and install one. `journalctl` is absent because it is part of a different init system; there is
nothing to install, because there is no journal.

*Reduced options.* `busybox find` has no `-printf`. `busybox ps` does not take most of the flags
you know. The applet is there and the flag is not, which is the more annoying failure because it
shows up halfway through a script.

*Different behaviour.* The worst kind, because it is silent. This course has already been bitten
by one: **BusyBox's `rmmod` returns success even when the kernel refused to unload the module**,
which is why L04's lab checks whether the module is still loaded instead of checking an exit
status. A test written against coreutils behaviour passes on your laptop and lies on the target.

The engineering summary is that BusyBox is what you ship and coreutils is what you develop
against, and the difference between them is a category of bug that only appears on the target.
Test scripts on the target, not on your laptop.

---
