# Appendix C - Exercises
Nine, ending with the Cross-check. Do them in order; C.6 onwards need the target running.

Where an exercise can be checked mechanically, a **Check yourself** line says how.

---

## C.1 Recall: where concurrency comes from

**a)** Name the five sources of concurrency from
[Appendix A.1](./a_concurrency_and_locks.md#a1-five-sources-two-of-which-you-have-already-met).
Which of them exist on a single-CPU kernel built with `PREEMPT_NONE`?

**b)** A driver written in 2004 for a single-CPU non-preemptible kernel is copied into a modern
one. Name the two assumptions it makes silently, and say what breaks.

**c)** Your driver's `read()` and its interrupt handler both touch the same buffer. Which of the
five sources is in play, and does the answer change on a single-CPU machine?

**d)** `counter++` is one line of C. How many machine operations is it, and which of them can be
interleaved with another CPU's copy of the same three?

---

## C.2 Recall: atomics and their limits

**a)** `atomic_inc` fixes a shared counter completely. Give a data structure it does not fix, and
state the invariant that spans more than one variable.

**b)** Rewrite this so it is correct, and say which primitive you used and why:

```c
if (atomic_read(&level) < capacity) {
        data[(atomic_read(&head) + atomic_read(&level)) % capacity] = byte;
        atomic_inc(&level);
}
```

**c)** State the rule that separates "use an atomic" from "use a lock", in one sentence.

**d)** `while (!flag) { }` never terminates even though another thread sets `flag`. Explain, and
give the fix. Is the fix a memory barrier?

---

## C.3 Hand calculation: choosing a primitive

For each, choose a spinlock, a spinlock with `_irqsave`, or a mutex, and justify it in one
sentence.

**a)** Protecting a counter touched only by two kernel threads.

**b)** Protecting a buffer touched by `read()` and by an interrupt handler.

**c)** Protecting a structure while copying 4 KB of it to userspace.

**d)** Protecting a device register sequence that takes about 2 microseconds.

**e)** Protecting a list that is walked in a timer callback and modified from `write()`.

**f)** Protecting a structure while allocating memory that may have to be reclaimed.

Then: **g)** two of your answers would deadlock the machine if you had chosen a plain `spin_lock`.
Which, and describe the deadlock in each case.

---

## C.4 Hand calculation: what the race costs

Four threads each increment a shared counter 20,000 times, unlocked.

**a)** What is the expected final value if nothing is lost?

**b)** A run reports `actual=63562`. How many increments were lost, and what percentage is that?

**c)** Ten runs on the same machine with the same code produced losses of 1,564; 6,471; 9,708;
12,278; 16,438; 16,805; 17,285; 17,475; 26,545; and 30,047. Compute the range as a percentage of
the expected total. What does the spread tell you that any single run does not?

**d)** Can the loss ever be zero? Can it ever be 60,000? Justify both from what a lost update is.

**e)** A colleague runs the unlocked version once, gets exactly 80,000, and concludes the lock is
unnecessary. Name the two separate errors in that reasoning.

---

## C.5 Design: atomic context

For each, say whether the code is in atomic context, and whether the call is legal there.

**a)** `kmalloc(64, GFP_KERNEL)` inside `read()`.

**b)** `kmalloc(64, GFP_KERNEL)` inside an interrupt handler.

**c)** `kmalloc(64, GFP_ATOMIC)` inside an interrupt handler.

**d)** `mutex_lock` while holding a spinlock.

**e)** `spin_lock` while holding a mutex.

**f)** `copy_to_user` while holding a spinlock.

**g)** `msleep(1)` inside a timer callback.

Then: **h)** on a kernel without debugging options, three of the illegal ones will usually work in
testing. Which, why, and what makes each fail later? **i)** Which config option that this course
enables would have reported them the first time?

---

## C.6 Code: race a counter, then fix it

Write `lectures/L07/lab/qa_race.c`. It must:

* Take module parameters `threads` (default 4), `increments` (default 20000) and `locked`
  (default 0), all read-only through sysfs.
* Start `threads` kernel threads with `kthread_run`, each incrementing a single shared
  `unsigned long` `increments` times.
* With `locked=0`, increment it without any protection. With `locked=1`, protect it with a
  spinlock.
* **Release all the threads from a barrier**, so that they start together. Without this the first
  thread often finishes before the last is created and the race does not happen at all; see
  [Appendix A.2](./a_concurrency_and_locks.md#a2-what-a-race-actually-costs).
* Wait for all of them to finish, then print exactly:
  `locked=%d threads=%d increments=%d expected=%lu actual=%lu lost=%lu`.

**Check yourself:** with `locked=1` the loss is 0 every time. With `locked=0` it is not.
`make test L=L07` runs the unlocked version three times and requires that at least one of them loses
something.

**a)** Before adding the barrier, run the unlocked version three times and record the losses. Then
add it and run three more. Report both sets.

