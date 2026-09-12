# Appendix C - Exercises
Nine, ending with the Cross-check. Do them in order; C.6 onwards need the target running.

Where an exercise can be checked mechanically, a **Check yourself** line says how.

---

## C.1 Recall: sleeping and spinning

**a)** A task is sleeping and another is spinning on a flag. For each, say what state it is in,
whether it is on the run queue, and what it costs.

**b)** Why can a task in `TASK_UNINTERRUPTIBLE` not be killed with signal 9? What is it usually
waiting for, and what does its presence in `ps` output tell you?

**c)** Which of the two sleeping states should a driver use, and why essentially always?

**d)** `schedule()` is called by the incorrect versions in
[Appendix A.2](./a_sleeping.md#a2-the-wrong-version-and-why-it-is-wrong-every-time) and by the
correct one in [A.3](./a_sleeping.md#a3-what-the-macro-actually-does). What else has to happen for
it to be a sleep rather than a yield?

---

## C.2 Recall: the lost wakeup

The second version from [Appendix A.2](./a_sleeping.md#a2-the-wrong-version-and-why-it-is-wrong-every-time),
with the reader already on the queue the handler wakes:

```c
if (fifo_empty()) {
        set_current_state(TASK_INTERRUPTIBLE);
        schedule();
}
```

**a)** Write out the interleaving that loses the wakeup. Be precise about where the interrupt
lands.

**b)** How wide is the window, in instructions? Given a device interrupting every millisecond,
roughly how long before you hit it?

**c)** Which line of `___wait_event`'s expansion closes it? Quote it.

**d)** `wait_event_interruptible` takes a **condition**, not a variable. Give two separate reasons,
one about the lost wakeup and one about what happens after a wake.

**e)** The condition is evaluated many times. What two properties must it therefore have?

**f)** A colleague argues the bug is rare because the window is two instructions. What is wrong
with that reasoning?

---

## C.3 Hand calculation: jiffies

This kernel is `HZ=250`.

**a)** How long is a jiffy, in microseconds?

**b)** `msecs_to_jiffies(1)`, `msecs_to_jiffies(4)`, `msecs_to_jiffies(10)`: give all three. Does
it round up or down, and why does that choice matter?

**c)** `msleep` sleeps for at least `msecs_to_jiffies(n)` jiffies and in practice one more.
Predict the measured duration of `msleep(1)`, `msleep(4)` and `msleep(10)`.

**d)** Two of those three are the same number. Which, and what does that mean for a driver that
calls `msleep(1)` in a loop expecting a millisecond each time?

**e)** The same driver is rebuilt on a `HZ=1000` kernel. Recompute all three.

**f)** `jiffies` is compared with `time_after` rather than `>`. What goes wrong with `>`, and how
often, on a 32-bit counter at `HZ=250`?

---

## C.4 Hand calculation: choosing a delay

For each, choose `udelay`, `usleep_range`, `msleep`, or a timer, and justify it in one sentence.

**a)** A hardware register needs 2 us to settle, inside a spinlock.

**b)** Polling a status bit that takes about 500 us, in `probe`.

**c)** Retrying a failed transfer in 100 ms.

**d)** Waiting 5 ms in a hard interrupt handler.

**e)** Giving up on a device that has not responded within 2 seconds.

**f)** Waiting 50 us in process context, as accurately as possible.

Then: **g)** one of the six is a trick. Which, and what is the right answer?

---

## C.5 Design: the four cases of `read`

Your driver's `read` faces four situations. For each, give the return value and say what the
calling program observes.

**a)** 40 samples available, 100 requested.

**b)** Nothing available, descriptor is blocking.

**c)** Nothing available, descriptor has `O_NONBLOCK`.

**d)** Nothing available, blocking, and the user presses Ctrl-C.

Then:

**e)** For **b)**, [L05](../../L05/README.md) returned `-EAGAIN` and this lecture blocks instead.
What changed, and why was `-EAGAIN` the right answer then?

**f)** For **d)**, what happens if you return `-EINTR` instead of `-ERESTARTSYS`? What if you
ignore the return value of `wait_event_interruptible` entirely?

**g)** What does returning 0 mean, and name a program that would silently do the wrong thing.

---

## C.6 Code: block until there is data

Write `lectures/L09/lab/qa_wait.c`. Start from your L08 driver and add a character device.

* Keep the interrupt handler from L08, but have it copy samples into a driver-side FIFO of 256
  entries under a spinlock, and call `wake_up_interruptible` when it added anything.
