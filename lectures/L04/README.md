# L04 - Kernel Modules

## Agenda
* `module_init` and `module_exit`: code with no `main`, that runs once and then waits.
* Building out of tree, and what `M=` actually does.
* `insmod`, `rmmod`, `modprobe`, `depmod`, and why the first and third are not the same command.
* Module parameters, and the sysfs directory you get without asking.
* `EXPORT_SYMBOL` against `EXPORT_SYMBOL_GPL`, and a licence check that happens at load time.
* `printk`, the log levels, and `pr_debug` that costs nothing until you turn it on.
* The C environment: no libc, no floating point, and a stack you can overflow.
* Live: a module that loads, then a second one that uses a symbol from the first.

---

## Lecture plan
Worked in this order:

1. **The smallest module.** Six lines: two functions, two macros, a licence. Build it, load it,
   watch `dmesg`. Then the observation that matters: `module_init` is not a `main`. It runs, it
   returns, and the module is then *resident and idle*, waiting to be called by something else.
   Everything you write from here on is callbacks.
2. **What the build did.** `make -C <kernel> M=<dir> modules`, and the point that you are running
   the *kernel's* build system on your directory, not your build system against kernel headers.
   That is why the kernel tree has to be configured and built first, and why a `.ko` is tied to
   the kernel that built it.
3. **Four commands, two of which are the same.** `insmod` takes a path and loads exactly that.
   `modprobe` takes a name, looks it up in `modules.dep`, and loads the dependencies first.
   `depmod` is what produces that file. `rmmod` removes. The demonstration is to load a module
   with a dependency using `insmod` and watch it fail with `Unknown symbol`.
4. **Parameters and sysfs.** One `module_param` line, and then `/sys/module/<name>/parameters/`
   exists with a file in it. Nobody wrote that code. This is the first appearance of the pattern
   the whole driver model is built on, and L10 is where it stops looking like magic.
5. **The licence, enforced twice.** `EXPORT_SYMBOL` against `EXPORT_SYMBOL_GPL`, and then do it:
   declare a module `MODULE_LICENSE("Proprietary")` and have it call a `_GPL` symbol. **The build
   fails**, from `modpost`, with a message naming the licence, the module and the symbol. Then say
   what happens when `modpost` could not have known, because that is the failure people actually
   lose time to: the loader does not refuse the symbol, it *hides* it, so `insmod` reports
   `Unknown symbol` with no mention of a licence anywhere. Two checks, two stages, two very
   different messages. This is
   [L01 Appendix B.4](../L01/appendix/b_licences.md#b4-kernel-modules-and-the-licence-the-linker-enforces)
   made concrete.
6. **`printk` and friends.** The eight levels, `pr_info` and `pr_err`, and `pr_debug` which
   compiles to nothing until dynamic debug turns it on at run time. Then `dev_info`, which is what
   you will actually use from L10 onwards, because it prints which device it came from.
7. **The C you are allowed to write.** No `stdio.h`, no `malloc`, no `double`, and a stack of
   16 KB or less that nothing grows for you. Say what happens when you overflow it, which is not
   a segfault.
8. **Live coding.** `qa_hello` with a parameter; then `qa_export` and `qa_user`, and the load
   order that fails.

**If the hour runs short, compress step 7**, which reads perfectly well in the appendix. Do not
compress step 5; it is the only place in the course where a licence becomes an error message.

---

## Before the lecture
* Read [Appendix A](./appendix/a_modules.md), which is modules, the build, and the kernel's C
  environment.
* Have `make kernel` completed. An out-of-tree module cannot be built without it.

## After the lecture
* Work through [Appendix B](./appendix/b_exercises.md), ending with the **Cross-check**: predict
  the module's memory footprint from `size -A` on the `.ko`, then read `/proc/modules` after
  loading it. The two differ by a factor of five, and finding out why means reading how a module
  is laid out in memory.
* Write `qa_hello.c`, `qa_export.c` and `qa_user.c` in [`lab/`](./lab), and make
  `make test L=L04` report **PASSED**. The lab's `run.sh` checks the load ordering, the holders
  directory, and that the kernel refuses to unload a module that is in use.

---

## What you should be able to do afterwards
* Write, build and load an out-of-tree module, and say what each of the four macros in it is for.
* Explain why `module_init` returning is not the module finishing.
* Say what `insmod` does that `modprobe` does not, and produce the failure that distinguishes them.
* Add a module parameter and read it back from sysfs without writing any sysfs code.
* Predict whether a given module will load, from its `MODULE_LICENSE` and the symbols it uses.
* Choose a `printk` level, and say why `pr_debug` is not simply `pr_info` you comment out.
* List three things you may not do in kernel C that you do without thinking in userspace C.

---

## Questions to test yourself
* What is resident in memory after `module_init` returns, and what is running?
* Why is a `.ko` built against one kernel usually refused by another?
* A proprietary module using a GPL-only symbol can fail at two different points, with two very
  different messages. Name both, and say which one you get when the symbol changed from
  `EXPORT_SYMBOL` to `EXPORT_SYMBOL_GPL` after your module was built.
* You add `module_param(depth, int, 0644)`. Who wrote the code that makes
  `/sys/module/yours/parameters/depth` appear?
* Why is there no `float` in the kernel? What would have to happen for there to be one?
* `rmmod` refuses with "Module is in use". What is holding it, and where can you see that?

---

## Reference
* [Appendix A](./appendix/a_modules.md) is the material;
  [Appendix B](./appendix/b_exercises.md) contains the exercises.
* [L01 Appendix B.4](../L01/appendix/b_licences.md#b4-kernel-modules-and-the-licence-the-linker-enforces)
  is the licensing argument this lecture makes concrete.
* [`lab/Kbuild`](./lab/Kbuild) explains why it builds every `.c` in the directory rather than a
  fixed list.

---

## Next lecture
* The oldest interface a driver can offer userspace, and the one you will write first.
* `open`, `read`, `write`, and what each of them has to return.
* Why dereferencing a pointer from userspace is a bug and not merely bad style.
* A ring buffer, and a KUnit suite that knows one thing your `read()` does not.

---
