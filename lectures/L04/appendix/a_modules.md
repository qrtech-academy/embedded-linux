# Appendix A - Kernel Modules, and the C You Are Allowed to Write
This appendix is the material for L04: what a module is, how it is built and loaded, what the
kernel does with the licence you declare, and what the C environment inside a kernel is actually
like. It ends with the coding style question, which this repository answers differently from the
kernel and owes you an explanation for.

---

## A.1 A module is not a program

The smallest useful module is six lines of substance:

```c
// SPDX-License-Identifier: GPL-2.0-only
#include <linux/init.h>
#include <linux/module.h>

static int __init qa_hello_init(void)
{
    pr_info("qa_hello: loaded\n");
    return 0;
}

static void __exit qa_hello_exit(void)
{
    pr_info("qa_hello: unloaded\n");
}

module_init(qa_hello_init);
module_exit(qa_hello_exit);
MODULE_LICENSE("GPL");
```

There is no `main`, and `qa_hello_init` is not one. The distinction is worth being precise about
because it shapes everything you write afterwards.

`main` runs, and while it runs, your program exists. When it returns, your program is over.
`qa_hello_init` runs **once, at load**, and when it returns the module is **resident and idle**.
Nothing of yours is running. The module is a body of code and data sitting in the kernel's address
space, waiting to be called by something else: a file operation, an interrupt, a timer, a probe.

So the shape of a module is *registration*. `init` announces what you can do and then gets out of
the way; everything after that is callbacks. A module whose `init` function contains a loop is
almost always a module that should have started a thread, and a module whose `init` never returns
has hung the process that called `insmod`.

**`__init` and `__exit` are instructions to the linker.** Code marked `__init` is placed in a
section that is freed once initialisation is done, which is why you see `Freeing unused kernel
memory: 4672K` at the end of boot. `__exit` code can never run when the module is built into the
kernel rather than as a module, because a built-in module can never be removed, so it is thrown
away: at link time on most architectures, and on arm64 at the end of boot, with the `__init` code.

![Five boxes in a row: insmod, init, resident, exit and rmmod. The middle box is highlighted and annotated to say that nothing of yours runs there; the module is code and data occupying kernel memory, waiting to be called by a system call, an interrupt, a timer or another module.](./images/module_lifecycle.png)

---

## A.2 The four macros

| Macro                | Required | What it is for                                                     |
| -------------------- | -------- | ------------------------------------------------------------------ |
| `MODULE_LICENSE`     | **Yes**  | Read by the loader. See A.5. Its absence is an error at build time |
| `MODULE_AUTHOR`      | No       | Convention, and useful when a bug report reaches a maintainer      |
| `MODULE_DESCRIPTION` | No       | Shown by `modinfo`                                                 |
| `MODULE_VERSION`     | No       | Free text; not used for dependency resolution                      |

`MODULE_LICENSE` is the one that is not optional. Omit it and `modpost` fails the build with
`missing MODULE_LICENSE()`, which is a good error, because the alternative is a module that loads
as if it were proprietary: it taints the kernel and cannot see a single GPL-only symbol.

All of them are readable without loading anything:

```bash
$ modinfo qa_hello.ko
filename:       qa_hello.ko
license:        GPL
depends:
vermagic:       6.12.30 SMP preempt mod_unload modversions aarch64
```

That `vermagic` line is A.3.

---

## A.3 Building out of tree, and why a `.ko` is not portable

An out-of-tree module is built by running the *kernel's* build system on your directory:

```bash
make -C /path/to/kernel M=/path/to/your/module modules
```

You are not compiling against kernel headers with your own build system. You are asking kbuild to
compile your file with exactly the flags the kernel was compiled with, which is why the kernel
tree has to be configured and built first, and why there is no shorter way.

The consequence is `vermagic`. Every module records the kernel version, whether that kernel was
SMP, which preemption model it used, and the architecture. The loader checks all of it and refuses
a mismatch. This is a module built against this course's `build/kernel`, loaded into the real-time
kernel L12 builds from the same source:

```text
qa_hello: version magic '6.12.30 SMP preempt mod_unload modversions aarch64' should be
          '6.12.30 SMP preempt_rt mod_unload modversions aarch64'
```

This looks like pedantry and is not. The kernel has no stable internal ABI; a structure that
gained a field between two point releases would be read at the wrong offsets by a module compiled
against the old one, and the failure would be silent corruption rather than a refusal to load.
`vermagic` turns that into an error message.

