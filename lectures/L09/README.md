# L09 - Sleeping, Waiting, and Time

## Agenda
* What sleeping is: a task state, a queue, and a scheduler that stops choosing you.
* Wait queues, and the condition that is re-tested after every wake.
* The lost wakeup: why the obvious flag-and-sleep is wrong every time, not rarely.
* Completions, and when they are the simpler answer.
* Blocking `read()`, `O_NONBLOCK`, and `-EAGAIN` at the right moment.
* `poll`, and what a driver must implement for `select` to work on it.
* Signals, `-ERESTARTSYS`, and an interruptible sleep that gets interrupted.
* Jiffies, `HZ`, `ktime`; delaying against sleeping; timers against hrtimers.

---

## Lecture plan
Worked in this order:

1. **Sleeping is not waiting.** A sleeping task is in `TASK_INTERRUPTIBLE`, is on a wait queue,
   and is not on the run queue at all: the scheduler does not consider it. A spinning task is
   `TASK_RUNNING` and burns a CPU. The distinction is the entire subject of the lecture, and the
   reader has already met the consequence in L07, where one primitive slept and the other did not.
2. **Build the wrong one first.** A flag, a `while (!flag) schedule();`, and why it is wrong in
   two independent ways. Then the sharper version: set the flag, then sleep. The wakeup arrives
   between those two statements and is lost forever. **This is not a rare race.** With an
   interrupt at one millisecond it happens in seconds.
3. **What `wait_event_interruptible` actually expands to.** Add to queue, set state, *re-test the
   condition*, then schedule. The re-test after being queued is what closes the window in step 2,
   and it is why the macro takes a condition rather than a flag. Also why the condition is
   evaluated many times and must therefore be cheap and side-effect free.
4. **Waking.** `wake_up_interruptible` from L08's handler. Note that waking does not transfer
   control and does not guarantee the condition is still true when the sleeper runs: another
   reader may have taken the data first. Hence the loop, which the macro already wrote for you.
5. **Blocking `read()` properly.** No data and blocking: sleep. No data and `O_NONBLOCK`: return
   `-EAGAIN` immediately. Signal while sleeping: return `-ERESTARTSYS` and let the kernel decide
   whether to restart the call. Getting the third one wrong makes your device un-interruptible
   with Ctrl-C, which users notice.
6. **`poll`.** Two lines of driver code, and suddenly `select`, `poll` and `epoll` all work and one
   thread can wait on your device and a socket together. Show `poll_wait` and the mask, and note
   that `poll` does not block; it registers interest and reports state.
7. **Time.** Jiffies and `HZ`, and why a jiffy is not a unit to quote in a datasheet. `ktime` and
   `CLOCK_MONOTONIC`, which is what you measure intervals with, against real time which can move
   backwards. Then the two-by-two that matters: `udelay` busy-waits and works in atomic context,
   `msleep` sleeps and does not; short delays must use the first and long ones must not.
8. **Timers.** `timer_list` at jiffy resolution, `hrtimer` at nanosecond resolution, and what each
   costs. Then run `qa-dev` from an hrtimer instead of its own interrupt and compare the jitter,
   which is the measurement L12 comes back to.

**If the hour runs short, compress step 8.** Do not compress step 2; the lost wakeup is the thing
this lecture exists to prevent.

---

## Before the lecture
* Read [Appendix A](./appendix/a_sleeping.md), which is sleeping and wait queues.
* Have `make test L=L08` passing. This lecture wakes the reader that L08's handler feeds.

## After the lecture
* Read [Appendix B](./appendix/b_time.md), which is time, delays and timers.
* Work through [Appendix C](./appendix/c_exercises.md), ending with the **Cross-check**: predict
  what `msleep(1)`, `msleep(4)` and `msleep(10)` actually cost given `HZ`, then measure them. One
  call takes eight times what it asks for, and two of the three answers are the same number.
* Make `make test L=L09` report **PASSED**, including the `poll` test driven from userspace.

---

## What you should be able to do afterwards
* Say what state a sleeping task is in, and what a spinning one is in.
* Describe the lost wakeup, and say which line of `wait_event_interruptible` prevents it.
* Explain why the condition passed to a wait macro is evaluated more than once.
* Implement a blocking `read()` that handles `O_NONBLOCK` and signals correctly.
* Implement `poll`, and say what your driver must do for `select` to work on it.
* Choose between `udelay` and `msleep` from the context and the duration.
* Say what a jiffy is on a given kernel, and why quoting a duration in jiffies is a mistake.
* Choose between a `timer_list` and an `hrtimer`, and say what resolution each gives you.

---

## Questions to test yourself
* Why does `wait_event_interruptible` take a condition rather than a variable to wait on?
* Your reader wakes, finds no data, and returns 0 to userspace. What did the caller conclude, and
  was it true?
* A user presses Ctrl-C while your `read()` is blocked and nothing happens. What did you fail to
  return?
* What is `HZ` on the kernel you built, and how many jiffies is a 3 ms delay?
* `msleep(1)` in a loop of 1000 takes noticeably more than one second. Why?
* Why can `udelay(5000)` be a bug even in code that is allowed to busy-wait?
* Your driver implements `read` but not `poll`. What happens when a program calls `select` on it?

---

## Reference
* [Appendix A](./appendix/a_sleeping.md) is sleeping;
  [Appendix B](./appendix/b_time.md) is time;
  [Appendix C](./appendix/c_exercises.md) contains the exercises.
* [L08](../L08/README.md) produced the events this lecture waits for. The two labs are one driver.
* [L07 Appendix A](../L07/appendix/a_concurrency_and_locks.md) established which primitives may
  sleep; this is the lecture that makes the reader deliberately sleep, in the one place it is
  correct to.

---

## Next lecture
* How a driver finds its hardware without an address in its source.
* Bus, device and driver, and the match that puts the three together.
* Device tree syntax, properly, and the `ranges` you already translated by hand in L06.
* `probe`, and the moment your driver stops being a module that pokes at an address.

---
