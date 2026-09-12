# L03 - The Kernel: Architecture, Source Tree, and Configuration

## Agenda
* The kernel as a program: one address space, no libc, and the only public interface it has.
* The subsystem map, and where in the tree each of them lives.
* Mainline, stable, long-term stable, and the vendor tree your SoC actually shipped with.
* Kconfig: what a symbol is, what `select` does that `depends on` does not, and `=y` against `=m`.
* Kbuild: `ARCH`, `CROSS_COMPILE`, `O=`, and what `Image` is that `vmlinux` is not.
* Live: turn one config option off and measure what it was worth.

---

## Lecture plan
Worked in this order:

1. **What kind of program the kernel is.** It has no `main`, it never returns, it runs in one
   address space shared by everything in it, and a null pointer dereference in any part of it
   takes down all of it. Contrast with a process, which the reader already understands, and be
   explicit that "monolithic" is a statement about the address space and not about modularity.
2. **The one public interface.** Everything userspace can ask of the kernel goes through the
   system call table, and that interface is *stable forever*: a binary from 1998 still runs. Then
   the sentence people find surprising, which is that the *internal* API has no such guarantee and
   changes every release. Those two facts together are the whole reason out-of-tree drivers are
   painful and in-tree ones are not.
3. **The tree, in one pass.** `arch/`, `drivers/`, `fs/`, `kernel/`, `mm/`, `net/`, `include/`,
   `Documentation/`. Then find one real driver and read its first thirty lines together; the
   shape of `drivers/rtc/rtc-digicolor.c` is the shape of what the reader writes in L06 to L11.
4. **Versions.** Mainline, `-stable`, LTS, and the vendor fork that is three years behind with
   four thousand patches. Say what the practical consequence is: the question "can I take this
   upstream fix" is a question about which of those trees you are on.
5. **Kconfig.** A symbol, a type, a prompt, and a dependency. Then the two that get confused:
   `depends on` hides a symbol until its dependency is met, and `select` turns another symbol on
   whether or not its own dependencies are met, which is why `select` is discouraged and why a
   `.config` can end up with an option nobody chose.
6. **`=y` against `=m`.** Built in against loadable. The decision is not free and the tradeoff is
   concrete: a module can be left off the image, updated separately and unloaded, but it cannot be
   used before the root filesystem is mounted, which is why the driver for the disk holding your
   modules cannot itself be a module.
7. **Live: measure a config option.** Put one line in `kernel/local.config`, rebuild, and compare
   the `Image`. The option to use is `CONFIG_IKCONFIG`, because its contribution is a blob whose
   size you can measure beforehand, so the prediction is arithmetic rather than a guess. Predict
   first: **34,138 bytes**, from `size -A kernel/configs.o`. Then measure, and get **65,536**.
   Do not resolve that in the room; it is the Cross-check, and the gap is the whole of it.

**If the hour runs short, compress step 4.** Version policy reads well on paper. Step 5 does not,
because the `select` behaviour only lands when you watch a symbol you did not choose appear in
the diff.

---

## Before the lecture
* Have `make kernel` completed once. It takes around twenty minutes and the lecture assumes a
  built tree to poke at.
* Read [Appendix A](./appendix/a_the_kernel_and_its_tree.md), which is the kernel's architecture
  and its source tree.

## After the lecture
* Read [Appendix B](./appendix/b_kconfig_and_kbuild.md), which is Kconfig and Kbuild in detail.
* Work through [Appendix C](./appendix/c_exercises.md), ending with the **Cross-check**: predict
  what one config option costs by measuring the object it contributes, then remove it, rebuild,
  and measure three different artefacts. They give three different answers and all three are
  correct.
* Finish the lab in [`lab/`](./lab), and make `make test L=L03` report **PASSED**.

---

## What you should be able to do afterwards
* Say what "monolithic kernel" claims, and what it does not claim.
* Explain why the syscall interface is stable and the internal API is not, and what follows for a
  driver you maintain out of tree.
* Navigate to a named subsystem in the source tree without searching.
* Read a Kconfig entry and say under what circumstances the option will and will not appear.
* Say what `select` does that `depends on` does not, and why that can produce a broken `.config`.
* Choose `=y` or `=m` for a given driver and defend the choice.
* Cross-build a kernel with a config fragment, and say where each of `Image`, `vmlinux` and the
  modules ends up.
* Measure what a config option costs, in image bytes and in modules.

---

## Questions to test yourself
* Why can the driver for the device holding your root filesystem not be a module?
* Your `.config` contains an option you never selected and whose `depends on` line is not
  satisfied. How did it get there?
* What is the difference between `vmlinux` and `Image`, and which one does the bootloader load?
* `make defconfig` for arm64 produces a configuration for how many machines? What does that tell
  you about how much of your build you are going to throw away?
* You backport a fix from mainline into a vendor tree that is three years old and it does not
  apply. What are your options, in order of increasing cost?
* Why does the kernel build its own headers rather than using the ones in `/usr/include`?
* You remove a config option contributing 34 KB and the `Image` shrinks by 64 KB. Where did the
  other 30 KB come from, and would removing a second 34 KB option shrink it by another 64 KB?

---

## Reference
* [Appendix A](./appendix/a_the_kernel_and_its_tree.md) is the architecture and the tree;
  [Appendix B](./appendix/b_kconfig_and_kbuild.md) is Kconfig and Kbuild.
* [Appendix C](./appendix/c_exercises.md) contains the exercises.
* [`kernel/trim.config`](../../kernel/trim.config) is this course's own answer to step 7, with a
  comment on every line saying what it removed and why. It is worth reading before the lab.
* [Bootlin's source browser](https://elixir.bootlin.com/linux/latest/source) is how to read the
  tree without cloning it.

---

## Next lecture
* The smallest thing you can write for a kernel, and how to load it into a running one.
* `module_init`, and what "init" means for code with no `main`.
* Why the kernel refuses to load some modules, and what a licence has to do with it.
* The C you are allowed to write up here, which is less than you are used to.

L03 was about the kernel somebody else wrote. L04 is the first one where you add to it.

---
