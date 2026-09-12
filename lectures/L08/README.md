# L08 - Interrupts and Deferred Work

## Agenda
* The path from a wire going high to your function being called, and the three numbers along it.
* `/proc/interrupts`, and what each column is actually counting.
* `request_irq`, the handler signature, and `IRQ_HANDLED` against `IRQ_NONE`.
* Level and edge triggering, and an acknowledge that has to happen in the right order.
* What a handler may not do, and what happens when it does it anyway.
* Four places to put the work that does not belong in the handler.
* Threaded handlers, and why they are the default answer now.
* Live: take `qa-dev`'s interrupt, acknowledge it correctly, and move the work out.

---

## Lecture plan
Worked in this order:

1. **Three numbers, not one.** The device asserts a line. The interrupt controller knows it as a
   hardware interrupt number. Linux knows it by a *virtual* IRQ number, allocated at probe time
   and unrelated to the first two. The device tree says `interrupts = <0 112 4>`; `/proc/interrupts`
   says something else entirely. People lose an afternoon to this, and the fix is knowing there are
   three numbers and which one each tool prints.
2. **Read `/proc/interrupts` together.** The count column, per CPU. Watch it move. Then note that
   a count that is not moving and a device that is not working is a different bug from a count
   that is racing away, and that the file distinguishes them in one line.
3. **`request_irq`.** The signature, the flags, and the `dev_id` cookie that is both handed back
   to you and used to identify your registration at `free_irq` time. Then shared interrupts:
   `IRQ_NONE` means "not mine", and a handler that returns `IRQ_HANDLED` unconditionally on a
   shared line breaks every other device on it.
4. **The acknowledge, and the order.** `qa-dev` is level triggered: it holds the line high until
   the guest clears `IRQ_STATUS`, by writing to it or, for `IRQ_SAMPLE`, by emptying the FIFO. So
   a handler that does neither is re-entered immediately, forever, and the machine wedges. **Do
   it live.** Then do it in the wrong order, which is subtler: drain first and acknowledge
   afterwards with the value read on entry, and an event that arrived after the drain has its bit
   cleared and its sample left in the FIFO with no interrupt to collect it.
5. **What a handler may not do.** It may not sleep, which rules out `GFP_KERNEL`, mutexes, and
   `copy_to_user`. It runs with interrupts disabled on its own line, so everything in it is time
   the rest of the system is not running. That is the whole reason for step 6.
6. **Four places to defer to.** Softirq, tasklet, workqueue, and a threaded handler. What each
   costs, which context each runs in, and which of them may sleep. Tasklets are deprecated and the
   appendix says what to read them as when you meet them in old code.
7. **Threaded handlers.** `request_threaded_irq` with a hard handler that acknowledges and a
   thread that does the work. Say why this is the default answer now: it is preemptible, it may
   sleep, it has a priority you can set, and under `PREEMPT_RT` almost every handler becomes one
   whether you asked or not. That last point is L12's, and this is where it is set up.
8. **Live coding.** Count `qa-dev`'s interrupts in the handler, do nothing else, and watch
   `/proc/interrupts`. Then move the FIFO drain into a threaded handler.

**If the hour runs short, compress step 6** to a table. Do not compress step 4; the wedged machine
is the lesson.

---

## Before the lecture
* Read [Appendix A](./appendix/a_interrupts.md), which is the interrupt path and handler rules.
* Have `make test L=L07` passing. From this lecture on, your own device can interrupt your own
  code, and L07's rules about what may run at the same time apply to the handler you write.

## After the lecture
* Read [Appendix B](./appendix/b_deferred_work.md), which is deferred work in its four forms.
* Work through [Appendix C](./appendix/c_exercises.md), ending with the **Cross-check**: predict
  how many interrupts `qa-dev` will raise in T seconds from `PERIOD_NS`, then read the delta out
  of `/proc/interrupts` and account for the shortfall. Your first explanation will be partly
  right, and the exercise is about finding out which part.
* Make `make test L=L08` report **PASSED**.

---

## What you should be able to do afterwards
* Trace an interrupt from the device's line to your handler, naming the three numbers involved.
* Read `/proc/interrupts` and say what a stuck count and a racing count each indicate.
* Register a handler, and say what the `dev_id` argument is for on a shared line.
* Say when `IRQ_NONE` is the correct return value, and what breaks if you never return it.
* Acknowledge a level-triggered interrupt in the right order, and say what the wrong order loses.
* List what a hard interrupt handler may not do, and derive the list from one fact rather than
  memorising it.
* Choose between a workqueue and a threaded handler, and defend the choice.

---

## Questions to test yourself
* The device tree says interrupt 112 and `/proc/interrupts` says 47. Are they the same interrupt?
* Your handler runs once and the machine then stops responding. What did you forget?
* Why can a hard interrupt handler not call `copy_to_user`, given that it is only copying memory?
* On a shared line, your handler always returns `IRQ_HANDLED`. Describe the symptom on the *other*
  device sharing that line.
* What is the difference between a tasklet and a workqueue, in terms of what each may do?
* You measure 9,847 interrupts where you predicted 10,000. Name two mechanisms that could account
  for the difference, and say how you would tell which it was.

---

## Reference
* [Appendix A](./appendix/a_interrupts.md) is the interrupt path;
  [Appendix B](./appendix/b_deferred_work.md) is deferred work;
  [Appendix C](./appendix/c_exercises.md) contains the exercises.
* [`tools/qa-dev/qa-dev.h`](../../tools/qa-dev/qa-dev.h) documents `IRQ_STATUS` as
  write-one-to-clear, and the device tree node declares the line level triggered. Both are
  load-bearing for step 4.
* The device's own model, [`tools/qa-dev/qa-dev.c`](../../tools/qa-dev/qa-dev.c), is readable and
  shows exactly when the line is raised and lowered. Reading the hardware's source is a luxury you
  will not have again.

---

## Next lecture
* The other half: a reader that wants data which does not exist yet.
* Wait queues, and the lost wakeup that is a bug rather than bad luck.
* `poll`, and how one thread waits on your device and a socket at once.
* Jiffies, `ktime`, and the difference between delaying and sleeping.

---
