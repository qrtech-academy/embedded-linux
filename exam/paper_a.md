# Embedded Linux and Kernel Drivers - Written Examination, Paper A

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

**Supplied, because nobody could be expected to carry them:** the GIC SPI base is 32; the page size
is 4096 bytes; `msecs_to_jiffies` rounds up.

---

## Question 1 - The image, and the licence on it (12 marks)

A product ships an ARM64 board running Linux. Its flash contains a bootloader, a kernel, and a root
filesystem holding BusyBox, an MQTT library under Apache-2.0, and a control daemon the company
wrote. One driver was added to the kernel tree. One further driver is built out of tree and the
company would prefer to keep it closed.

**a)** Name the four pieces of an embedded Linux system. One of them is not on the flash. Which,
and what does it determine about the other three? **(3)**

**b)** A customer requests the source. Go through the six components above and say for each what
must be published. **(4)**

**c)** BusyBox was not modified. Does that change your answer for it? State the rule. **(2)**

**d)** The control daemon makes system calls into the kernel and is not published. The out-of-tree
driver is linked into the kernel's address space. Explain why the first is settled and the second
is not, naming the text that settles the first and the argument that applies to the second. **(3)**

---

## Question 2 - Asking a running kernel a question (8 marks)

**a)** `cat /proc/uptime` prints two numbers. Where were those numbers a microsecond before the
command ran? Give the mechanism, not a metaphor. **(2)**

**b)** State two consequences of that mechanism for a program reading `/proc`, and for each say
what a program that ignores it does wrong. **(3)**

**c)** `/proc` and `/sys` are both generated on read. State the difference between them in terms of
where their contents come from, and say which of the two is a documented ABI. **(2)**

**d)** `ls -l /dev/null` shows two numbers where a size would be. Name them and say what each
selects. **(1)**

---

## Question 3 - Configuring a kernel, and what it costs (10 marks)

From `drivers/gpio/Kconfig`:

```text
config GPIO_SYSFS
	bool "/sys/class/gpio/... (sysfs interface)" if EXPERT
	depends on SYSFS
	select GPIO_CDEV
```

**a)** Your `.config` has `CONFIG_SYSFS=y` and `# CONFIG_EXPERT is not set`. You add
`CONFIG_GPIO_SYSFS=y` to a fragment and run `olddefconfig`. What is in the final `.config`, and
why? **(3)**

**b)** Explain the difference between `depends on` and `select` in one sentence each. Which of the
two can produce a `.config` that violates a `depends on` line elsewhere, and how? **(3)**

**c)** A symbol has `default y` and its prompt is hidden. Is it set? Explain how a symbol nobody
was asked about acquires a value. **(2)**

**d)** A driver for the eMMC holding the root filesystem is configured `=m`, on a system with no
initramfs. State what happens at boot and quote the shape of the message. **(2)**

---

## Question 4 - A module, written out (12 marks)

**a)** Write a complete kernel module. It must print a greeting on load and a farewell on unload,
take a string parameter `who` defaulting to `"world"` that is readable but not writable through
sysfs, and carry the macros a module needs. Use `pr_fmt` so every message is prefixed with the
module name. **(7)**

**b)** Your `module_init` function returns 0. What is running afterwards, and what is resident?
**(2)**

**c)** Name what `__init` does. It is not a comment. **(1)**

**d)** `modinfo` reports
`vermagic: 6.12.30 SMP preempt mod_unload modversions aarch64`. Name what two of those six fields
assert, and say why a mismatch is an error rather than a warning. **(2)**

---

## Question 5 - The character device contract (12 marks)

A driver presents `/dev/qa_fifo`, backed by a byte ring buffer of capacity 256, currently empty.

**a)** Give the return value of every call in this sequence, and the level after each: **(5)**

```text
1.  write of 200 bytes
2.  write of 100 bytes
3.  read  of 512 bytes
4.  read  of 512 bytes
5.  write of 300 bytes
```

**b)** Step 2 is the one most people get wrong. State what it returns and which part of the
contract decides it. **(2)**

**c)** Give what this driver should return in each of these situations, and say what userspace
sees for each: a non-blocking read with nothing buffered; a write with the buffer full; a
`copy_to_user` that fails; and a read asking for zero bytes. **(3)**

