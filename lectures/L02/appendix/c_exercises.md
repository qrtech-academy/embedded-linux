# Appendix C - Exercises
Nine, ending with the Cross-check. Do them in order; the last one needs the script from C.6.

Several have a plausible wrong answer that is worth walking into before you find it. Where an
exercise can be checked mechanically, a **Check yourself** line says how.

Everything here runs on the target. Get a shell with `make boot`, and remember that Ctrl-A X quits
QEMU. A few parts ask you to compare against your own machine, and say so where they do.

---

## C.1 Recall: what the shell does and what it does not

For each of the following, say whether the **shell** does it or the **program** does it, and in
one sentence why.

**a)** Expanding `*.c` into a list of filenames.

**b)** Deciding what to do when given the argument `-l`.

**c)** Sending output to a file because the line ended in `> out.txt`.

**d)** Changing the current directory.

**e)** Reporting `No such file or directory` when a file is missing.

**f)** Substituting the value of `$HOME`.

Then: `grep foo *.log` is run in a directory containing no `.log` files at all. What does `grep`
receive as its arguments, and what happens?

---

## C.2 Recall: pipelines

**a)** How many processes does `ps | grep sh | wc -l` create, and how many pipes?

**b)** In the two-stage pipeline `A | B`, the shell closes both ends of the pipe after forking
both children. Name what breaks if it does not close the *write* end, and say which process
suffers.

**c)** `yes | head -1` terminates promptly rather than filling memory. Explain the mechanism, in
terms of what happens to the writer.

**d)** `grep pattern file | wc -l` returns exit status 0 even when `grep` matched nothing. Why,
and what would you add to a script to make that a failure?

---

## C.3 Hand calculation: reading `/proc/stat`

Here are two consecutive samples of `/proc/stat` from a target, taken with the given uptimes:

```text
sample 1, /proc/uptime says 3.90 2.52
cpu  16 0 341 252 0 75 25 0 0 0
ctxt 1626
processes 63
procs_running 1

sample 2, /proc/uptime says 6.40 6.99
cpu  19 0 383 699 0 81 27 0 0 0
ctxt 1901
processes 71
procs_running 2
```

**a)** How many context switches per second, over this interval?

**b)** How many processes were created per second?

**c)** The `cpu` line's fourth field is idle time. By how many units did it increase, and how many
seconds is that? State the unit you used and why.

**d)** There are two CPUs. Over the 2.50 s interval, how much CPU time was available in total, and
how much of it was spent idle? Does your answer to **c)** exceed the wall-clock interval, and if
so, why is that not a mistake?

**e)** Which of the four numbers you have computed would be different if the kernel had been built
with `CONFIG_HZ=1000` instead of 250?

---

## C.4 Hand calculation: device numbers

From a target's `/proc/devices` and `/dev`:

```text
  1 mem
  4 tty
  5 /dev/tty
 10 misc
204 ttyAMA
254 gpiochip

crw-rw-rw-    1 root root    1,   3 /dev/null
crw-------    1 root root    5,   1 /dev/console
crw-------    1 root root  254,   0 /dev/gpiochip0
crw-rw-rw-    1 root root    1,   5 /dev/zero
```

**a)** `/dev/null` and `/dev/zero` have the same major and different minors. What does that tell
you, and what does it not?

**b)** Which driver handles `/dev/console`?

**c)** You run `mknod /dev/spare c 204 64`. Does the command succeed? Does opening the node
succeed? Are those the same question?

**d)** You run `mknod /dev/bogus c 42 0`. Same two questions.

**e)** A colleague deletes `/dev/null` and says the null device is gone. What is actually gone,
and what is not?

---

## C.5 Design: which file answers the question

For each question, name the single file under `/proc` or `/sys` that answers it, and say why the
obvious alternative is worse.

**a)** Which preemption model was this kernel built with?

**b)** How many CPUs does this machine have?

**c)** What did the bootloader pass to the kernel?

**d)** How many times has the timer interrupt fired on CPU 1?

**e)** Which physical addresses has a driver claimed?

**f)** What is the name of the program running as PID 1?

**g)** Which files does process 56 currently have open?

---

## C.6 Code: the machine report

Write `lectures/L02/lab/machine-report.sh`, a POSIX shell script that runs on the target and
prints one `key: value` line per fact, in any order. It is checked by the shipped
[`lab/run.sh`](../lab/run.sh), so the key names are a contract.

