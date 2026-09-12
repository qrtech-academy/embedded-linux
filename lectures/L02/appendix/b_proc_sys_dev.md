# Appendix B - `/proc`, `/sys`, and `/dev`
Three directories that are not what they look like. Between them they are how a running Linux
system is inspected, and every diagnostic tool you will ever use is a program that reads one of
them and formats the result. `top` reads `/proc`. `lsblk` reads `/sys`. Knowing that is the
difference between using tools and being able to answer a question no tool answers.

Every listing in this appendix was produced on the target this course builds; you can reproduce
each one with the command shown.

---

## B.1 `/proc` is generated on read

Start with the demonstration, because the rest of the appendix follows from it:

```text
# cat /proc/uptime
3.95 2.36
```

Two numbers: seconds since boot, and seconds spent idle summed across CPUs. Now the question that
matters. **Where were those numbers a microsecond before you ran that command?**

Nowhere. There is no file. There is no disk. There is no buffer holding "3.95" waiting to be read.
When `cat` opened the path, the kernel ran a function; when `cat` read, that function formatted a
string from live kernel variables and returned it. Close the file and the string ceases to exist.

`/proc` is a *filesystem interface to kernel data structures*. It is mounted, like any filesystem:

```text
# grep proc /proc/mounts
none /proc proc rw,relatime 0 0
```

and it is `none` because there is no device behind it. It is a filesystem in the sense that the
kernel's VFS layer can route `open` and `read` to it, and in no other sense.

Four consequences follow, and all four catch people:

* **Every file appears to have size 0.** The kernel does not know how long the answer will be until
  it generates it. So `ls -l /proc` is useless and `wc -c < /proc/uptime` is the only way to find
  out how big something is.
* **Reading twice gives different answers**, and there is no guarantee of consistency *between*
  two reads. This is the subject of the Cross-check.
* **A seek regenerates it.** `lseek` from the start or from the current position works on most of
  it, but only by producing the text again up to the offset, so what follows the offset need not
  match what you read before it. A seek from the end fails with `EINVAL`, because there is no end
  until the text has been produced. Tools that `mmap` files do not work on `/proc`.
* **A read can be expensive.** Reading `/proc/slabinfo` walks kernel data structures under a lock.
  Polling a `/proc` file in a tight loop is not free, and on a busy system it is measurable.

