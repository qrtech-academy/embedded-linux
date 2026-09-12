# Appendix C - Exercises
Nine, ending with the Cross-check that closes the course. Do them in order; C.6 onwards need both
kernels built, which is `make kernel` and `make kernel RT=1`, and the second kernel's initramfs,
which is `make rootfs RT=1`.

Where an exercise can be checked mechanically, a **Check yourself** line says how.

---

## C.1 Recall: what real time claims

**a)** Define a real-time system without using the word "fast".

**b)** System A responds in 50 us on average and 30 ms at worst. System B responds in 5 ms every
time, never more than 5.1 ms. Which is real time? Answer for a 6 ms deadline and for a 1 ms
deadline.

**c)** A colleague reports that a change "improved latency by 30%". What is the single question
that determines whether that is good news?

**d)** Distinguish hard from soft real time, and say which Linux with `PREEMPT_RT` honestly is.

---

## C.2 Recall: the three sources

**a)** Name the three sources of latency from
[Appendix A.2](./a_realtime.md#a2-where-latency-comes-from).

**b)** For each of these, say which source it contributes to:

* A `spin_lock_irqsave` critical section that copies 4 KB.
* A `udelay(200)` in a probe function.
* A low-priority task holding a mutex a high-priority task needs.
* A hard interrupt handler that takes 300 us.

**c)** Two of the three are somebody's code and one is structural. Which is which, and what
mechanism addresses the structural one?

**d)** Tell the Mars Pathfinder story in four sentences, naming the three priorities involved.

---

## C.3 Hand calculation: a latency budget

A motor controller must react to an encoder interrupt within **500 us**, every time. Measured on
the target hardware:

```text
interrupt to hard handler        max  40 us
hard handler duration            max  15 us
hard handler to threaded handler max 120 us
threaded handler duration        max  60 us
threaded handler to userspace    max 200 us
```

**a)** What is the worst-case interrupt-to-userspace latency? Does it meet the deadline?

**b)** The work is moved entirely into the hard handler, removing the two thread transitions.
Recompute. Does it now meet the deadline, and what have you done to every other device on the
system?

**c)** A driver elsewhere holds a `spinlock_t` for 300 us. Add it to your budget for both **a)**
and **b)**. Which arrangement survives?

**d)** Under `PREEMPT_RT` that 300 us spinlock section becomes preemptible. Recompute **a)**. What
happened, and what has it cost you?

**e)** The requirement is restated as "500 us, 99.9% of the time". What changes about which
numbers you need, and is that easier or harder to demonstrate?

---

## C.4 Design: reading your own driver for hostility

Open the driver you wrote in [L11](../../L11/README.md) and find:

**a)** Every place it disables interrupts, and for how long.

**b)** Every place it holds a lock across something that is not a handful of register accesses.

**c)** Every busy-wait.

**d)** Every assumption that it stays on one CPU.

For each one you find, say what it would cost under `PREEMPT_RT` and what the fix would be. If you
find none of some category, say how you established that.

**e)** Which of the four habits from
[Appendix A.6](./a_realtime.md#a6-what-makes-a-driver-hostile-to-real-time) is the hardest to spot
by reading, and what would you use to find it instead?

---

## C.5 Design: priorities

**a)** You set your measurement program to `SCHED_FIFO` priority 80. Name two things that can now
still preempt it.

**b)** A `SCHED_FIFO` task enters an infinite loop on a single-CPU machine. What happens, and what
saves you?

**c)** `sched_rt_runtime_us` is 950000 out of 1000000. State what that means in one sentence, and
describe the symptom of hitting it.

**d)** Turning the throttle off is possible. When would you, and what do you owe the next person to
work on the system?

**e)** `SCHED_DEADLINE` refuses a request that `SCHED_FIFO` would have accepted. What did it do
that `SCHED_FIFO` does not, and why is a refusal more useful than a missed deadline?

---

## C.6 Code: measure by subtraction

Write `lectures/L12/lab/qa_latency.c`, a platform driver that turns your L09 and L11 work into a
measurement instrument.

* In the interrupt handler, **first** take `ktime_get_ns()`, then read `TS_LO` and `TS_HI` to get
  the instant the device asserted its line. Reading `TS_LO` latches the pair.
* Store both, plus a sequence number and a count of records dropped, in a ring of 512
  `struct qa_latency_record` (declared in [`lab/qa_latency.h`](../lab/qa_latency.h)).
