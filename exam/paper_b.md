# Embedded Linux and Kernel Drivers - Written Examination, Paper B

**Time:** 4 hours. **Closed book.** No machine, no compiler, no reference material.
**Total: 100 marks.**

This paper exists to test your own skills and knowledge. It is not a qualification and it gates
nothing. It draws on all twelve lectures, so **it is meant to be taken once the course is over**.

---

## Rubric

**The kernel is Linux 6.12**, configured as the course configures it: `HZ=250`, so one jiffy is
4 ms; `CONFIG_PREEMPT=y` unless a question says otherwise; two CPUs.

**Code is marked on semantics, not on syntax.** A missing semicolon, a forgotten header or a brace
in the wrong column costs nothing. A `memcpy` where `copy_to_user` was needed costs everything.
Answers may be written in kernel C or in unambiguous pseudocode.

**Where a question says "state the consequence"**, naming the defect earns half the marks and
saying what it does to the running system earns the other half. "This is wrong" scores nothing.

**Where a question asks you to find defects, the number is stated.** Listing more is not penalised,
but only the stated number is marked, so put your strongest answers first.

**The device** is `qa-dev`. Any register a question depends on is given in the question. You are
expected to know that `readl`/`writel` are the only legal way to touch an `__iomem` pointer, and
that its `IRQ_STATUS` is write-one-to-clear.

**This paper is about failure.** Nearly every question hands you something that compiles, loads, or
runs, and does something other than what its author intended. In most cases the system reports
nothing at all, and saying **how you would have found it** carries marks in its own right.

**Supplied:** the GIC SPI base is 32; the page size is 4096 bytes; `msecs_to_jiffies` rounds up;
`USER_HZ` is 100.

---

## Question 1 - What leaves the building, and when it does not (10 marks)

**a)** State, in one sentence, the only question an open source licence answers. **(1)**

**b)** A colleague says "we ship Linux, so all our code has to be open source". Identify the part of
that sentence that is wrong and the part that is right, and name the specific text that settles it.
**(3)**

**c)** Your product satisfies the GPL with a written offer rather than by shipping source
alongside. State what you must be able to produce, and for how long. Name the engineering
consequence, which is not a legal one. **(3)**

**d)** An audit script greps for `SPDX-License-Identifier` and reports six distinct licences in a
directory. Reading the files by hand finds three. Explain the discrepancy. **(2)**

**e)** The same script finds no file marked `Proprietary` and the colleague concludes the tree
contains nothing proprietary. Give two separate faults in that inference. **(1)**

---

## Question 2 - A number that is not what it says (12 marks)

**a)** `/proc/stat` reports CPU time in units of 1/100 s regardless of `CONFIG_HZ`. A driver author
divides those figures by `HZ`, which is 250. By what factor is the answer wrong, and in which
direction? **(2)**

**b)** Two consecutive samples of `/proc/stat` on a two-CPU machine, 2.50 s apart, show the idle
field rising by 447 units. Convert that to seconds. It exceeds the wall-clock interval. Explain why
that is not a mistake. **(3)**

**c)** A script computes context switches per second by sampling `/proc/stat` twice and dividing by
the `sleep 1` it asked for. Name the two separate errors in that method. **(2)**

**d)** Ten runs of that script on one idle machine give ten different values, the largest several
times the smallest. State what that spread tells you about the quantity being measured, and how
many significant figures the result should be reported to. **(2)**

**e)** `HZ` is 250. Give the measured duration of `msleep(1)`, `msleep(4)` and `msleep(10)`, and
explain why two of the three are the same number. `msleep`'s own source contains no rounding-up
term; name where the extra time comes from. **(3)**

---

## Question 3 - An option that did not survive (10 marks)

You add `CONFIG_PREEMPT_RT=y` to a config fragment, merge it, run `olddefconfig` and build. The
kernel builds cleanly, boots, and `/proc/version` says `PREEMPT`.

**a)** Explain what happened. `PREEMPT_RT` is declared
`depends on EXPERT && ARCH_SUPPORTS_RT`, and the architecture selects the second. **(3)**

**b)** State why this failure is worse than a build error, and describe the first symptom you would
actually have noticed. **(2)**

**c)** Describe a mechanical check that would have caught it at configure time, and say what makes
it possible to write. **(2)**

**d)** Removing `CONFIG_IKCONFIG` from a kernel shrinks `vmlinux`'s section total by 41,208 bytes
and the `Image` by 65,536. The object it removes contributes 34,138 bytes. Account for both
differences. **(3)**

---

## Question 4 - A module that will not load (12 marks)

**a)** A module compiles and links, and `insmod` reports `Unknown symbol qa_answer (err -2)`. Give
**three** distinct causes, and say how you would distinguish them. **(4)**

**b)** One of those causes involves no error in your code at all and produces a message that does
not mention the real problem. Name it and explain why the message is misleading. **(3)**

**c)** A second module fails with `invalid module format`. What disagreed, and what would you do
about it? **(2)**

**d)** A build fails with
`ERROR: modpost: GPL-incompatible module mine.ko uses GPL-only symbol 'bar'`. Contrast this failure
with the one in **b)**: which is better to receive, and why? **(2)**

