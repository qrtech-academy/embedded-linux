# L05 - Character Device Drivers

## Agenda
* Major and minor numbers, and what each of them selects.
* `struct file_operations`, and the fact that a driver is a table of callbacks and nothing else.
* `open`, `release`, `read`, `write`: what each returns, and what userspace does with it.
* `copy_to_user`, and why dereferencing a userspace pointer is a bug rather than a shortcut.
* Which `-Exxx` to return, and why the choice is part of the interface.
* The misc device, and when the shortcut is the right answer.
* `ioctl`, and why adding a new one is usually the wrong answer.
* Live: a ring buffer, and the KUnit suite that tests it.

---

## Lecture plan
Worked in this order:

1. **What a device node is.** `ls -l /dev/null` and the two numbers where the size should be.
   Major selects the driver; minor selects which of that driver's devices. Then
   `cat /proc/devices` to see the ones already taken. This is the payoff for
   [L02](../L02/README.md), where these numbers first appeared with nothing attached to them.
2. **A driver is a table.** `struct file_operations`, and the fact that every entry is optional.
   Register the table against a major number and the kernel routes `read()` on any node with that
   major into your function. That is the whole mechanism.
3. **The one that has to be right.** `read()` is handed a pointer, and that pointer is a userspace
   address. Dereferencing it directly is wrong in three separate ways: the page may not be mapped,
   the address may belong to a different process by the time you touch it, and it may point at
   kernel memory and be an invitation to read it. `copy_to_user` is what checks all three.
   **Write it wrong first, live, and read the oops.** It is the single most useful two minutes in
   the lecture.
4. **Return values are the interface.** `read()` returns a count, and a short count is not an
   error. Zero means end of file, and if you return zero when you merely have nothing right now,
   every reader of your device sees EOF and stops. That bug is silent, common, and the reason
   L09 exists.
5. **The shortcut.** `misc_register`, which allocates a minor under a shared major and creates the
   node for you, in about six lines instead of forty. Say plainly that most small drivers should
   use it, and that the long way is taught first because the short way hides exactly the parts
   worth understanding.
6. **`ioctl`, briefly and with a warning.** The encoding, the direction bits, and then the
   argument: an `ioctl` you invent is an ABI you maintain forever, and there is usually a
   subsystem that already defines the operation you want. L11 is that argument in full.
7. **Live coding.** The ring buffer specified in [`lab/qa_fifo.h`](./lab/qa_fifo.h). Write
   `qa_fifo_put` and `qa_fifo_get`, run the shipped KUnit suite, and watch which case fails first.

Two predictions worth making. Before step 3, ask what happens if you just use `memcpy`. Before
step 7, ask which of the ten KUnit cases a first attempt usually fails; the answer is
`qa_fifo_wraps`, and it is the eighth of ten, which means seven passing tests tell you nothing.

**If the hour runs short, compress step 6.** Do not compress step 3 or step 4.

---

## Before the lecture
* Read [Appendix A](./appendix/a_character_devices.md), which is the character device interface.
* Read [`lab/qa_fifo.h`](./lab/qa_fifo.h). It is the specification for what you write, and the
  prose in it is part of the material rather than a comment on it.

## After the lecture
* Read [Appendix B](./appendix/b_the_driver.md), which specifies the driver in prose: every
  function, what it returns, and what it must do at the boundaries.
* Work through [Appendix C](./appendix/c_exercises.md), ending with the **Cross-check**: work out
  by hand what a sequence of five calls must return, then write a program that performs it and
  reconcile. One of the five is not what almost anyone predicts.
* Write `qa_fifo.c` in [`lab/`](./lab) and make `make test L=L05` report **PASSED**, with the
  KUnit suite reporting **10 of 10**.

---

## What you should be able to do afterwards
* Say what a major and a minor number each select, and find both for any node in `/dev`.
* Write a `struct file_operations` and register it, both the long way and with `misc_register`.
* Explain the three separate things `copy_to_user` checks, and what goes wrong if you skip it.
* Say what `read()` must return when it has nothing to give, and why zero is the wrong answer.
* Choose the right `-Exxx` for a given failure and say what userspace will print for it.
* Give one reason to add an `ioctl` and two reasons not to.
* Write a ring buffer that survives its own wraparound, and prove it with a test rather than by
  inspection.

---

## Questions to test yourself
* Two device nodes have the same major and different minors. What do they have in common?
* Why is `copy_to_user` a function rather than a macro that expands to `memcpy`?
* Your `read()` returns 0 whenever the buffer is empty. Describe what `cat /dev/yours` does, and
  say why it is not what you wanted.
* What does `open()` on your device return if you never implemented `open` in your
  `file_operations`?
* Where does the node in `/dev` come from, given that your driver only registered a number?
* A ring buffer passes every test except one about wraparound. What is almost certainly wrong with
  it, and why did the other tests not catch it?

---

## Reference
* [Appendix A](./appendix/a_character_devices.md) is the character device interface;
  [Appendix B](./appendix/b_the_driver.md) is the specification of what to build;
  [Appendix C](./appendix/c_exercises.md) contains the exercises.
* [`lab/qa_fifo.h`](./lab/qa_fifo.h) is the contract, and
  [`lab/qa_fifo_kunit.c`](./lab/qa_fifo_kunit.c) is what checks it. Reading the suite before you
  start is allowed and recommended; it is a specification written in a second language.
* The suite tests nothing about concurrency, and says so at the top. That is L07.

---

## Next lecture
* Where a driver gets memory, and the flag that says which context you are in.
* How a driver reaches its hardware, and why the compiler must not be trusted with it.
* `ioremap`, `readl`, and the address you compute by hand before you map it.
* The error path you write four times and then delete.

---