With `CONFIG_MODVERSIONS`, which this course enables, the check is finer: a checksum is computed
per exported symbol from its argument types, a module is refused if any symbol it uses has changed
shape, and the release number at the front of `vermagic` is no longer compared at all. That is what
lets a distribution ship third-party modules across a stable series.

**This course's Kbuild files build every `.c` in the lab directory as its own module:**

```makefile
obj-m += $(patsubst $(src)/%.c,%.o,$(filter-out %.mod.c,$(wildcard $(src)/*.c)))
```

That is unusual for real kernel code, where the object list is written out explicitly. It is done
here because the repository ships the build file and you write the sources, so a fixed list would
mean editing the build every time you start an exercise. Note `$(src)` rather than a bare
wildcard: kbuild runs the file from the kernel's output directory, and a wildcard over the current
directory silently matches nothing, producing a build that succeeds having compiled zero modules.
The `filter-out` is the other half: kbuild generates a `foo.mod.c` beside every `foo.c` it builds,
and without it the second build tries to make a module of that as well.

---

## A.4 Four commands, and the two people confuse

| Command    | Takes   | Does                                                                  |
| ---------- | ------- | --------------------------------------------------------------------- |
| `insmod`   | A path  | Loads exactly that file. Resolves nothing                             |
| `modprobe` | A name  | Looks the name up in `modules.dep`, loads dependencies first, then it |
| `depmod`   | Nothing | Scans `/lib/modules/$(uname -r)` and writes `modules.dep`             |
| `rmmod`    | A name  | Unloads, if nothing holds a reference                                 |

The demonstration that makes the difference concrete is to load a module with a dependency the
wrong way:

```text
# insmod ./qa_user.ko
qa_user: Unknown symbol qa_answer (err -2)
insmod: can't insert './qa_user.ko': unknown symbol in module or invalid parameter
```

`insmod` did what it was told. It loaded that file, found an unresolved symbol, and gave up. It
never occurred to it to look for a module providing `qa_answer`, because looking things up is
`modprobe`'s job and `modprobe` reads a file that `depmod` generated.

**Unloading is refcounted.** While `qa_user` is loaded, `qa_export` cannot be removed:

```text
# rmmod qa_export
rmmod: remove 'qa_export': Resource temporarily unavailable
# cat /sys/module/qa_export/refcnt
1
# ls /sys/module/qa_export/holders/
qa_user
```

The `holders` directory is the useful one: it names who is holding you, rather than merely how
many. Note also that **BusyBox's `rmmod` returns success even when the removal failed**, which is
why this course's L04 lab checks whether the module is still loaded rather than checking an exit
status. A test that trusts that exit status gets the same answer on a kernel that refused and on a
kernel that did not.

---

## A.5 The licence, and where the check happens