![Userspace above a dashed syscall boundary, and below it three equally sized boxes for /proc, /sys and /dev, each connected by a two-way arrow to a single box holding the kernel's live data structures. Nothing is stored: opening a path selects a function and reading it runs that function.](./images/kernel_interfaces.png)

---

## B.2 The files worth knowing

These nine answer most questions you will have about a running system.

| File               | Answers                                                     |
| ------------------ | ----------------------------------------------------------- |
| `/proc/version`    | Kernel version, compiler, build date, preemption model      |
| `/proc/cmdline`    | What the bootloader passed the kernel                       |
| `/proc/uptime`     | Seconds since boot, and idle seconds                        |
| `/proc/cpuinfo`    | One block per CPU                                           |
| `/proc/meminfo`    | Memory, in far more detail than `free` shows                |
| `/proc/stat`       | Counters since boot: CPU time, context switches, interrupts |
| `/proc/interrupts` | Interrupt counts per CPU per source. L08 lives here         |
| `/proc/devices`    | Which major numbers are claimed, and by what                |
| `/proc/iomem`      | The physical address map. L06 lives here                    |

On the target:

```text
# cat /proc/version
Linux version 6.12.30 (@f03d349e7b1d) (aarch64-linux-gnu-gcc (Debian 12.2.0-14) 12.2.0,
GNU ld (GNU Binutils for Debian) 2.40) #1 SMP PREEMPT ...

# cat /proc/cmdline
console=ttyAMA0 rdinit=/init qa.test=L02
```

Three facts in the first line: the version, the compiler, and that this is an `SMP PREEMPT` build.
That last word is a preemption model, it is `CONFIG_PREEMPT`, and L12 is about changing it.

The second line is the handover from bootloader to kernel. `console=` says where kernel messages
go, `rdinit=` names PID 1, and `qa.test=L02` is a parameter the kernel does not recognise. An
unknown `key=value` is normally passed on to PID 1's environment, but one with a dot in its name is
taken for a parameter of a module, here one called `qa`, and passed to nobody. It stays in
`/proc/cmdline`, which is where [`tools/target/init`](../../../tools/target/init) reads it to learn
which lecture to run.

### `/proc/stat`, in detail

This is the one the lab uses.

```text
# head -8 /proc/stat
cpu  16 0 341 252 0 75 25 0 0 0
cpu0 8 0 194 96 0 41 13 0 0 0
cpu1 8 0 146 156 0 34 11 0 0 0
intr 2274 0 76 635 0 0 0 3 0 0 0 ...
ctxt 1626
btime 1787646992
processes 63
procs_running 1
```

| Line            | Means                                                            |
| --------------- | ---------------------------------------------------------------- |
| `cpu`           | Aggregate CPU time, in **USER_HZ units**, not seconds. See below |
| `cpu0`, `cpu1`  | The same, per CPU. There are two here because `-smp 2`           |
| `intr`          | Total interrupts, then a count per interrupt source              |
| `ctxt`          | **Total context switches since boot.** A monotonic counter       |
| `btime`         | Boot time, as a Unix timestamp                                   |
| `processes`     | Total processes ever forked since boot                           |
| `procs_running` | Processes currently in state `R`                                 |

The ten `cpu` fields are user, nice, system, idle, iowait, irq, softirq, steal, guest, guest_nice.

**`ctxt` is a counter, not a rate.** Nothing in `/proc` tells you context switches per second; to
get a rate you read the counter twice, subtract, and divide by the elapsed time. That is what
`vmstat` does internally, and doing it yourself is the lab.

**The USER_HZ trap.** The CPU times are in units of 1/100 s **regardless of `CONFIG_HZ`**. Our
kernel has `CONFIG_HZ=250`, so a jiffy is 4 ms, but `/proc/stat` still reports in 10 ms units,
because `USER_HZ` is fixed at 100 for ABI compatibility. Dividing by `HZ` instead of by 100 is a
common and silent error, and it is worth 2.5x here.

---

## B.3 `/proc/<pid>/`, and `/proc/self`

Every process has a directory named by its PID.

| Path         | Holds                                            |
| ------------ | ------------------------------------------------ |
| `cmdline`    | The full command line, arguments NUL-separated   |
| `comm`       | The short name, writable, 15 characters          |
| `status`     | Human-readable state, memory, UIDs, thread count |
| `stat`       | The same in one machine-readable line            |
| `fd/`        | One symlink per open file descriptor             |
| `maps`       | The memory map                                   |
| `cwd`, `exe` | Symlinks to the working directory and the binary |

`/proc/self` is a magic symlink to the reading process's own directory, which is how a program
finds out about itself without knowing its PID:

```text
# grep -E '^(Name|State|Pid|PPid)' /proc/self/status
Name:	grep
State:	R (running)
Pid:	70
PPid:	56
```

Note that `Name` is `grep` and not the shell. The shell runs `grep` in a child process, and it is
that child reading its own directory. This confuses people the first time and is worth reproducing.

`fd/` is the most useful of these in practice. It is what `lsof` reads, and it will tell you which
file a stuck process is holding open when nothing else will.

---

## B.4 `/sys`, and why it is not `/proc`

`/sys` is also generated on read, so everything in B.1 applies. The difference is where its
contents come from and what the rules are.

**`/proc` grew organically.** It began as process information, then became the place anyone put
anything, and its files have no common format. `/proc/stat` is a table, `/proc/uptime` is two
floats, `/proc/meminfo` is key-value, and each was designed separately.

**`/sys` is generated from the driver model.** It is not written by hand at all: it is the kernel's
internal tree of buses, devices, drivers and classes, exposed as directories. Its rule is **one
value per file**, and that rule is the whole reason it is easy to script against.

```text
# ls /sys/bus
amba          gpio            platform        spi
clockevents   i2c             pnp             spmi
clocksource   mdio_bus        rpmsg           tee
container     memory          scmi_protocol   virtio
cpu           memory_tiering  serial          workqueue
...
```

Those are buses in the device model's sense, which is a matching policy rather than a physical
bus; `platform` is the one this course's driver ends up on. Under each, `devices/` and `drivers/`,
and the match between them is what calls `probe`. **All of this is L10**, and the reason it appears
here is that a reader should have walked the tree before being told what generates it.

The other top-level directories worth knowing now:

| Path                             | Holds                                               |
| -------------------------------- | --------------------------------------------------- |
| `/sys/class/`                    | Devices grouped by what they are, regardless of bus |
| `/sys/devices/`                  | The real tree; everything else is symlinks into it  |
| `/sys/module/`                   | One directory per loaded module. L04                |
| `/sys/firmware/devicetree/base/` | The device tree, unpacked. L10                      |
| `/sys/kernel/debug/`             | debugfs, if mounted. Not an ABI                     |

**The ABI distinction is the one that matters professionally.** `/sys` is a documented, stable
interface: a file that exists in one kernel version is expected to exist in the next, and
`Documentation/ABI/` records the promises. `/sys/kernel/debug` is explicitly *not*: debugfs may
change or vanish between releases, and shipping a product whose userspace depends on a debugfs
file is shipping a product that breaks on a kernel upgrade. L05 returns to this when deciding
where a driver should expose something.

---

## B.5 `/dev`, and the two numbers

```text
# ls -l /dev/null /dev/console /dev/gpiochip0
crw-rw-rw-    1 root root    1,   3 ... /dev/null
crw-------    1 root root    5,   1 ... /dev/console
crw-------    1 root root  254,   0 ... /dev/gpiochip0
```

Where a regular file shows a size, a device node shows **two numbers**. The first character of the
permissions says which kind:

* `c` is a **character device**: a stream of bytes, read and written in order. Serial ports,
  terminals, and everything this course writes.
* `b` is a **block device**: addressable in fixed-size blocks, cached by the kernel. Disks.

The two numbers are the **major** and **minor**. Major selects the *driver*; minor selects *which
device of that driver's*. `/proc/devices` lists the claimed majors:

```text
# cat /proc/devices
Character devices:
  1 mem
  4 tty
  5 /dev/tty
 10 misc
 89 i2c
204 ttyAMA
252 rtc
254 gpiochip
...
```

So `/dev/null` at major 1 is handled by the `mem` driver, minor 3 selecting the null behaviour;
`/dev/gpiochip0` at 254 is the GPIO subsystem, which L11 registers with. **A node is just a name
carrying two numbers.** Nothing stops you creating one for a driver that does not exist:

```text
# mknod /dev/nonsense c 42 0
# cat /dev/nonsense
cat: /dev/nonsense: No such device or address
```

The node was created happily. The open failed because no driver claims major 42. This is worth
doing, because it separates two things people conflate: the node in the filesystem, and the driver
registration in the kernel. **L05 creates the second, and something else creates the first.**

That something else on this target is **devtmpfs**:

```text
# grep dev /proc/mounts
none /dev devtmpfs rw,relatime,size=221248k,...
```

devtmpfs is a filesystem the kernel populates itself: when a driver registers a device, a node
appears. On a desktop, **udev** sits on top, applying naming rules, permissions and symlinks. This
target has no udev, which is why every node is owned by root with default permissions, and why
`/dev` here is shorter than the one on your laptop.

---

## B.6 Reading these files from a script

The lab asks you to build a report out of `/proc`, and there are four traps.

**Fields are positional and the separator is not consistent.** `/proc/stat` is space-separated
with a variable number of spaces after the label; `/proc/meminfo` is `key:` then whitespace then
value then a unit. `awk` handles both because it splits on runs of whitespace by default:

```sh
ctxt=$(awk '/^ctxt/ { print $2 }' /proc/stat)
mem=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
```

**Units are not always what they look like.** `/proc/meminfo` is in kB and says so. `/proc/stat`
CPU time is in USER_HZ, is always 1/100 s, and does *not* say so. `/proc/uptime` is in seconds
with two decimals.

**`/proc/cmdline` is space-separated; `/proc/<pid>/cmdline` is NUL-separated.** The same-looking
name, two different formats. `tr '\0' ' '` is the fix for the second.

**Two reads are two moments.** Anything computed from two files, or two reads of one file, is
computed from a system that changed in between. For a rate this is exactly what you want, as long
as you also measure the interval rather than assuming it:

```sh
a=$(awk '/^ctxt/ { print $2 }' /proc/stat)
t0=$(cut -d' ' -f1 /proc/uptime)
sleep 1
b=$(awk '/^ctxt/ { print $2 }' /proc/stat)
t1=$(cut -d' ' -f1 /proc/uptime)
```

Dividing `b - a` by 1 rather than by `t1 - t0` assumes `sleep 1` slept exactly one second. It did
not, and [Appendix C](./c_exercises.md)'s Cross-check is about how much that matters and why.

---

## B.7 What these three do not tell you

Worth stating, because a reader who has just learned to read `/proc` tends to believe it answers
everything.

* **`/proc` shows state, not history.** It cannot tell you what a process was doing a second ago,
  only what it is doing now. For history you need tracing, which is `ftrace` and `perf`.
* **Counters wrap and reset.** `ctxt` is 64-bit and will not wrap in practice, but plenty of
  counters are 32-bit, and all of them reset at boot. A rate computed across a reboot is nonsense.
* **`/proc/meminfo` does not tell you what is using memory.** It tells you how memory is
  classified. Attributing it to processes means walking every `/proc/<pid>/smaps`, and the numbers
  do not add up cleanly because pages are shared.
* **Nothing here is atomic.** There is no way to sample the whole system at one instant. Every
  tool that appears to, including `top`, is reading a sequence of files over a period of time.

---