**d)** `read` is handed a `char __user *`. Name the three separate things that are wrong with
dereferencing it directly. **(2)**

---

## Question 6 - An address, translated and mapped (12 marks)

A device tree contains:

```text
/ {
        #address-cells = <2>;
        #size-cells = <2>;

        bus@c000000 {
                #address-cells = <1>;
                #size-cells = <1>;
                ranges = <0x00 0x00 0xc000000 0x2000000>;

                widget@0 {
                        compatible = "acme,widget-1.0";
                        reg = <0x00 0x1000>;
                        interrupts = <0x00 0x70 0x04>;
                };
        };
};
```

**a)** How many 32-bit cells does `widget`'s `reg` occupy, and how do you know? **(2)**

**b)** What physical address do the registers start at, and how large is the window? Show the
arithmetic. **(3)**

**c)** A colleague reads `reg` and maps `0x0`. Name the two different things that could happen
when the driver then reads its identity register, and say which of the two is worse to debug.
**(3)**

**d)** Decode `interrupts = <0x00 0x70 0x04>`. Give the type, the number, the trigger, and the GIC
hardware number. **(2)**

**e)** Rewrite the driver's acquisition of the register window as a platform driver would do it,
in one line, and name what that line replaced. **(2)**

---

## Question 7 - A race, traced (10 marks)

Four kernel threads each increment a shared `unsigned long` twenty thousand times, with no lock, on
a two-CPU machine.

**a)** What is the expected final value? **(1)**

**b)** A run reports 63,562. How many increments were lost, and what percentage? **(2)**

**c)** `counter++` is one line of C. How many machine operations is it, and describe the
interleaving that loses one increment. **(3)**

**d)** The same program with `increments=200` per thread returns the correct answer every time,
over many runs. Is the bug absent at that size? Explain what is actually different. **(2)**

**e)** A colleague proposes making the counter `atomic_t` rather than adding a lock. For this
program, does that work? Now suppose the threads must also maintain a running maximum alongside the
counter. Does it still work? State the rule. **(2)**

---

## Question 8 - An interrupt, acknowledged (10 marks)

`/proc/interrupts` on a running system contains:

```text
 17:       1789          0  GIC-0 144 Level     qa_irq
```

and the device tree for that device says `interrupts = <0 112 4>`.

**a)** Three different numbers identify this interrupt. Name all three, give their values, and say
where each comes from. **(3)**

**b)** Write the body of a hard interrupt handler for a device whose `IRQ_STATUS` is
write-one-to-clear and whose FIFO must be drained. Return the correct value in both the
"mine" and "not mine" cases. **(4)**

**c)** Your handler acknowledges before draining rather than after. Describe the sequence of events
that results, and say whether data is lost. **(2)**

**d)** Your handler does not acknowledge at all. State the consequence. **(1)**

---

## Question 9 - A reader put to sleep (8 marks)

**a)** This code is intended to wait until data is available, and the reader has already joined
the wait queue the interrupt handler wakes. Now and then it sleeps until the next interrupt
instead, and if no further interrupt comes, forever. Describe the interleaving that causes it,
being precise about where the interrupt lands. **(3)**

```c
if (fifo_empty()) {
        set_current_state(TASK_INTERRUPTIBLE);
        schedule();
}
```

**b)** `wait_event_interruptible` takes a *condition* rather than a variable. Give two separate
reasons: one about the failure in **a)**, and one about what happens after a wake. **(2)**

**c)** State what `read` must return in each of these: data available; empty and blocking; empty
with `O_NONBLOCK`; and a signal arriving during the wait. **(2)**

**d)** Name the two families of delay function, and give the single question that chooses between
them. **(1)**

---

## Question 10 - Frameworks, and the trade (6 marks)

**a)** A driver presents a character device with two `ioctl`s of its own. Name three things a
subsystem would have given it that it does not have. **(2)**

**b)** Registering with IIO creates `in_voltage0_raw` in sysfs. Name what the driver had to
implement for that to appear, and what it did **not** have to implement. **(2)**

**c)** The same measurement on two kernels gives a mean of 449 us and a maximum of 11,321 us on
`PREEMPT`, and 551 us and 4,964 us on `PREEMPT_RT`. State which kernel is better and defend the
answer in one sentence. **(2)**

---

**End of Paper A.**