* Present `/dev/qa_latency`, whose `read` blocks until records are available and returns as many
  whole records as fit, with `O_NONBLOCK` and `poll` support as in L09.
* Count records dropped when the ring is full rather than overwriting.
* Use `devm_` for everything the driver core has a helper for, and
  `devm_add_action_or_reset` for the character device, which has none.

**Check yourself:** `make test L=L12` reports **PASSED**, with ten checks, and
`RT=1 make test L=L12` does too after `make rootfs RT=1` and `RT=1 make build L=L12`.

**a)** Why must `ktime_get_ns()` be the first statement rather than coming after the register
reads? Estimate what you would be adding to every measurement if it came second.

**b)** You forget to rebuild between kernels and `insmod` says `invalid module format`. Which
lecture explained that, and what exactly disagreed?

**c)** The driver drops records under load rather than overwriting the oldest. Argue for that
choice, then argue against it.

---

## C.7 Code: measure from userspace

The measurement program `qa_latency_test` ships with the course. Read it before running it.

**a)** It computes two intervals. Name them, and say which is absolute and which is only a spread.
Why the difference?

**b)** It takes `clock_gettime` once per batch of records rather than once per record. Why can it
not do better, and what does a large batch tell you about the reader?

**c)** It discards the first few reads. What would they have measured otherwise?

**d)** The histogram buckets are logarithmic. Take the idle `PREEMPT` histogram from
[Appendix B.4](./b_measurement.md#b4-reading-a-histogram) and redraw the top three rows as linear
1 us buckets. How many rows would the full histogram need?

**e)** Run it and read your own histogram. What fraction of samples is under 512 us, and what is
the worst case? Which of those two would you put in a datasheet, and which describes the system?

---

## C.8 Design: what cyclictest is for

**a)** Describe in two sentences what `cyclictest` measures.

**b)** Your `cyclictest` maximum is 45 us and your device's data still arrives late. Explain how
both can be true.

**c)** Name the part of the path in [Appendix B.1](./b_measurement.md#b1-which-latency) that
`cyclictest` covers, and the parts it does not.

**d)** `qa-dev` has a timestamp register. Real hardware almost never does. Given that, how do
people actually measure interrupt latency on real boards? Name two techniques.

**e)** Why did this course build a device with that register rather than using a real one?

---

## C.9 Cross-check: the trade, measured

The last Cross-check. Predict which kernel wins, measure both, and discover that the answer depends
entirely on which number you look at.

**a) Predict.** Before measuring anything, write down whether you expect `PREEMPT_RT` to produce a
**lower mean** and a **lower maximum** than `PREEMPT`, for the handler-to-userspace latency the
lab reports. Commit to both answers separately.

**b) Measure, four ways.** Build and boot both kernels, remembering to rebuild the module for each:

```sh
make kernel      && make build L=L12      && make test L=L12
make kernel RT=1 && make rootfs RT=1
RT=1 make build L=L12 && RT=1 make test L=L12
```

Record the mean and the maximum for each kernel, idle and under load: eight numbers.

**c) Reconcile.** Answer each:

* Which of your two predictions was right, and which was wrong?
* The mean is **worse** under `PREEMPT_RT` and the maximum is **better**. Explain both, in terms
  of what [Appendix A.5](./a_realtime.md#a5-what-preempt_rt-actually-changes) says changes.
* If a colleague measured only the mean, what would they conclude, and would they be wrong?
* State, in one sentence, why "worse average, better worst case" is the definition of the trade
  rather than a disappointing result.

**d) Repeat it.** Run the **same** idle measurement on the **same** kernel three more times and
record the maximum each time. Compare the spread between runs against the difference you measured
between the two kernels in **b)**.

* Is your kernel-to-kernel difference larger than your run-to-run variation?
* If it is not, what have you actually established?
* How many runs would you need before you would defend the comparison in a design review?

**e) The part that matters most.** Everything you have measured was taken inside an emulator.
Write a paragraph, not a sentence, answering: **what is this measurement blind to?** Cover at
minimum which components other than the guest kernel are inside your numbers, why the absolute
values cannot transfer to real silicon, and what specifically survives the comparison and what
does not.

**f)** You are asked for one number for a datasheet: "interrupt-to-userspace latency". Write the
entry exactly as you would submit it, including every condition. Then write the sentence you would
add to say what it does not cover.

**g)** Finally: your driver now probes off a device tree, services interrupts, blocks readers
correctly, registers with two subsystems, and has had its latency characterised. Name the one thing
you would still not deploy it without, and say which lecture told you why.

---
