# Appendix B - Open Source Licences, and What You Have to Publish
This appendix is about one question. It is the only question a licence actually answers, and
almost every argument about open source licensing is an argument that has lost sight of it:

> **If I give somebody this binary, what am I obliged to give them along with it?**

Not "is this free software". Not "can I use this commercially"; you almost always can. The
question is what leaves your building when the product does.

**This is not legal advice, and the author is not a lawyer.** What it is is the engineering model
you need to have in your head so that you know which decisions need a lawyer and which do not.
Getting this wrong is expensive, and the expensive cases are almost always cases where nobody
asked the question at all until a customer did.

---

## B.1 Two families

Every licence you will meet on an embedded product falls into one of two families, distinguished
by what happens when you combine the code with your own.

**Permissive** licences let you do essentially anything, including shipping binaries with no
source, provided you carry the copyright notice along. MIT, BSD-2-Clause, BSD-3-Clause and
Apache-2.0 are the ones you will actually see.

**Copyleft** licences let you do essentially anything, provided that whoever receives the binary
can also receive the source, under the same licence. GPL-2.0, GPL-3.0, LGPL-2.1 and MPL-2.0 are
the ones you will see.

| Licence      | Family                  | If you ship a binary containing it, you must publish                              |
| ------------ | ----------------------- | --------------------------------------------------------------------------------- |
| MIT          | Permissive              | Nothing. Keep the notice in your documentation                                    |
| BSD-3-Clause | Permissive              | Nothing, plus you may not use the authors' names to endorse                       |
| Apache-2.0   | Permissive              | Nothing, plus a NOTICE file, plus a patent grant you give                         |
| MPL-2.0      | Weak copyleft (file)    | The source of the MPL files you changed                                           |
| LGPL-2.1     | Weak copyleft (library) | The library's source, and the means to relink your binary against a modified copy |
| GPL-2.0      | Strong copyleft         | The complete corresponding source of the whole work                               |
| GPL-3.0      | Strong copyleft         | The above, plus installation information for consumer devices                     |

The two rows worth reading twice are LGPL and GPL-3.0, because both carry an obligation that is
not about source code at all, and both are where embedded products get caught.

---

## B.2 The word that does the work: derivative

Copyleft only reaches code that is part of the same work. So everything depends on where one work
ends and the next begins, and that boundary is not defined by the licence in terms an engineer can
apply mechanically. What exists instead is a set of positions, some of which are near-universally
accepted and some of which are contested.

Broadly accepted:

* **Static linking creates one work.** If your proprietary code is linked into the same binary as
  GPL code, the result is a derivative work of both.
* **Separate processes communicating over a pipe or a socket do not.** Your closed daemon talking
  to a GPL program over a socket is two works.
* **Mere aggregation does not.** Two unrelated programs on the same filesystem image are not one
  work because they share a partition.

Contested, and where you need a lawyer rather than an opinion:

* **Dynamic linking.** The Free Software Foundation holds that linking against a GPL library
  creates a derivative work even at run time. Others disagree. This is why the LGPL exists: it
  settles the question for libraries that want to be linkable by proprietary code.
* **Kernel modules.** See B.4, which is the case this course actually cares about.

---

## B.3 The syscall exception, and why your application is yours

The Linux kernel is GPL-2.0-only. Every program on a Linux system makes system calls into it. If
that made every program a derivative work of the kernel, no proprietary software could run on
Linux at all, and Linux would have no commercial users.

Linus Torvalds added a note to the top of the kernel's `COPYING` file that says so explicitly. The
note now lives in `LICENSES/exceptions/Linux-syscall-note`, which `COPYING` names as the kernel's
explicit syscall exception:

> NOTE! This copyright does *not* cover user programs that use kernel services by normal system
> calls - this is merely considered normal use of the kernel, and does *not* fall under the
> heading of "derived work".

