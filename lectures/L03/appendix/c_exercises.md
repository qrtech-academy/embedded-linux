# Appendix C - Exercises
Nine, ending with the Cross-check. Do them in order; C.9 needs a kernel build and is the one to
start early, because it takes about twenty minutes of waiting.

Where an exercise can be checked mechanically, a **Check yourself** line says how.

The kernel source is in `build/linux-6.12.30` and the built tree in `build/kernel`; both are there
after `make kernel`. Nothing here needs the network.

---

## C.1 Recall: what kind of program the kernel is

**a)** Name three things that are true of a userspace program and false of the kernel.

**b)** "Linux is a monolithic kernel." What exactly does that claim, and what does it **not** claim?
In particular, does it say anything about how the source is organised?

**c)** A userspace program dereferences a null pointer and the system carries on. The kernel
dereferences a null pointer. Describe what happens instead, and say why the difference is
structural rather than a matter of the kernel being better tested.

**d)** Why is there no `printf` in the kernel, given that there is obviously a way to print things?

---

## C.2 Recall: the two interfaces

**a)** State the stability guarantee on the system call interface, and the stability guarantee on
the kernel's internal API.

**b)** Those two answers are opposites. For each, give the practical consequence for someone
maintaining an out-of-tree driver.

**c)** A colleague proposes that Linux should have a stable driver ABI so that vendors can ship
binary drivers. Give the strongest argument against, and name the file in the tree that makes it.

**d)** Your driver is in the mainline tree. An internal API it uses changes. Who updates your
driver, and why?

---

## C.3 Hand calculation: reading Kconfig

From `drivers/gpio/Kconfig` in the pinned tree:

```text
config GPIO_SYSFS
	bool "/sys/class/gpio/... (sysfs interface)" if EXPERT
	depends on SYSFS
	select GPIO_CDEV # We need to encourage the new ABI

config GPIO_CDEV
	bool
	prompt "Character device (/dev/gpiochipN) support" if EXPERT
	default y
```

**a)** Your `.config` has `CONFIG_SYSFS=y` and `# CONFIG_EXPERT is not set`. You add
`CONFIG_GPIO_SYSFS=y` to a fragment and run `olddefconfig`. What is in the final `.config`, and
why?

**b)** Same question with `CONFIG_EXPERT=y`.

**c)** `GPIO_CDEV` has `default y` and a prompt behind `EXPERT`. With `EXPERT` off, is
`CONFIG_GPIO_CDEV` set? Explain how a symbol nobody was asked about gets a value.

**d)** Explain, in one sentence each, what `depends on` does and what `select` does. Then say which
of the two can produce a `.config` that violates a `depends on` line somewhere else, and how.

**e)** You want `/dev/gpiochipN` on a kernel with `EXPERT` off. Which symbol do you set, and does
it work?

---

## C.4 Hand calculation: built in or module

For each, say whether the option must be `=y`, may be `=m`, or cannot be `=m` at all, and give the
reason in one sentence.

**a)** The driver for the SATA controller holding the root filesystem, on a system with no
initramfs.

**b)** The same, on a system with an initramfs containing that driver.

**c)** `CONFIG_GPIOLIB`, which is declared `bool` rather than `tristate`.

**d)** A driver for a USB device the user may or may not plug in.

**e)** The filesystem type of the root filesystem, with no initramfs.

**f)** `CONFIG_PREEMPT_RT`.

---

## C.5 Design: navigating the tree

For each, say which directory you would look in **first**, and give the search you would run if
that did not find it.

**a)** The code that decides which task runs next.

**b)** The driver for an I2C temperature sensor.

**c)** The definition of `struct file_operations`.

**d)** The arm64 exception entry path.

**e)** The implementation of the `openat` system call.

**f)** The kernel message `Attempted to kill init!`.

For **f)**, actually run your search on the pinned tree and give the file and line.

---

## C.6 Code: the kernel report

Write `lectures/L03/lab/kernel-report.sh`, a POSIX shell script that runs on the target and reports
what the running kernel was configured with. It is checked by the shipped
[`lab/run.sh`](../lab/run.sh), so the key names are a contract.

| Key             | Value                                                     |
| --------------- | --------------------------------------------------------- |
| `version`       | The kernel version alone, for example `6.12.30`           |
| `smp`           | `yes` or `no`                                             |
| `preempt`       | One of `none`, `preempt`, `preempt_dynamic`, `preempt_rt` |
| `hz`            | The value of `CONFIG_HZ`, or `unknown` (see below)        |
| `modules`       | `yes` or `no`: can this kernel load modules at all        |
| `filesystems`   | How many filesystem types the kernel knows                |
| `char-majors`   | How many character device majors are claimed              |
| `config-source` | `config.gz` or `inferred` (see below)                     |

**The point of the exercise is the last two rows.** Some kernels are built with
`CONFIG_IKCONFIG_PROC`, which embeds the configuration and exposes it as `/proc/config.gz`; on
those, every question above can be answered by looking it up. Most kernels you meet in the field
are not, and then the same questions must be answered from other evidence, or admitted to be
unanswerable.

Your script must handle both:

* If `/proc/config.gz` is readable, report `config-source: config.gz` and read `hz` from it.
* If it is not, report `config-source: inferred`, and report `hz: unknown`.

**Report `unknown` rather than guessing.** There is no honest way to read `CONFIG_HZ` off a running
kernel without the config, and a script that prints a confident number it cannot justify is worse
than one that admits the gap. `run.sh` checks for exactly this.

Two more traps, both of which `run.sh` checks:

* **`char-majors` counts character devices only.** `/proc/devices` has two sections.
* **Test for `PREEMPT_RT` before `PREEMPT`.** The string `PREEMPT` is a prefix of `PREEMPT_RT`, so
  a `case` that tests the shorter one first reports an RT kernel as a plain preemptible one. L12
  depends on telling them apart.

**Check yourself:** `make test L=L03` reports `SKIPPED` before you write it and `PASSED` after,
with seventeen checks. Then do C.9, which turns `/proc/config.gz` off, and run `make test L=L03`
again; it must still pass, with `config-source` now reading `inferred`.

---

## C.7 Code: what is in this kernel that need not be

Using the running target and the built tree, answer with a command and a number.

**a)** How many modules did the build produce, and how many are installed on the target?

**b)** How many symbols does the kernel export to modules? Compare
`/proc/kallsyms` with the number of *exported* symbols in `build/kernel/Module.symvers`.

**c)** How much memory was returned to the system after boot by discarding `__init` code? Find the
kernel message that says so.

**d)** `Image` is 24 MB. How large is `vmlinux`, and account for the difference in one sentence.

**e)** Name three subsystems that are compiled into this kernel that the emulated machine cannot
possibly use, and find them in `/proc/filesystems` or `/proc/devices` to prove they are there.

---

## C.8 Design: a configuration for a real product

You are configuring a kernel for a product: an ARM64 SoC, 256 MB of RAM, one Ethernet interface,
an eMMC holding an ext4 root filesystem, an I2C sensor, and a watchdog. It boots from U-Boot with
no initramfs. It must support field updates of the sensor driver without a reboot.

**a)** For each of the seven components, say `=y`, `=m` or `=n`, and why.

**b)** Which of the decisions above would, if you got them wrong, produce a kernel that does not
boot at all? Describe the symptom.

**c)** The product later gains a second hardware variant with a different sensor. What changes
about your configuration strategy, and what would you use `savedefconfig` for?

**d)** Your build is taking forty minutes. Name the first thing to look at, and say roughly what
you expect to find, based on what `kernel/trim.config` does for this course.

---

## C.9 Cross-check: what one config option costs

Predict a number, change one line, measure, and reconcile. The three measurements disagree with
each other and with your prediction, and all of them are correct.

`CONFIG_IKCONFIG` embeds a compressed copy of the `.config` into the kernel so that the running
system can be asked what it was built with. It is a good option to measure because its
contribution is mostly one blob whose size you can find out in advance.

**a) Predict.** With the current kernel built, run:

```bash
size -A build/kernel/kernel/configs.o
```

Add up the four sections that B.6 counts as the option's content. That is what `CONFIG_IKCONFIG`
contributes. Write the number down.

**b) Check the prediction two other ways.** The bulk of it is the compressed config itself, and you
can measure that independently:

```bash
gzip -9 -c build/kernel/.config | wc -c        # on the host
ls -l /proc/config.gz                           # on the target, after make boot
```

Do all three agree? Should they be identical, and if not, why not?

**c) Record the baseline.** Note the exact byte counts of both `build/kernel/arch/arm64/boot/Image`
and `build/kernel/vmlinux`, and the section sizes from `size -A build/kernel/vmlinux`.

**d) Change one line.** Create `kernel/local.config`, which is merged last and is gitignored:

```bash
printf '# CONFIG_IKCONFIG is not set\n' > kernel/local.config
make kernel
```

**e) Measure the same three things again.** You now have, for the same one-line change:

* a change in `vmlinux`'s **section sizes**,
* a change in the **`vmlinux` file**,
* a change in the **`Image`**.

**f) Reconcile.** Answer each:

* Which of the three measurements is closest to your prediction from **a)**, and which is furthest?
  By what factor is the furthest one out?
* Look at the per-section deltas. Two sections account for nearly all of it. For each, compare the
  section's delta against the bytes `configs.o` contributed to it. They are not equal. What is the
  relationship between the two numbers, and what does 4096 have to do with it?
* The `Image` delta is a suspiciously round number. What is it a multiple of, and what does that
  tell you about how the `Image` is laid out?
* Given all that: if you now removed a *second* option contributing another 34 KB, would the
  `Image` shrink by the same amount again? Explain.

**g)** Boot the smaller kernel and run `make test L=L03`. Your report from C.6 should still pass,
with `config-source` now reading `inferred`. If it does not, C.6's requirement to handle both
worlds is the part you skipped.

**h)** A colleague asks "how much does `CONFIG_IKCONFIG` cost?". Give them a single number and a
sentence, and say which of your measurements you chose and why.

**Restore the kernel afterwards** with `rm kernel/local.config && make kernel`, so that later
lectures start from the configuration they were written against.

---
