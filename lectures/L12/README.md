# L12 - Real-Time Linux

## Agenda
* What "real time" claims, and why it is a statement about the worst case and never the average.
* Three sources of latency, only one of which is the scheduler.
* Priority inversion, and the spacecraft it kept resetting.
* Four preemption models, and what each one is willing to interrupt.
* What `PREEMPT_RT` actually changes: sleeping spinlocks, threaded interrupts, inheritance.
* Which locks do not change, and why `raw_spinlock_t` exists.
* `cyclictest`: what it measures and what it structurally cannot see.
* Live: measure your own driver's latency both ways, interrupt to handler and handler to
  userspace, and plot it.

---

## Lecture plan
Worked in this order:

1. **The definition, and the trap in it.** A real-time system is one where being late is being
   wrong. It says nothing about being fast: a system that responds in 10 ms every single time is
   real time, and one that responds in 100 us on average and 40 ms once an hour is not. **Every
   number in this lecture is a maximum, and an average is not evidence.** People who have measured
   only averages are the audience for this whole hour.
2. **Three sources of latency.** Interrupts disabled, preemption disabled, and a lower-priority
   task holding something the high-priority one needs. The first two are code you or someone else
   wrote; the third is priority inversion. Draw all three.
3. **Priority inversion, and Mars.** The Pathfinder story, briefly and accurately: a high-priority
   task blocked on a mutex held by a low-priority task that was itself preempted by a medium
   -priority one, a watchdog, and a fix uploaded from Earth that enabled priority inheritance.
   It is the clearest example there is of a bug that slipped through testing on the ground and
   kept resetting a spacecraft on Mars.
4. **Four models.** `PREEMPT_NONE`, `PREEMPT_VOLUNTARY`, `PREEMPT` and `PREEMPT_RT`, in terms of
   the single question: when a high-priority task becomes runnable, at what points may the kernel
   switch to it? Then the historical note that matters and is recent: **`PREEMPT_RT` was merged
   into mainline in 6.12**, the kernel this course builds. Before that it was an out-of-tree patch
   series that trailed the kernel it patched. `kernel/rt.config` is four lines, and that is the
   evidence.
5. **What actually changes.** Most `spinlock_t` become sleeping locks, so code that spun now
   sleeps and may be preempted. Most interrupt handlers become threads with priorities. Mutexes
   get priority inheritance. Then the consequence for the reader's own code: the spinlock added in
   L07 and the threaded handler written in L08 behave differently, and a handler that assumed it
   could not be preempted is now wrong.
6. **What does not change.** `raw_spinlock_t` still spins, still disables preemption, and exists
   for the places that genuinely cannot sleep: the scheduler, the timer core, the interrupt entry
   path. Using one to "make it fast" is how you reintroduce the latency `PREEMPT_RT` removed.
7. **What makes a driver hostile.** Four habits: long spinlock sections, interrupts disabled
   across real work, `udelay` loops of any length, and per-CPU assumptions. Go through the
   reader's own driver and find at least two.
8. **Measure it.** `cyclictest` first, and say what it measures: the difference between when a
   timer should have woken a task and when it did. Then say what it cannot see, which is your
   device's interrupt path, because there is no device in it. Then measure that instead, using
   `qa-dev`'s `TS_LO`/`TS_HI`: the device records the instant it raised the line, your handler
   reads it back, and the subtraction is real interrupt latency rather than an inference.
9. **Both kernels, and the honest conclusion.** `make kernel RT=1`, boot it, run the same
   measurement under the same load, and plot the two histograms. Then the part that matters
   professionally: **QEMU is not a real-time host, and the absolute numbers are worthless.** The
   shape of the comparison survives; the microseconds do not. Say what it would take to measure
   this properly, and what you would need to trust the answer.

**If the hour runs short, compress step 3.** Do not compress step 9's second half; a latency
number quoted without its measurement conditions is the mistake this whole lecture exists to
prevent.

---

## Before the lecture
* Read [Appendix A](./appendix/a_realtime.md), which is latency, preemption models and
  `PREEMPT_RT`.
* Run `make kernel RT=1` beforehand, then `make rootfs RT=1`. The kernel is a second full build
  and takes about as long as the first; the initramfs carries that kernel's modules, so it has to
  be built for it separately.
* Have `make test L=L11` passing.

## After the lecture
* Read [Appendix B](./appendix/b_measurement.md), which is measurement: what `cyclictest` does,
  how to read a histogram, and what to refuse to claim.
* Work through [Appendix C](./appendix/c_exercises.md), ending with the **Cross-check**: predict
  whether `PREEMPT_RT` lowers the mean and the maximum, measure both kernels idle and under load,
  and find that the two answers differ. The exercise then asks you to state, at length, what your
  measurement is blind to; that answer is the deliverable, not the number.
* Make `make test L=L12` report **PASSED** on both kernels.

---

## What you should be able to do afterwards
* Define a real-time system without using the word "fast", and say why an average is not evidence.
* Name three sources of latency and say, for a given piece of code, which one it contributes to.
* Explain priority inversion, and say what priority inheritance does about it.
* Choose a preemption model for a stated requirement and defend it.
* Say what `PREEMPT_RT` does to a `spinlock_t` and to an interrupt handler.
* Say why `raw_spinlock_t` exists and when using one is a mistake.
* Find, in unfamiliar driver code, the four habits that make it hostile to real time.
* Run `cyclictest`, read its output, and state precisely what it did and did not measure.
* Present a latency measurement together with the conditions that make it meaningful.

---

## Questions to test yourself
* System A responds in 50 us on average and 30 ms at worst. System B responds in 5 ms every time.
  Which is real time, and for what requirement?
* Your handler takes a `spinlock_t` and does 200 us of work. What changes under `PREEMPT_RT`, and
  is the change an improvement?
* Why can `PREEMPT_RT` not simply make every lock a sleeping lock?
* `cyclictest` reports a maximum of 40 us. What does that tell you about your device's interrupt
  latency?
* A colleague reports "we measured 12 us latency". What four questions do you ask before believing
  it applies to your product?
* Why is a `udelay(50)` in a driver a real-time problem even though 50 us is short?
* You measure lower latency under QEMU than the datasheet claims for real silicon. What happened?

---

## Reference
* [Appendix A](./appendix/a_realtime.md) is the theory;
  [Appendix B](./appendix/b_measurement.md) is the measurement;
  [Appendix C](./appendix/c_exercises.md) contains the exercises.
* [`kernel/rt.config`](../../kernel/rt.config) is the entire difference between the two kernels,
  and its comment explains why it is four lines and used not to be.
* [`tools/qa-dev/qa-dev.c`](../../tools/qa-dev/qa-dev.c) shows exactly when the timestamp is taken,
  which is the one thing you must be sure of before trusting a latency measurement built on it.

---

## Next lecture
There is not one. The course ends here, with a driver that probes off a device tree, services
interrupts, blocks a reader correctly, registers with two subsystems, and whose latency you have
measured and can describe honestly.

What to do next, in rough order of usefulness: read a real driver in `drivers/` for a device you
own and see how much of it you now recognise; write a driver for hardware that exists; and send a
patch, because the review you get on a first patch to a subsystem mailing list is worth more than
any course.

---