That paragraph is the legal foundation of embedded Linux as a commercial platform, and it is worth
knowing that it is a clarification granted by the copyright holder rather than something that falls
out of the GPL itself. **The boundary it draws is the system call boundary.** Your application
talks to the kernel through `read`, `write`, `ioctl` and the rest, and that is normal use.

The practical consequence is the one your colleague gets wrong. "We ship Linux, so all our code
must be open source" is false: your application, running as its own process and making system
calls, is yours, and you may ship it as a binary with no source at all. What *is* true is the
narrower claim, that the kernel you ship, and any modifications you made to it, must be published.

---

## B.4 Kernel modules, and the licence the linker enforces

A kernel module is not a separate process. It is compiled against the kernel's own headers, linked
into the kernel's address space, and calls kernel functions directly. Under every version of the
derivative-work argument, that is a much harder position to defend than an application making
system calls, and the widely held view among kernel developers is that a module is a derivative
work of the kernel.

The kernel does not leave this as an argument. It enforces a version of it mechanically, and this
is the part that matters to you as a driver author.

**Every module declares its licence in its own binary:**

```c
MODULE_LICENSE("GPL");
```

The string is not documentation. It is read by the module loader, and the set of accepted values
is fixed: `"GPL"`, `"GPL v2"`, `"GPL and additional rights"`, `"Dual BSD/GPL"`, `"Dual MIT/GPL"`,
`"Dual MPL/GPL"`, and `"Proprietary"`. Anything else counts as proprietary. A module with no
`MODULE_LICENSE` at all is not built: `modpost` fails with `missing MODULE_LICENSE()`.

**Two things follow when a module is not GPL-compatible.**

First, the kernel is **tainted**. `/proc/sys/kernel/tainted` gains a bit, every subsequent oops
carries a taint flag, and kernel developers will decline to debug it. That is a social mechanism
rather than a legal one, but it is a real cost: a bug report from a tainted kernel is a bug report
nobody upstream will look at.

Second, and concretely, **a large part of the kernel's internal API becomes unavailable.** Symbols
are exported in one of two ways:

```c
EXPORT_SYMBOL(foo);      /* any module may use this */
EXPORT_SYMBOL_GPL(bar);  /* only GPL-compatible modules may use this */
```

A module declaring a proprietary licence and calling `bar()` is refused, and it is refused **in two
different places depending on what the build could see.**

Usually the build fails, at the `modpost` step that runs after linking each module:

```text
ERROR: modpost: GPL-incompatible module mine.ko uses GPL-only symbol 'bar'
```

That is the good case: the message names the licence, the module and the symbol, and no `.ko` is
produced. It happens whenever `modpost` can see that `bar` is GPL-only, which is nearly always,
because the built-in kernel's exports are listed in its `Module.symvers`.

When `modpost` could not have known, the module loader refuses instead, and its message is much
worse. It does not report a licence problem; it **hides GPL-only symbols from a proprietary
module's symbol lookup entirely**, so what you see is:

```text
mine: Unknown symbol bar (err -2)
```

which is indistinguishable from a typo or a missing dependency. That path is what you hit after a
kernel upgrade in which a symbol you used changed from `EXPORT_SYMBOL` to `EXPORT_SYMBOL_GPL`;
your module was built when it was legal and is loaded when it is not. L04 causes both on purpose.

**Which symbols are `_GPL` is a live decision, not a historical accident.** Maintainers choose,
and over the years the boundary has moved steadily toward `_GPL` for anything that looks like a
core internal interface. If your business model depends on a proprietary module, it depends on a
set of exported symbols that other people control and may narrow in the next release.

---

## B.5 What "complete corresponding source" means in practice

GPL-2.0 section 3 requires you to give the recipient "the complete corresponding machine-readable
source code", defined as "all the source code for all modules it contains, plus any associated
interface definition files, plus the scripts used to control compilation and installation of the
executable".

Read the last clause again, because it is the one people fail. **The build scripts are part of the
obligation.** A tarball of kernel sources with no `.config` in it does not satisfy this: the
recipient cannot produce your binary from it. Neither does a source tree that only builds with an
internal toolchain nobody outside your company has.