**e)** After loading a proprietary module, `/proc/sys/kernel/tainted` reads 4097 and one further
line appears in `dmesg` that is not about licensing. State what it says and what has been lost.
**(1)**

---

## Question 5 - A read that returns zero (12 marks)

This is the `read` of a character device backed by a ring buffer. It compiles, it loads, and a
program using it appears to work until it does not. `priv->lock` is a `spinlock_t` and
`qa_fifo_get` returns the number of bytes it actually removed.

```c
static ssize_t qa_read(struct file *file, char __user *buf, size_t count, loff_t *pos)
{
        unsigned long flags;
        u8            tmp[64];
        size_t        n;

        spin_lock_irqsave(&priv->lock, flags);

        if (priv->level == 0) {
                spin_unlock_irqrestore(&priv->lock, flags);
                return 0;
        }

        n = qa_fifo_get(priv->fifo, tmp, min(count, sizeof(tmp)));
        memcpy(buf, tmp, n);

        spin_unlock_irqrestore(&priv->lock, flags);
        return count;
}
```

**a)** This function has **four** defects. Name each one and state its consequence. **(8)**

**b)** Give the correct return value in each of the four situations a blocking `read` faces: data
available; empty and blocking; empty with `O_NONBLOCK`; and a signal arriving during the wait.
**(2)**

**c)** The same driver implements `read` but not `poll`. A program calls `select` on the
descriptor. State what happens, and what the driver must implement. **(2)**

## Question 6 - A mapping that is wrong (10 marks)

**a)** A driver maps a physical address one page past its device and reads the identity register.
Describe what happens on ARM64, and what state the module and the machine are left in. **(3)**

**b)** A different driver maps an address far below its device and reads the same register,
obtaining `0x00000000` with no error. Which of the two failures is more dangerous, and why? **(2)**

**c)** From **a)** and **b)**, state the general rule about using "it did not crash" as evidence
that a mapping is correct, and name the one defensive measure that would have caught both. **(2)**

**d)** A driver stores the result of `ioremap` in a `void *` rather than a `void __iomem *`, and
accesses it with `*ptr` rather than `readl`. It compiles and appears to work. Name **three**
distinct things that can now go wrong. **(3)**

---

## Question 7 - A deadlock that has not happened (12 marks)

A module's init function, running on one thread, takes lock A then lock B and releases both, then
takes lock B then lock A and releases both. It loads successfully. `dmesg` then contains
`WARNING: possible circular locking dependency detected` and a diagram headed
`*** DEADLOCK ***` with a CPU0 and a CPU1 column.

**a)** Nothing deadlocked and only one thread ran. Explain why the report was produced anyway.
**(3)**

**b)** The diagram has two CPU columns. How many CPUs executed this code? State what the columns
actually represent. **(2)**

**c)** Name the facility that produced the report, the config option that enables it, and what it
costs. **(2)**

**d)** A second module loses up to 38% of its increments to a data race, on the same kernel, and
the same facility reports nothing at all. Explain precisely why, and state the general limitation.
**(3)**

**e)** A colleague argues an ABBA ordering that has run for two years without deadlocking is
therefore correct. Rebut it in two sentences. **(2)**

---

## Question 8 - An interrupt that never stops (10 marks)

A level-triggered device is given a handler that reads its status register, counts the interrupt,
and returns `IRQ_HANDLED` without writing to `IRQ_STATUS`.

**a)** Describe what happens from the first interrupt onwards. State what `insmod` does. **(3)**

**b)** Roughly half a minute later the console prints a message about RCU stalls and an NMI sent
between CPUs. Explain the connection to the missing write, given that the message mentions neither
interrupts nor the driver. **(3)**

**c)** A test harness runs this. State what it should report, and why that is different from a
failing test. **(2)**

**d)** The same omission on an **edge**-triggered device does not wedge the machine. State what
happens instead, and which of the two failures you would rather ship. **(2)**

---

## Question 9 - A driver that finds its own hardware (6 marks)

**a)** A platform driver's `probe` is never called. Give **four** things you would check, in the
order you would check them. **(3)**

**b)** A driver is unbound by hand through sysfs while its module remains loaded. State what
happens to the memory region, the interrupt and the sysfs attributes it acquired with `devm_`, and
what that tells you about what `devm_` is attached to. **(2)**

**c)** The same driver keeps its register pointer in a file-scope `static`. Describe the machine on
which that stops working. **(1)**

---

## Question 10 - Worse average, better maximum (6 marks)

The same latency measurement on two kernels, idle, over 2,000 samples:

```text
PREEMPT      mean  449 us   max 11,321 us
PREEMPT_RT   mean  551 us   max  4,964 us
```

**a)** State which kernel a throughput-oriented reviewer would prefer, which a real-time
requirement would demand, and why both are reading the table correctly. **(2)**

**b)** Repeating the `PREEMPT` measurement gives a maximum of 2,502 us. State what that does to any
conclusion drawn from the table, and what would be needed to draw one safely. **(2)**

**c)** Both figures were measured under an emulator. Name **two** components other than the guest
kernel that are inside those numbers, and state precisely what survives the comparison and what
does not. **(2)**

---

**End of Paper B.**
