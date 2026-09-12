# L07 - Concurrency and Locking

## Agenda
* Five sources of concurrency in a kernel, only one of which is another CPU.
* Atomics: what they promise, and the much larger thing they do not.
* Memory barriers, and why the compiler is as much of a problem as the processor.
* Spinlocks, `_irq` and `_irqsave`; what each one disables and at what cost.
* Mutexes and semaphores, and the single question that chooses between them and a spinlock.
* Atomic context, `might_sleep()`, and why "do not sleep here" is not a style rule.
* Deadlock, lock ordering, and lockdep.
* Live: race the L05 ring buffer, watch it lose data, then fix it.

---

## Lecture plan
Worked in this order:

1. **Where concurrency comes from.** Five sources, and the reader has met two of them already:
   another CPU running your code (SMP), the scheduler preempting you mid-function (preemption), an
   interrupt arriving (L08), a timer firing, and a workqueue running your deferred work. On a
   single-CPU non-preemptible kernel, only the interrupt is left, with the timers that fire on the
   way out of one, and that is why old driver code looks the way it does and why copying it is
   dangerous.
2. **Break it, live.** Two threads, both calling the ring buffer from L05. Run it. Count what went
   in and what came out; the numbers differ. Then say the uncomfortable part: it passed ten KUnit
   cases, and the suite said at the top that it tests nothing about concurrency. **A passing test
   suite is a statement about what was tested.**
3. **Atomics are not enough.** `atomic_t` and `atomic_inc` make one operation indivisible. The
   ring buffer's problem is that *three* operations have to be indivisible together. Show that
   making each of head, tail and level atomic fixes nothing, because the invariant spans them.
   This is the misconception worth the most time in the room.
4. **Barriers.** The compiler may reorder your stores; the CPU may reorder them again. `READ_ONCE`
   and `WRITE_ONCE` for the first, `smp_mb` and friends for the second. Keep it short and
   concrete, and say that most driver code should be using a lock instead, which provides both.
5. **Spinlocks.** Busy-wait, do not sleep, and therefore usable from an interrupt handler. Then
   the trap: taking a spinlock in process context that an interrupt handler on the *same CPU* also
   takes is a self-deadlock, which is what `spin_lock_irqsave` exists to prevent. Draw it.
6. **Mutexes.** Sleep rather than spin, so they cannot be used in atomic context, and they are
   the right answer whenever the critical section is long or may itself sleep. The choosing
   question is exactly one sentence: *can the code that takes this lock sleep, and can the code
   that contends for it wait?*
7. **Atomic context.** What it is, how to tell you are in it, and what `might_sleep()` does.
   Then the demonstration: call `msleep` under a spinlock with `CONFIG_DEBUG_ATOMIC_SLEEP` on,
   and read the splat.
8. **Lockdep.** Build an ABBA deadlock deliberately, in two functions that take two locks in
   opposite orders, and let lockdep report it *without the deadlock actually happening*. That
   last part is the point: lockdep finds the ordering violation the first time it sees both
   orders, not the one time in ten thousand that they collide.

**If the hour runs short, compress step 4.** Do not compress step 3; it is the one that changes
how people write code afterwards.

---

## Before the lecture
* Read [Appendix A](./appendix/a_concurrency_and_locks.md), which is the sources of concurrency
  and the primitives.
* Have `make test L=L06` passing.

## After the lecture
* Read [Appendix B](./appendix/b_deadlock_and_lockdep.md), which is deadlock, lock ordering and
  lockdep.
* Work through [Appendix C](./appendix/c_exercises.md), ending with the **Cross-check**: compute
  the expected final counter for N threads and M increments, measure what you actually get
  unlocked, and account for the difference. Then find the iteration count at which the broken
  program is correct every time.
* Make `make test L=L07` report **PASSED**, which includes producing a lockdep report on purpose.

---

## What you should be able to do afterwards
* Name five sources of concurrency in a kernel and say which of them a single-CPU kernel has.
* Say why making every field of a structure atomic does not make the structure thread-safe.
* Choose between a spinlock and a mutex, and give the one-sentence reason.
* Say what `spin_lock_irqsave` saves and restores, and what goes wrong without it.
* Recognise atomic context in unfamiliar code, and list what may not be done there.
* Read a lockdep report and say which two locks, taken in which orders, it is complaining about.
* Explain why lockdep can report a deadlock that has not happened.

---

## Questions to test yourself
* Your driver works perfectly on a single-CPU target and corrupts data on a dual-CPU one. Name
  three things that changed, only one of which is "two things run at once".
* Why is `atomic_read` followed by `atomic_set` not an atomic read-modify-write?
* You hold a spinlock and call `kmalloc(GFP_KERNEL)`. What is wrong, and when will you find out?
* What exactly does a spinlock do to the CPU that is waiting for it? Why is that acceptable for
  short sections and catastrophic for long ones?
* Two functions take locks A and B in opposite orders, and the code has run in production for two
  years without deadlocking. Is it correct?
* Why does `CONFIG_PROVE_LOCKING` make a kernel slower, and why would you still enable it during
  development?

---

## Reference
* [Appendix A](./appendix/a_concurrency_and_locks.md) is the primitives;
  [Appendix B](./appendix/b_deadlock_and_lockdep.md) is deadlock and lockdep;
  [Appendix C](./appendix/c_exercises.md) contains the exercises.
* [`kernel/qa.config`](../../kernel/qa.config) turns on `CONFIG_PROVE_LOCKING` and
  `CONFIG_DEBUG_ATOMIC_SLEEP` for this course, with a comment on why. Those two options are the
  reason the exercises in this lecture produce output rather than silence.

---

## Next lecture
* The other source of concurrency, and the one you cannot schedule.
* What an interrupt handler may not do, and what it must do before it returns.
* Four places to put work that does not belong in a handler.
* Why the default answer is now a thread.

---
