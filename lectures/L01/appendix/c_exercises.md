# Appendix C - Exercises
Eight, ending with the Cross-check. Do them in order; the last one needs the script from C.6.

Several of these have a plausible wrong answer that is worth walking into before you find it.
Where an exercise can be checked mechanically, a **Check yourself** line says how.

Everything here runs against the trees `make kernel` and `make rootfs` already downloaded, under
`build/`. Nothing needs the network.

---

## C.1 Recall: the four pieces

Without looking at [Appendix A](./a_the_four_pieces.md), name the four pieces of an embedded Linux
system and say in one sentence what each does.

Then, for each of the following, say which piece it belongs to:

**a)** `/lib/modules/6.12.30/kernel/lib/kunit/kunit.ko`

**b)** `u-boot.img`

**c)** `aarch64-linux-gnu-gcc`

**d)** `/init`

**e)** The `.dtb` handed to the kernel at boot

**f)** `/bin/busybox`

---

## C.2 Recall: why there are two bootloaders

A colleague looking at a board's flash layout asks why there is both an `SPL` and a `u-boot.img`,
and suggests deleting the first to save space.

**a)** Explain in two sentences why the SPL exists.

**b)** What specifically would fail if you deleted it, and at what point in the boot?

**c)** Name one thing about a board that makes bricking it recoverable, and one that does not.

---

## C.3 Hand calculation: what the toolchain triplet promises

**a)** Break `aarch64-linux-gnu` into its parts and say what each names.

**b)** You are handed a binary and told only that it was built with `arm-none-eabi-gcc`. What can
you say about the system it is intended to run on, and in particular, can it run on Linux? Justify
it from the triplet alone.

**c)** A program builds against `aarch64-linux-gnu-gcc` on a machine whose sysroot has glibc 2.36.
It is deployed to a target whose root filesystem has glibc 2.31. Predict what happens, and say
whether the failure is at build time or at run time.

**d)** A colleague fixes a "missing header" error in a cross build by running
`sudo apt install libfoo-dev`. Explain why this does not work, and what would.

---

## C.4 Design: what leaves the building

You ship a product containing exactly these things:

| Component                  | Licence          | Modified by you         |
| -------------------------- | ---------------- | ----------------------- |
| U-Boot                     | GPL-2.0-or-later | Yes, a board port       |
| Linux kernel               | GPL-2.0-only     | Yes, one driver in-tree |
| BusyBox                    | GPL-2.0-only     | No                      |
| `libcurl`                  | MIT-like (curl)  | No                      |
| A logging daemon you wrote | Proprietary      | n/a                     |
| A kernel module you wrote  | You choose       | n/a                     |

A customer sends a written request for the source code.

**a)** Go through the table and say, for each row, what you must publish.

**b)** BusyBox is unmodified. Does that change the answer? Say why.

**c)** Your logging daemon links dynamically against `libcurl` and talks to your kernel module
through `ioctl`. Does either of those relationships oblige you to publish the daemon?

**d)** What must you keep, and for how long, in order to be able to answer this request at all?

---

## C.5 Design: where the boundary falls

For each pair below, say whether the two things are one work or two, and name the argument that
decides it. Where the answer is genuinely contested, say so rather than picking.

**a)** A proprietary application and the kernel, communicating by system calls.

**b)** A proprietary program statically linked against a GPL-2.0 library.

**c)** A proprietary program dynamically linked against an LGPL-2.1 library.

**d)** A proprietary program dynamically linked against a GPL-2.0 library.

**e)** A proprietary kernel module and the kernel.

**f)** A GPL program and a proprietary program on the same filesystem image, which never
communicate.

---

## C.6 Code: an SPDX inventory

Write a script, `lectures/L01/lab/spdx-audit.sh`, that takes a directory and reports what licences
the files under it are under.

It should:

* **a)** Walk every `*.c` and `*.h` file under the directory it is given.
* **b)** For each, extract the SPDX identifier if there is one. The tag looks like
  `SPDX-License-Identifier: GPL-2.0-only` and appears in a comment in roughly the first few lines.
* **c)** Print a count per identifier, most common first.
* **d)** Print, separately and by name, every file that has no identifier at all. These are the
  interesting ones and they must not be silently folded into a total.
* **e)** Print the total number of files examined, so that the counts can be checked against it.

Two requirements that are easy to miss and are the point of the exercise:

* **Normalise the deprecated spellings.** SPDX renamed several identifiers; `GPL-2.0` is the old
  spelling of `GPL-2.0-only`, and `GPL-2.0+` is the old spelling of `GPL-2.0-or-later`. Both
  spellings are in the kernel tree, in quantity. A report that lists them separately is reporting
  two licences where there is one. Your script must report the current spelling and say how many
  of each it merged.
* **Do not stop at the first match in the file.** Some files carry more than one SPDX tag. Take
  the first one, but know that you have made that choice.

**Check yourself:** run it on `build/linux-6.12.30/drivers/rtc`, which has 184 `.c` and `.h` files
at its top level. Your total must be 184.

---

## C.7 Code: measure the machine you built

Answer each of these with a command, run on the target after `make boot`, or on the host against
`build/`. Write down the command as well as the number.

**a)** What kernel version is running, what compiler built it, and when?

**b)** What did the bootloader pass to the kernel on its command line?

**c)** How large is the kernel image, and how large is the compressed initramfs?

**d)** How many modules did the kernel build, and how many are installed on the target?

**e)** How much memory does the target have, and how much of it is free once it has booted?

**f)** What is the physical address of the `qa-dev` registers, according to `/proc/iomem`?

For **f)**, note that nothing has claimed the region yet, because no driver for the device exists
until L06. Say what you can see and what you cannot.

---

## C.8 Cross-check: an audit by hand against an audit by script

This is the exercise the other seven exist for. You will compute a set of numbers by hand, run your
own code on the same problem, and reconcile the two. They will not agree, and the disagreement is
the lesson.

**a)** By hand, with no scripting, classify the licences of these ten files in
`build/linux-6.12.30/drivers/rtc`:

```text
rtc-ds1307.c   rtc-pl031.c    rtc-starfire.c   rtc-rs5c313.c   rtc-cmos.c
rtc-m41t80.c   rtc-pcf8563.c  rtc-abx80x.c     rtc-max77686.c  rtc-s35390a.c
```

For each, write down the identifier and where you found it. Do not run your script yet.

**b)** Now predict, from that sample of ten, what the breakdown over the whole of
`drivers/rtc` will be. Write down a number of distinct licences and a rough proportion for each.

**c)** Run your script from C.6 over the whole directory. Record the output.

**d)** Reconcile. Specifically, answer these:

* How many *distinct SPDX strings* did your script find, and how many *distinct licences* is that
  actually? What is the relationship between the two numbers?
* Your script reports some number of untagged files. Find each one and determine its licence by
  another route. Say what that route was, and whether it was the same route for both.
* Did your ten-file sample predict the whole? If your proportions were off, say which direction
  and why a sample drawn from files you recognised the names of would be biased.

**e)** A colleague runs your script, sees no `Proprietary` in the output, and concludes that the
kernel tree contains nothing proprietary. Say what is wrong with that inference. There are at least
two separate problems with it.

---
