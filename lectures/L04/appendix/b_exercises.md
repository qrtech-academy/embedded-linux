# Appendix B - Exercises
Nine, ending with the Cross-check. Do them in order; B.6 onwards need the modules from the lab.

Where an exercise can be checked mechanically, a **Check yourself** line says how. Several have a
plausible wrong answer that is worth walking into before you find it.

Everything here runs against the target from `make boot`, or against the built tree under
`build/kernel`. Nothing needs the network.

---

## B.1 Recall: a module is not a program

**a)** `qa_hello_init` returns 0. What is running afterwards, and what is resident?

**b)** Why is it a mistake to put a `while (1)` loop in a module's init function? What should you
have written instead, and what happens to `insmod` if you do it anyway?

**c)** What do `__init` and `__exit` actually do? Neither is a hint to the reader.

**d)** The boot log says `Freeing unused kernel memory: 4672K`. What relationship does that message
have to `__init`?

**e)** Name the four `MODULE_*` macros from the lab's module, and say which one is not optional and
what happens if you leave it out.

---

## B.2 Recall: four commands

**a)** State in one sentence each what `insmod`, `modprobe`, `depmod` and `rmmod` do.

**b)** `insmod` and `modprobe` are often described as the same command. Give the concrete
difference, and describe the experiment that demonstrates it using the lab's `qa_export` and
`qa_user`.

**c)** What file does `modprobe` read to decide what to load first, and what generates it?

**d)** `rmmod qa_export` fails while `qa_user` is loaded. Where, in `/sys`, can you see *which*
module is holding it, rather than merely how many are?

---

## B.3 Hand calculation: reading `vermagic`

`modinfo` on the lab's module reports:

```text
vermagic: 6.12.30 SMP preempt mod_unload modversions aarch64
```

**a)** Name what each of the six fields is asserting about the kernel this module may be loaded
into.

**b)** For each of the following changes to the kernel, say whether this module would still load,
and why:

* The kernel is rebuilt from the same source with no config change.
* The kernel is rebuilt with `# CONFIG_SMP is not set` in `kernel/local.config`. Read
  `arch/arm64/Kconfig` before answering.
* The kernel is upgraded from 6.12.30 to 6.12.31.
* The kernel is rebuilt with `CONFIG_PREEMPT_RT=y` instead of `CONFIG_PREEMPT=y`.

**c)** `modversions` appears in the list. What does `CONFIG_MODVERSIONS` add beyond the version
string, and what problem does it solve that `vermagic` alone does not?

**d)** Explain why a mismatch is reported as an error rather than being allowed with a warning.
What is the failure mode that policy is protecting you from?

---

## B.4 Hand calculation: the licence, at two stages

A module declares `MODULE_LICENSE("Proprietary")` and calls a function exported with
`EXPORT_SYMBOL_GPL`.

**a)** You build it in the same directory as the module that exports the symbol. What happens, at
which build step, and what exactly does the message say?

**b)** You build it in a directory of its own, where the build cannot see the exporting module's
symbols. What happens now, and why is it a *different* message?

**c)** Neither of those produced a `.ko`. Describe the circumstances in which a proprietary module
using a GPL-only symbol does build successfully and then fails at `insmod`.

**d)** In that case, what does `insmod` print? Read
[Appendix A.5](./a_modules.md#a5-the-licence-and-where-the-check-happens) and say why the message
does not mention a licence, in terms of what the module loader actually does with GPL-only
symbols.

**e)** Why is that the worst of the three messages to receive?

---

## B.5 Design: choosing a log level

For each, choose from `pr_debug`, `pr_info`, `pr_warn`, `pr_err`, and justify it in one sentence.

**a)** The driver has probed successfully and is ready.

**b)** A device returned a value outside its documented range, and you clamped it.

**c)** `ioremap` returned NULL and `probe` is about to fail.

**d)** You want to print the value of every register during development.

**e)** The device tree specified a clock rate the hardware cannot produce, so you used the nearest.

Then: **f)** why is `pr_debug` not simply `pr_info` that you comment out before shipping? Give two
reasons, one about the binary and one about the field.

---

## B.6 Code: your first module

Write `lectures/L04/lab/qa_hello.c`. It must:

* Print a greeting from its init function and a farewell from its exit function.
* Take a string parameter `who`, defaulting to `world`, readable but **not** writable via sysfs.
* Take an integer parameter `count`, defaulting to 1, readable **and** writable via sysfs, that
  controls how many times the greeting is printed.
* Carry `MODULE_LICENSE`, `MODULE_AUTHOR`, `MODULE_DESCRIPTION` and `MODULE_VERSION`.
* Use `pr_fmt` so every message is prefixed with the module name, and contain one `pr_debug` that
  says something only useful when switched on.