| Key              | Value                                            |
| ---------------- | ------------------------------------------------ |
| `kernel`         | The kernel version alone, for example `6.12.30`  |
| `cpus`           | The number of CPUs                               |
| `memtotal-kb`    | Total memory in kB, as an integer                |
| `uptime-s`       | Seconds since boot                               |
| `cmdline`        | The kernel command line, verbatim                |
| `init`           | The name of the program running as PID 1         |
| `chardev-majors` | How many **character device** majors are claimed |
| `ctxt-per-s`     | Context switches **per second**, measured        |

Rules, all of which the test enforces:

* **Every key appears exactly once.** A report with a key twice is a report whose reader gets
  whichever line comes first.
* **`kernel` is the version alone**, not the whole of `/proc/version`.
* **`chardev-majors` counts character devices only.** `/proc/devices` has two sections and
  counting both is the plausible wrong answer.
* **`ctxt-per-s` is a rate, not a counter.** `/proc/stat`'s `ctxt` is a total since boot; nothing
  in `/proc` gives you a rate, so you must sample twice and divide by the time that actually
  elapsed rather than by the time you asked for.
* Use only what is on the target. In particular there is no `vmstat` and no `strace`. `awk` can
  do arithmetic.

**Check yourself:** `make build L=L02` does nothing for this lecture, since there is no module.
Run `make test L=L02`; before you have written the script it reports `SKIPPED`, and afterwards it
should report `PASSED` with eighteen checks.

---

## C.7 Code: PID 1 is not an ordinary process

Two short experiments on the target. Predict the outcome of each **before** running it, and write
your prediction down.

**a)** Run `kill -9 1`. What did you predict, what happened, and what does that tell you about the
protection PID 1 has?

**b)** Now the other half. You cannot easily make the real init exit, so reason it out instead:
[`tools/target/init`](../../../tools/target/init) ends with either `exec /bin/sh` or `poweroff -f`.
What would happen if you deleted that last line and the script simply ran off the end? Name the
exact kernel message.

**c)** A daemon's parent exits while the daemon is still running. What is the daemon's `PPID`
afterwards, and who is now responsible for calling `wait()` on it?

---

## C.8 Design: what a two-megabyte userland costs you

**a)** On the target, find the size of `/bin/busybox` and the number of applets it provides. Then
work out the average bytes per command, and say why that number is misleading.

**b)** Check whether each of `strace`, `ss`, `vmstat`, `lsof` and `journalctl` is present. For each
absent one, say which of two reasons applies: *no BusyBox applet exists*, or *the subsystem it
belongs to is not on this system*.

**c)** You need to find out which files a stuck process has open, on a target with no `lsof` at
all. What do you do instead?

**d)** Name a class of bug that only appears on the target and never on your development machine,
and give the concrete example this course has already hit.

---

## C.9 Cross-check: a rate measured three ways

The signature exercise. You will compute a number by hand, have your script compute it, and then
run the script repeatedly, and the three will not agree. The disagreement is the exercise.

**a) By hand.** On the target, run this twice with a pause you time yourself, using a watch or a
phone rather than the machine:

```sh
cat /proc/uptime; awk '/^ctxt/ { print $2 }' /proc/stat
```

Compute context switches per second from your two readings. Write the number down.

**b) By script.** Run your `machine-report.sh` from C.6 and record its `ctxt-per-s`.

**c) Three more times.** Run the script three times in a row and record all three values.

**d) Reconcile.** Answer each of these:

* By how much do your three script runs differ from each other, as a percentage of the largest?
  Is `ctxt-per-s` a property of the machine, or a property of the moment you measured it?
* Your script prints a value with a decimal point. How many of those digits are meaningful? What
  would be an honest way to present this number?
* Compare the hand figure to the script figure. Your hand interval was several seconds and the
  script's was about one. Which would you expect to be steadier, and did that hold?
* Now remove the `sleep` from your script so the two samples are taken back to back, and run it
  again. The measured interval is roughly 0.14 s. What does the rate do, and why is a
  short interval worse rather than better, given that it is closer to "now"?

**e)** You would like to check your answer against `vmstat`, which reports exactly this number.
Try it. Then say what happened, what it tells you about this target, and how you would check the
answer without it.

**f)** A colleague reads your report, sees `ctxt-per-s: 73.3`, and puts it in a datasheet as the
machine's context-switch rate. Give two separate reasons that is wrong.

---