[L01 Appendix B.4](../../L01/appendix/b_licences.md#b4-kernel-modules-and-the-licence-the-linker-enforces)
made the argument. This is the mechanism.

Symbols leave a module in one of two ways:

```c
EXPORT_SYMBOL(qa_answer);       /* any module */
EXPORT_SYMBOL_GPL(qa_answer);   /* GPL-compatible modules only */
```

The accepted values of `MODULE_LICENSE` are a fixed list: `"GPL"`, `"GPL v2"`,
`"GPL and additional rights"`, `"Dual BSD/GPL"`, `"Dual MIT/GPL"`, `"Dual MPL/GPL"`, and
`"Proprietary"`. Anything else is treated as proprietary, including a typo.

Now the part worth doing rather than reading. Take a module that calls a `_GPL` symbol, declare
its licence `"Proprietary"`, and build it. **The build fails**, and the message is unusually good:

```text
ERROR: modpost: GPL-incompatible module qa_proprietary.ko uses GPL-only symbol 'qa_answer'
```

That is `modpost`, a build step that runs after every module is linked and before the `.ko` is
finished. It reads the exports of everything it can see, and the check is three lines in
`scripts/mod/modpost.c`:

```c
if (!mod->is_gpl_compatible && exp->is_gpl_only)
        error("GPL-incompatible module %s.ko uses GPL-only symbol '%s'\n",
              basename, exp->name);
```

**The licence is enforced twice, at two different stages, and it is worth knowing both** because
they fail differently.

**At build time**, as above, when `modpost` can see that the symbol is GPL-only. That is the usual
case: the exports of the built-in kernel come from its `Module.symvers`, and modules built together
see each other. You get a clear message naming the licence, the module and the symbol, and no
`.ko` is produced at all.

**At load time**, as a backstop, and here the failure is much less obvious. The module loader does
not check the licence of a symbol you asked for and refuse it; instead it **hides GPL-only symbols
from the search entirely**. From `kernel/module/main.c`:

```c
static bool find_exported_symbol_in_section(...)
{
        if (!fsa->gplok && syms->license == GPL_ONLY)
                return false;
```

where `gplok` is set from the loading module's own taint:

```c
.gplok = !(mod->taints & (1 << TAINT_PROPRIETARY_MODULE)),
```

So a proprietary module looking up a GPL-only symbol is told the symbol **does not exist**, and
`insmod` reports:

```text
qa_user: Unknown symbol qa_answer (err -2)
```

**Nothing in that message mentions a licence.** It is the same message you get for a genuine
typo or a missing dependency, which makes it one of the more confusing failures in kernel work.
The load-time path is the one you hit when `modpost` could not have known: a module built with
`KBUILD_MODPOST_WARN=1`, which turns an unresolved symbol from an error into a warning, or a module
built against a kernel where the symbol was `EXPORT_SYMBOL` and loaded into one where it has since
become `EXPORT_SYMBOL_GPL`. That second case is real and happens on kernel upgrades.

**Tainting is separate and additive.** Loading any out-of-tree module taints the kernel, even a
GPL one:

```text
qa_hello: loading out-of-tree module taints kernel.
```

`/proc/sys/kernel/tainted` is a bitmask; `Documentation/admin-guide/tainted-kernels.rst` decodes
it. Loading an out-of-tree module sets bit 12 (`TAINT_OOT_MODULE`, value 4096); loading a
proprietary one *also* sets bit 0 (`TAINT_PROPRIETARY_MODULE`), so a proprietary out-of-tree module
leaves `/proc/sys/kernel/tainted` reading **4097** and shows as `(PO)` in `/proc/modules`.

What a taint means is mostly social: an oops from a tainted kernel is one that upstream
maintainers will decline to debug, because they cannot see the code that might have caused it.

**One taint has a concrete technical consequence, and it is worth knowing before L07.** Loading a
proprietary module prints this as well:

```text
qa_prop_ok: module license 'Proprietary' taints kernel.
Disabling lock debugging due to kernel taint
```

The lock validator is switched off, for the rest of that boot, because it cannot reason about
locking in code it cannot see. L07 is built entirely on that validator. So a single proprietary
module loaded anywhere on the system silently removes the tool you would use to find the deadlock
it might be causing, and the rule that follows is to keep development kernels free of proprietary
modules even when the production system has one.

---

## A.6 Parameters, and sysfs you did not write

One line:

```c
static char *who = "world";
module_param(who, charp, 0444);
MODULE_PARM_DESC(who, "who to greet");
```

buys a load-time argument and a sysfs file:

```text
# insmod ./qa_hello.ko who=embedded
# cat /sys/module/qa_hello/parameters/who
embedded
```

Nobody wrote code to create that file. The third argument is its mode, and `0` means do not
create one at all. If the mode is writable, userspace can change the variable while the module is
loaded, which is worth pausing on: that is a shared variable being written by another context, and
everything L07 says about concurrency applies to it.

This is the first appearance of the pattern the whole driver model rests on, which is that you
describe something and the kernel generates the interface. L10 is where it stops looking like a
convenience and starts looking like the architecture.

---

## A.7 Printing

`printk` with a level, or the wrappers, which is what you should actually use:

| Wrapper     | Level | Use for                                           |
| ----------- | ----- | ------------------------------------------------- |
| `pr_emerg`  | 0     | The system is unusable                            |
| `pr_alert`  | 1     | Action must be taken immediately                  |
| `pr_crit`   | 2     | Critical conditions                               |
| `pr_err`    | 3     | An error your driver could not handle             |
| `pr_warn`   | 4     | Something unexpected that you did handle          |
| `pr_notice` | 5     | Normal but significant                            |
| `pr_info`   | 6     | Normal. Most of what you write during development |
| `pr_debug`  | 7     | Compiled out unless dynamic debug is on           |

Three practical notes.

**Set `pr_fmt` once, at the top of the file**, and every message gets a prefix for free:

```c
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
```

**`pr_debug` is not `pr_info` you comment out.** With `CONFIG_DYNAMIC_DEBUG`, which this course
enables, each call site can be switched on at run time:

```bash
echo 'module qa_hello +p' > /sys/kernel/debug/dynamic_debug/control
```

Until then it costs nothing but a few bytes of metadata. That is what makes it reasonable to leave
debug printing in shipped code.

**Prefer `dev_info` once you have a `struct device`**, from L10 onwards. It prints which device the
message came from, which matters the moment there are two of them.

---

## A.8 The C you are allowed to write

The kernel is compiled `-nostdinc`, `-ffreestanding`, against its own headers. There is no C
library. The practical list:

* **No `stdio.h`, `stdlib.h`, `string.h`.** There are kernel equivalents with the same names for
  some things (`memcpy`, `strlen`, `snprintf`) and no equivalent for others.
* **No `malloc`.** `kmalloc` and friends, which take a flag saying what context you are in. L06.
* **No floating point.** The kernel does not save FPU state on entry, so using a `double` corrupts
  whatever userspace task was interrupted. On arm64 the compiler is not allowed to try: the kernel
  is built with `-mgeneral-regs-only`, so a `double` is a compile error. If you genuinely need it
  there is
  `kernel_fpu_begin()`, and needing it is nearly always a sign the calculation belongs in
  userspace. Fixed point is the normal answer.
* **A small, fixed stack.** 16 KB on arm64, for the whole call chain, and nothing grows it;
  interrupts run on a separate per-CPU stack of the same size. This kernel puts an unmapped guard
  page below each stack (`CONFIG_VMAP_STACK`, on by default), so running off the end is a `kernel
  stack overflow` panic rather than a diagnostic you can recover from. Without the guard page, a
  large local array silently corrupts whatever lies below the stack, and the crash comes somewhere
  else entirely. `-Wframe-larger-than=2048` warns about the obvious cases at compile time.
* **No exceptions and no unwinding.** Every function returns an error code, and the caller checks
  it. The convention is zero for success and a negative `-Exxx` for failure, and pointer-returning
  functions use `ERR_PTR`, `IS_ERR` and `PTR_ERR` to pack an error into a pointer.
* **Never trust a userspace pointer.** L05.

The unifying idea is that a mistake in kernel C does not produce a segfault in your program,
because there is no "your program". It produces an oops, and often it produces one somewhere else,
later, in code you did not write.

---

## A.9 Coding style, and why this repository does not use the kernel's

The Linux kernel has a documented coding style, in
`Documentation/process/coding-style.rst`, and it is not a matter of taste: patches are rejected
for violating it, and `scripts/checkpatch.pl` exists to check.

It is tabs, eight columns wide, with braces in K&R placement:

```c
static int qa_fifo_put(struct qa_fifo *fifo, const u8 *data, size_t len)
{
	size_t n = 0;

	if (!fifo || !data)
		return 0;

	while (n < len && fifo->level < fifo->capacity) {
		fifo->data[(fifo->head + fifo->level) % fifo->capacity] = data[n++];
		fifo->level++;
	}

	return n;
}
```

**This repository is formatted differently**, with four spaces and braces on their own line:

```c
static int qa_fifo_put(struct qa_fifo* fifo, const u8* data, size_t len)
{
    size_t n = 0;

    if (!fifo || !data) { return 0; }

    while (n < len && fifo->level < fifo->capacity)
    {
        fifo->data[(fifo->head + fifo->level) % fifo->capacity] = data[n++];
        fifo->level++;
    }

    return n;
}
```

That is the QAcademy house style, shared with every other course in the series and enforced by
[`.clang-format`](../../../.clang-format). The trade is deliberate and it is worth being honest
about both halves of it.

**What it buys** is that a reader moving between the Rust, C++ and Linux courses sees one style,
and that `make format` does the same thing everywhere.

**What it costs** is that none of the code in this repository would be accepted upstream, and that
a reader who goes from here to `drivers/` will find every file looks different. That second cost
is real, which is why this section exists, and why the two versions above are printed side by
side. The difference is entirely mechanical: eight-column tabs against four spaces, brace
placement, and `char *p` against `char* p`.

If you write a driver you intend to submit, run `scripts/checkpatch.pl --file` on it and follow
what it says. Nothing in this course's material depends on the formatting, and everything in it
would be correct in either style.

---