The practical checklist for a product that ships a GPL kernel is:

* The kernel source, at the exact version you shipped, including every patch you applied.
* The `.config` you built it with.
* The device tree sources.
* Enough instructions to build it: which toolchain, which commands.
* The same for U-Boot, BusyBox, and every other GPL component in the image.

You may either ship this alongside the product, or include a **written offer** valid for three
years to supply it on request. The written offer is what most products use, and it is the thing
that has to survive in your build system for three years after the last unit ships. That is a
release-engineering requirement that comes directly out of a licence, and it is the single most
common thing to discover too late.

**GPL-3.0 adds installation information.** For a consumer device, you must also provide whatever
is needed to actually install a modified version and have it run: keys, signing tools, flashing
instructions. This is why a great many embedded products deliberately stay on GPL-2.0-only
components, and why the kernel's own GPL-2.0-only status without the "or later" clause is a
decision rather than an oversight.

---

## B.6 SPDX, and how you find out what you have

You cannot answer the question in the opening of this appendix without an inventory. Reading every
file is not possible; almost every project now says so in a machine-readable way instead.

An **SPDX identifier** is a single comment line at the top of a file:

```c
// SPDX-License-Identifier: GPL-2.0-only
```

The kernel adopted these in 2017 and nearly every file now carries one. They are exact, they are
greppable, and a file that has one needs no further interpretation:

```bash
grep -rh 'SPDX-License-Identifier:' drivers/ | sort | uniq -c | sort -rn
```

Three cautions, and they are the whole of what makes this a skill rather than a `grep`.

* **A file with no SPDX tag is not unlicensed.** It is a file whose licence has to be found some
  other way: a `LICENSE` file in its directory, a header comment, or the project's top-level
  terms. These are the interesting files in any audit, and there are always some.
* **`GPL-2.0-only` and `GPL-2.0-or-later` are different licences.** The second lets a downstream
  recipient move to GPL-3.0 and its installation-information obligation. The kernel is
  `GPL-2.0-only`. Some of the components around it are not.
* **A build system is not an inventory.** What matters is what ended up in the image, and a
  package can be present in the source tree and absent from the shipped filesystem, or the
  reverse.

The exercise in [Appendix C](./c_exercises.md) is to build that inventory for a real tree and say
what you would have to publish. The Cross-check is to do a subdirectory by hand first, and find out
where your script and your eyes disagree.

---

## B.7 A worked example

A product ships:

| Component                | Licence          | Modified        |
| ------------------------ | ---------------- | --------------- |
| U-Boot                   | GPL-2.0-or-later | Yes, board port |
| Linux kernel             | GPL-2.0-only     | Yes, one driver |
| Your out-of-tree driver  | Yours to choose  | n/a             |
| BusyBox                  | GPL-2.0-only     | No              |
| An MQTT client library   | Apache-2.0       | No              |
| Your control application | Proprietary      | n/a             |

What must you publish?

* **U-Boot**, complete corresponding source including your board port and your config.
* **The kernel**, complete corresponding source including your driver, your `.config` and your
  device tree. Note that the driver is in the kernel tree and is therefore part of the work.
* **BusyBox**, source at the version shipped. Unmodified does not mean exempt; the obligation is
  to the recipient of the binary, not conditional on your having changed it.
* **The MQTT library**: nothing, but carry its NOTICE file and its licence text in your
  documentation.
* **Your control application**: nothing. It is a separate process making system calls, and B.3 is
  why.

And the one that is a decision rather than an obligation: **your out-of-tree driver**. If you keep
it out of tree and declare it proprietary, you take on the taint, you lose every `EXPORT_SYMBOL_GPL`
symbol, and you own the maintenance of it against a kernel API that has no stable interface and
changes every release. Most companies that try this eventually stop, and the reason is usually the
maintenance cost rather than the licence.

---