**Check yourself:** `insmod ./qa_hello.ko who=embedded count=2` prints the greeting twice;
`cat /sys/module/qa_hello/parameters/who` returns `embedded`; writing to that file fails with
`Permission denied`, and writing to `count` succeeds.

---

## B.7 Code: one module using another

Write `qa_export.c`, which exports `qa_answer()` returning 42 with `EXPORT_SYMBOL_GPL`, and
`qa_user.c`, which calls it from its init function and prints the result.

**a)** Load them in the wrong order deliberately. Record the exact error.

**b)** Load them in the right order, then try to `rmmod` them in the wrong order. Record what
happens, and find the holder in `/sys`.

**c)** `qa_export.c` also exports `qa_answer_open()` with plain `EXPORT_SYMBOL`. Write a third
module declaring `MODULE_LICENSE("Proprietary")` that calls **only** that one. Does it build? Does
it load?

**d)** Read `/proc/sys/kernel/tainted` before loading anything, after loading `qa_export`, and
after loading the proprietary one. You get three different numbers. Decompose each into bits, and
name the two taints involved using `include/linux/panic.h`. Then look at the flags in
`/proc/modules` and in `/sys/module/<name>/taint`: which letters appear against which module, and
why does the proprietary module carry two?

**e)** Loading the proprietary module prints one further line that is not about licensing at all:

```text
Disabling lock debugging due to kernel taint
```

Find out what was disabled. Then say what that means for [L07](../../L07/README.md), which is
built entirely on that facility, and state the rule it implies for a development kernel.

**Check yourself:** `make test L=L04` passes, with twelve checks. Note that its check on `rmmod`
deliberately asserts on `lsmod` rather than on `rmmod`'s exit status; B.8 is why.

---

## B.8 Design: a test that cannot fail

The lab's `run.sh` checks that a module in use cannot be unloaded. It does so by attempting the
`rmmod` and then looking at `lsmod`, rather than by checking `rmmod`'s exit status.

**a)** Run `rmmod qa_export` while `qa_user` is loaded, then immediately `echo $?`. What do you
get?

**b)** Given that, what would a test written the obvious way conclude, on a kernel that correctly
refused *and* on one that wrongly allowed it?

**c)** Name the general rule this is an instance of, and give one other example from
[L02](../../L02/appendix/a_shell_and_processes.md#a8-busybox-measured) of the same class of
problem.

---

## B.9 Cross-check: how big is a module

Three measurements of the same module, differing by a factor of five. Predict, measure, reconcile.

**a) The file.** With the lab built, record the size of `qa_hello.ko` on disk.

**b) The content.** Run `size -A` on it, in the container so you get the cross toolchain's version:

```bash
aarch64-linux-gnu-size -A lectures/L04/lab/qa_hello.ko
```

Record the `Total`. Then record the sum of only those sections that will actually be **loaded**:
leave out `.modinfo`, `__versions` and `.comment`, which are metadata the loader reads and does not
keep, and `.symtab` and `.strtab`, of which it keeps only a small copy for `/proc/kallsyms`. The
`.note.*` sections are kept, and are small.

**c) Predict.** From **b)**, write down what you expect the module to occupy in kernel memory once
loaded.

**d) Measure.** Boot, load the module, and read its actual size two ways:

```sh
grep qa_hello /proc/modules
cat /sys/module/qa_hello/coresize
```

**e) Reconcile.** Answer each:

* By what factor does the measured size exceed your prediction?
* The measured number is round. What is it a multiple of, and how many of them?

* Load `qa_export` and compare *its* `coresize` with `qa_hello`'s. They are not the same multiple.
  Before reading further, say what would have to differ between two modules for one to need more
  of these units than the other.
* Now find out why. List the section addresses and sort them:

  ```sh
  for f in /sys/module/qa_hello/sections/.*; do
      echo "$(cat "$f" 2>/dev/null) $(basename "$f")"
  done | sort
  ```

  The addresses fall into distinct groups. How many groups, what is in each, and what is the
  spacing between them? What does that tell you about how a module is laid out in memory?

* `include/linux/module.h` defines `enum mod_mem_type`. How many of its entries are *core* types
  rather than init types, and how does that number relate to what you measured? The allocation
  itself is one line in `kernel/module/main.c`; find it.

* Why is the module laid out this way rather than packed into one contiguous region? The answer is
  about permissions, and it is the same reason the kernel's own `.text` and `.data` are separate.

**f)** `/sys/module/qa_hello/initsize` reads 0 after the module has finished loading, even though
the module plainly has an init function. What happened to it, and what does that have to do with
B.1(d)?

**g)** Someone asks how much memory your driver uses. Give a single number and a sentence, and say
which of your three measurements you chose and why. Then say what your answer would be if the
driver also allocated a 64 KB buffer with `kmalloc` in its init function, and which of the three
numbers would have changed.

---