* Add `/dev/qa_wait`, registered the long way as in [L05](../../L05/README.md).
* `read` returns whole samples. Empty and blocking: wait. Empty and `O_NONBLOCK`: `-EAGAIN`.
  Interrupted: `-ERESTARTSYS`.
* Implement `poll`.
* Take a `period_ns` parameter; **zero means create the device but leave it stopped**, which is
  how the tests reach the idle-device cases.

**Check yourself:** `make test L=L09` reports **PASSED**, with eighteen checks in total: ten from
the harness and eight from the userspace tester across its two modes. The shipped
`qa_wait_test` exercises both a running and a stopped device.

**a)** You will be tempted to hold the spinlock across `wait_event_interruptible`. What happens,
and which config option this course enables tells you?

**b)** Name your wait queue `readq` and try to build. Quote the error and explain it.

**c)** With the device running, drain the device and time the next `read`. How long did it block,
and what woke it?

---

## C.7 Code: measure the sleeps

Write `lectures/L09/lab/qa_timing.c`. It must print `HZ` and the jiffy length, then measure the
average duration of `msleep(1)`, `msleep(4)`, `msleep(10)`, `usleep_range(1000, 1000)`,
`usleep_range(100, 100)` and `udelay(100)` over a configurable number of repetitions, using
`ktime_get`.

**Check yourself:** `msleep(1)` and `msleep(4)` come out within a few hundred microseconds of each
other, and `usleep_range(1000)` comes out below one jiffy.

**a)** Why `ktime_get` and not `ktime_get_real`?

**b)** `udelay(100)` measures about 112 us and `usleep_range(100)` about 307 us. Explain both the
ordering and the gap.

**c)** Your module measures `msleep` by calling it 200 times in a loop. Name one thing that
measures which a single call would not, and one thing it hides.

---

## C.8 Design: a timer instead of an interrupt

Your driver gets its data because the device interrupts. Suppose it did not.

**a)** Rewrite the design using a `timer_list` that polls the device every 4 ms. What is the
callback allowed to do, and what would you have to move?

**b)** With `hrtimer` instead, what changes about resolution and about where the callback runs?

**c)** For each design, say what happens to a sample that arrives just after a poll.

**d)** The device's FIFO holds 16 samples. At a 1 ms sample rate, what is the slowest poll interval
that cannot lose data? What does that number become if the FIFO were 4 deep?

**e)** State the general rule for when polling is the right answer and when an interrupt is.

---

## C.9 Cross-check: a millisecond that is not a millisecond

Predict a duration from `HZ`, measure it, and find that one call takes eight times as long as it
asks for.

**a) Predict.** This kernel is `HZ=250`. Using `msecs_to_jiffies` rounding up, and the rule that
`schedule_timeout` guarantees *at least* the requested number of jiffies, predict the measured
duration of:

* `msleep(1)`
* `msleep(4)`
* `msleep(10)`
* `usleep_range(1000, 1000)`

Write all four down before running anything.

**b) Measure.** Load `qa_timing` with `reps=200` and record all four.

**c) Reconcile.** Answer each:

* Which call came out furthest from what it asked for, and by what factor? Did your prediction
  expect it?
* Two of the four measurements are the same number to within a rounding error. Which two, and is
  that a bug in the measurement, in `msleep`, or in your expectation?
* `msleep(4)` asks for exactly one jiffy and takes two. Where does the second jiffy come from?
  `msleep`'s source does not add one; find the sentence in `schedule_timeout`'s documentation that
  explains it, and say why a guarantee of "at least" costs an extra tick.
* `usleep_range(1000)` asks for the same duration as `msleep(1)` and takes a fifth as long. What
  is it using instead, and what did you give up to get that?

**d) Make a prediction and test it.** Your account of the extra jiffy implies something specific
about `msleep(5)` on this kernel. Predict it, measure it, and say whether you were right.

**e) Change the constant.** Recompute all four predictions for `HZ=1000`. Which of the four
measurements would change, and which would not? What does that tell you about which of these
functions are quantised and which are not?

**f)** A driver contains `for (i = 0; i < 1000; i++) msleep(1);` in a loop, with a comment saying
"wait one second". How long does it actually take on this kernel? On a `HZ=1000` kernel? Rewrite
the line so it does what the comment says on both.

**g)** You are asked to document your driver's worst-case response time. Everything measured here
was an average over 200 repetitions on an idle machine. Say what you would put in the document,
what you would refuse to claim from these numbers, and what you would have to measure instead.
[L12](../../L12/README.md) is that measurement.

---
