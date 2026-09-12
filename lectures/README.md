# Lecture Material

The following material is covered in the lectures.

* [L01](./L01/README.md): Embedded Linux, and the licence you ship with it.
* [L02](./L02/README.md): The command line, and the system underneath it.
* [L03](./L03/README.md): The kernel: architecture, source tree, and configuration.
* [L04](./L04/README.md): Kernel modules.
* [L05](./L05/README.md): Character device drivers.
* [L06](./L06/README.md): Memory, MMIO, and resource management.
* [L07](./L07/README.md): Concurrency and locking.
* [L08](./L08/README.md): Interrupts and deferred work.
* [L09](./L09/README.md): Sleeping, waiting, and time.
* [L10](./L10/README.md): The device model and the device tree.
* [L11](./L11/README.md): Kernel frameworks.
* [L12](./L12/README.md): Real-time Linux.

---

## How a lecture is arranged

Each lecture is a directory holding three things.

**`README.md` is the plan for the hour**, not the material. It says what is built, in what order,
what to read before and after, and what you should be able to do when it is over. It is short on
purpose; if it is long enough to read during the lecture, the material has leaked into it.

**`appendix/` carries the material.** An appendix is linked from its lecture's README once it is
written; all twelve lectures are complete. Theory
appendices come first, `a_`, `b_`, and as many letters as the lecture needs. Then one fixed
position: **the exercises appendix is always last.** So a lecture with two theory appendices has
`a_`, `b_`, `c_exercises.md`, and one with three pushes the exercises along by a letter. The rule
is worth knowing because it means you can always find the exercises without reading the directory.

**Worked solutions to the code are deliberately not published.** Every Code exercise, like every
lab, is checkable by running something, and carries a **Check yourself** line saying how; an answer
to read would replace the work. The exercises that are argued or worked on paper, the Recall, Hand
calculation and Design exercises and the by-hand half of each Cross-check, have worked answers in
Appendix A of the [book](../book/README.md). Argue each one before you read its answer, not
instead of it. The lecture that set the exercise is still the place to take a disagreement.

The two papers in [`exam/`](../exam/README.md) do carry model answers, because an exam is marked by
somebody other than the candidate. They answer the code questions as marking checklists rather than
as listings, so they are not solutions to these labs by another route.

**The figures are generated.** An appendix that carries one embeds it from
`appendix/images/`, and the source is in [`diagrams/`](../diagrams/README.md). Charts are drawn
from the numbers the appendix itself publishes, so a figure and the table beside it cannot
disagree.

**`lab/` is the workspace.** It holds what the course provides, which is the Kbuild file, the
KUnit suite where the lecture has one, and `run.sh`, the script the target runs to test what you
wrote. It does not hold the driver. That is the point of it.

---

## Exercises

Eight to ten per lecture, each labelled with its kind:

* **Recall.** Say it back, in your own words, with nothing in front of you.
* **Hand calculation.** Work out a number on paper.
* **Design.** Choose between two mechanisms and defend the choice.
* **Code.** Write something and run it.
* **Cross-check.** Exactly one per lecture, always last.

The Cross-check is the signature exercise and the reason the other four exist. You compute a
number by hand, you run your own code on the same problem, and then you reconcile the two. They
will rarely agree exactly, and reconciling them is the point: "my two answers differ by eight
percent" is not a failure of the exercise, it is the exercise. Each one names the artefacts to
measure and the questions to ask about the gap, so that you can tell a discrepancy you have
explained from one you have merely noticed.

---

## Why there is no C++ test framework here

Every other QAcademy course checks your work with the
[QAcademy Test framework](https://github.com/qrtech-academy/test-framework), a C++17 library the
course pulls in as a submodule. This one does not, and cannot: the code you write is a kernel
module, and a kernel module runs in a kernel. There is no `main`, no libc, and nothing on the host
that can call your `read()`.

So the harness is the machine. `make test` builds your module, drops it into an initramfs with
the lecture's `run.sh`, boots `qemu-system-aarch64`, and reads the serial console. Two things are
tested that way:

* **KUnit**, for the parts that are pure logic. A ring buffer's wrap-around and a register field's
  decoding are functions with no hardware in them, and KUnit runs them inside the kernel with a
  real test framework around them. It is also what mainline uses, which makes it worth meeting.
* **The on-target script**, for everything else. Loading the module, reading `/dev`, checking
  `dmesg`, counting interrupts in `/proc/interrupts`; all the things that are only true of a
  driver in a running kernel.

Both report through the same three markers on the console, and `make test` distinguishes a test
that failed from a kernel that panicked before the test began. That distinction matters more here
than it does in userspace, because in kernel space the second one is a normal Tuesday.

---