**b)** Try `threads=1`. What loss do you get, and why is that not evidence of anything?

**c)** Try `threads=8` on a two-CPU target. Does the loss go up in proportion to the threads?
Explain what actually limits it.

---

## C.7 Code: make lockdep object

Write `lectures/L07/lab/qa_abba.c`. It must define two spinlocks, take them in one order and
release them, then take them in the opposite order and release them, all from its init function on
a **single thread**, and print a message before and after.

**Check yourself:** the module loads successfully, `lsmod` shows it, and `dmesg` contains
`WARNING: possible circular locking dependency detected` and a `*** DEADLOCK ***` diagram.

**a)** The module loaded and did not hang. Explain why lockdep reported a deadlock anyway.

**b)** The report's diagram has a CPU0 column and a CPU1 column. How many CPUs actually executed
your code? What are those two columns, then?

**c)** Find the two `qa_abba_init+0x...` offsets in the report's dependency chain. What is each one
telling you, and why are they different?

**d)** Reload the module a second time without rebooting. Does the report appear again? Explain in
terms of what lockdep is storing.

**e)** Now fix the module so both sections take the locks in the same order. Confirm the report is
gone. Has your module's behaviour changed in any observable way other than the absence of the
warning?

---

## C.8 Design: what the tools do not see

**a)** `qa_race` loses up to 38% of its increments with lockdep fully enabled, and lockdep says
nothing at all. Explain why, precisely.

**b)** State the general limitation that follows, and say what it implies about a codebase that
"passes with lockdep enabled".

**c)** Name two kinds of deadlock lockdep cannot find, and say why each is outside its model.

**d)** Lockdep only sees code that runs. Which parts of a driver are least likely to be exercised
by a test suite, and why does that matter more for lock ordering than for most bugs?

**e)** A development kernel has a proprietary module loaded. What has silently happened to lockdep,
what is the single line of `dmesg` that said so, and which lecture did you first meet it in?

---

## C.9 Cross-check: a number computed twice

Predict a total by arithmetic, measure it, and account for the difference. Unlike the earlier
Cross-checks the disagreement here is not a rounding artefact; it is the bug.

**a) Predict.** With `threads=4` and `increments=20000`, compute the expected final counter. This
is one multiplication and it is not the interesting part; write it down anyway, because it is the
number everything else is measured against.

**b) Measure, locked.** Load with `locked=1` and record `actual`. Run it three times.

**c) Measure, unlocked.** Load with `locked=0` and record `actual` five times.

**d) Reconcile.** Answer each:

* The locked runs agree with your prediction exactly, every time. Why is "exactly" the right word
  here, rather than "to within measurement error"? What is different about this measurement
  compared to L03's `Image` size or L02's context-switch rate?
* The unlocked runs disagree with your prediction and with each other. Compute the mean and the
  range. Is the mean a useful number? What would you have to say alongside it for it to mean
  anything?
* In the interleaving drawn in A.2, a collision loses exactly one increment. If every collision
  were of that kind, how many times did two threads collide in your worst run? A thread preempted
  between its load and its store erases every increment made while it was off the CPU; what does
  that make your figure, a count or a bound? Is it plausible given the run took a few hundred
  milliseconds?

**e) Change one variable at a time.** Rerun the unlocked version three times each at
`increments=200`, `2000`, `20000` and `200000`, keeping `threads=4`. Report the loss as a
*percentage* of the expected total in all twelve runs.

The result is not the smooth curve most people predict. Answer these:

* At which values does the loss appear at all, and what happens below that?
* You now have a configuration in which the unlocked program is **correct every single time**.
  Is the bug absent at that size? What is actually different?
* The threads are released from a barrier, so they genuinely start together. Given that, explain
  why a short run still does not collide. How long does the overlap have to last, and what is it
  competing against?
* Someone testing this code would naturally use a small number of iterations, because it is
  faster. Say what they would conclude and how confident they would be.

**f) The prediction that matters.** You now have a measurement whose value you cannot predict, and
a measurement whose value you can. Say which of the two you would put in a bug report and which you
would put in a test, and why they are not the same choice.

**g)** A colleague proposes fixing `qa_race` by making the counter `atomic_t` instead of adding a
lock. For this specific program, would that work? Now suppose the threads also had to keep a
running maximum alongside the counter. Would it still work? Which appendix section answers this,
and what is the one-sentence rule?

---
