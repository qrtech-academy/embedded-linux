# Appendix C - Exercises
Nine, ending with the Cross-check. Do them in order; C.6 onwards need the target running.

Where an exercise can be checked mechanically, a **Check yourself** line says how.

**A warning about C.8.** It asks you to load a handler that never acknowledges its device. That
wedges the machine, on purpose, and the only way out is a reboot. A few seconds here; do not run the
equivalent against anything you cannot power-cycle.

---

## C.1 Recall: the three numbers

**a)** The device tree says `interrupts = <0 112 4>` and `/proc/interrupts` says `17 ... GIC-0 144`.
Explain all three numbers and where each comes from.

**b)** $112 + 32 = 144$. What is the 32?

**c)** Which of the three changes if you boot the same kernel on the same machine with one extra
device present? Why?

**d)** A datasheet documents the device's interrupt as 112. A colleague greps `/proc/interrupts`
for 112, finds nothing, and concludes the driver is not loaded. What has gone wrong with their
reasoning?

**e)** What does the third cell, `4`, mean, and what would `1` have meant instead?

---

## C.2 Recall: reading `/proc/interrupts`

```text
 17:       1789          0  GIC-0 144 Level     qa_irq
```

**a)** Name every field.

**b)** The second CPU's count is 0. Give two different explanations, and say how you would tell
them apart.

**c)** The count is not moving and the device is not working. What have you ruled out, and what is
still possible?

**d)** The count is increasing by millions per second. What is almost certainly wrong?

**e)** You unload your module and load it again. Does the count restart from zero? What does that
imply for any measurement of an interrupt rate?

---

## C.3 Hand calculation: the acknowledgement

`qa-dev`'s `IRQ_STATUS` is write-one-to-clear. At the moment your handler runs, it holds
`0b01` (`QA_DEV_IRQ_SAMPLE`). For **c)** to **e)**, suppose the bit is cleared only by a write to
it; **f)** is about the other way this device has.

**a)** Your handler writes `0xFFFFFFFF` to it. What happens to the `SAMPLE` bit? What happens to an
`OVERRUN` that the device set one microsecond after your read?

**b)** Your handler writes back exactly the value it read. Same two questions.

**c)** Your handler acknowledges first and then drains the FIFO. Describe the sequence of events
that produces a spurious interrupt, and say whether any data is lost.

**d)** Your handler drains the FIFO and then acknowledges with a value it read *before* draining.
Describe the sequence that loses an event.

**e)** Of **c)** and **d)**, one is survivable and one is not. Which, and why?

**f)** For this device there is a second way to clear `IRQ_SAMPLE` that involves no write to
`IRQ_STATUS` at all. What is it, and how would you find that out from
[`tools/qa-dev/qa-dev.c`](../../../tools/qa-dev/qa-dev.c)?

---

## C.4 Hand calculation: an interrupt budget

A device raises an interrupt every 250 microseconds. Its handler takes 8 microseconds.

**a)** How many interrupts per second, and what fraction of one CPU does the handler consume?

**b)** The handler grows to 40 microseconds. Recompute both.

**c)** At what handler duration does the CPU do nothing but service this device?

**d)** The device's FIFO holds 16 samples and it produces one per interrupt. How long can the
system ignore the device before samples are dropped?

**e)** You move 30 of the 40 microseconds into a threaded handler. Which of your answers change,
and which does not? In particular, does the *system's* total work change?

---

## C.5 Design: where does the work go

For each, choose hard handler, threaded handler, or workqueue, and justify it in one sentence.

**a)** Reading a status register and clearing an interrupt.

**b)** Copying 4 KB out of the device's FIFO into a driver buffer.

**c)** Waking a userspace reader that is blocked on `read()`.

**d)** Allocating a buffer with `GFP_KERNEL`.

**e)** Retrying a failed transfer after a 10 ms delay.

**f)** Updating a statistics counter.

**g)** Logging an error with `dev_err`.

Then: **h)** two of your answers would be illegal in a hard handler. Which, and what exactly goes
wrong? **i)** Which config option this course enables would tell you?

---

## C.6 Code: take the interrupt

Write `lectures/L08/lab/qa_irq.c`. It must:

* Find the device's node with `of_find_compatible_node` using `QA_DEV_DT_COMPATIBLE`, get its
  address with `of_address_to_resource`, and its interrupt with `irq_of_parse_and_map`. Print both.
* Claim and map the registers as in [L06](../../L06/README.md), and check the identity register.
* Register a handler with `request_irq`, named `qa_irq`.
* Program `PERIOD_NS` from a module parameter (default 1000000) and set `ENABLE | IRQ_EN`.
* In the handler: read `IRQ_STATUS`, **return `IRQ_NONE` if nothing is pending**, acknowledge with
  the value you read, then drain the FIFO counting samples.
* Count hard interrupts and samples in `atomic_t`s and print them on unload.
* Take a `threaded` module parameter which, when set, uses `request_threaded_irq` with
  `IRQF_ONESHOT` and does the draining in the threaded half.
* Disable the device and `free_irq` on unload, in that order.

**Check yourself:** `make test L=L08` reports **PASSED**, with nine checks. `/proc/interrupts` gains
a `qa_irq` line whose count climbs at roughly a thousand per second.

**a)** Why must the device be disabled before `free_irq`, and not after?

**b)** Your handler returns `IRQ_HANDLED` unconditionally instead of checking. On this target
nothing appears to break. Explain what you have broken anyway, and on what kind of system it would
show up.

---

## C.7 Code: the threaded half

With `threaded=1`:

**a)** Find the kernel thread with `ps`. What is it called, and what does the name tell you?

**b)** The hard handler now returns `IRQ_WAKE_THREAD`. Where must the acknowledgement happen, and
what happens if you leave it in the threaded half without `IRQF_ONESHOT`?

**c)** Measure the interrupt rate both ways over two seconds. Is the threaded version slower?
Was that your prediction?

**d)** Name two things the threaded handler can do that the hard one cannot, and one thing it
gives you that a workqueue does not.

---

## C.8 Design: the interrupt that never stops

**Read the warning at the top of this appendix.**

**a)** Remove everything in your handler that clears `IRQ_SAMPLE`: the acknowledgement, and the
drain with it, because emptying the FIFO clears the bit too (C.3 **f)**). Rebuild, load it, and
record what happens to `insmod`, and how long it takes before the console says anything.

**b)** The message that eventually appears mentions neither interrupts nor your driver. Quote it,
and explain the connection.

**c)** This produces no failing test. `make test L=L08` reports something other than a failure;
what, and why does the harness draw that distinction?

**d)** From another machine you cannot get, but suppose you could run one command on this one
before it died. Which, and what would it have shown?

**e)** `qa-dev` is level-triggered. Would the same missing acknowledgement wedge an edge-triggered
device? What would happen instead?

---

## C.9 Cross-check: interrupts counted two ways

Predict a count from the period, measure it, and account for a shortfall that is larger than
measurement error and entirely explicable.

**a) Predict.** Your device is programmed with `PERIOD_NS=1000000`. How many interrupts should it
raise in exactly two seconds? Write the number down.

**b) Measure.** Load your module, then take a **delta** across a measured interval:

```sh
n0=$(grep qa_irq /proc/interrupts | awk '{ print $2 + $3 }')
t0=$(cut -d' ' -f1 /proc/uptime)
sleep 2
n1=$(grep qa_irq /proc/interrupts | awk '{ print $2 + $3 }')
t1=$(cut -d' ' -f1 /proc/uptime)
```

Compute the actual elapsed time and the actual count. Do this three times.

**c) Reconcile.** The measured count is short by something like 15%, consistently. Answer each:

* Why a delta rather than reading the count once? What did
  [Appendix A.2](./a_interrupts.md#a2-reading-procinterrupts) say happens across a reload?
* Your elapsed time is not 2.00 s. Does using the measured elapsed time rather than 2.00 remove
  the shortfall? By how much does it move it?
* The remaining shortfall is not noise: three runs agree to within a few percent of each other.
  So it is systematic. **Before reading further, write down a hypothesis.**

**d) Find out.** The device is not a black box; its source is
[`tools/qa-dev/qa-dev.c`](../../../tools/qa-dev/qa-dev.c). Find `qa_dev_arm_timer` and read the one
line that decides when the next interrupt happens.

* Is the next interrupt scheduled relative to *when the last one fired*, or to an absolute
  schedule?
* Given that, what is the actual interval between two interrupts, in terms of the programmed
  period and anything else?
* Does that account for a 15% shortfall at a 1 ms period? Estimate the missing term and say
  whether it is a plausible number for this system.

**e) Test the explanation, and watch it fail.** A relative re-arm means each interval is
`period + overhead`, so the model predicts a **constant** overhead: a large shortfall at short
periods and a small one at long ones.

Run it at `period_ns=10000000` (10 ms), `1000000` (1 ms) and `100000` (0.1 ms). For each, compute
the shortfall *and* the overhead your model implies, which is
`(elapsed / count) - period`.

The measured result on this target:

| Period | Count in ~2.1 s | Shortfall | Implied overhead |
| ------ | --------------- | --------- | ---------------- |
| 10 ms  | 190             | 8.7%      | 947 us           |
| 1 ms   | 1731            | 17.6%     | 213 us           |
| 0.1 ms | 13085           | 38.6%     | 63 us            |

**The implied overhead is not constant. It is larger at longer periods, which is backwards.** The
relative re-arm is real and is part of the answer, and it is plainly not the whole answer.

Do not resolve this by inventing a mechanism. Instead, answer:

* What would the table look like if a fixed per-interrupt overhead were the only effect?
* Your driver is one of at least three things in the measurement: the driver, the kernel's timer
  and scheduler, and QEMU. Which of the three does your `/proc/uptime` measurement include?
* At 10 ms the guest is idle almost all the time and at 0.1 ms it is not. Why might *that* affect
  how promptly an emulated timer is serviced?
* What experiment would separate the device's behaviour from the emulator's? Name one you could
  run, and one you could not run here at all.

**f) The fast end is a different effect.** At 0.1 ms compare the driver's own two counters:

```text
hard=13708  samples=14389
```

More samples arrived than interrupts were taken.

* How can one interrupt deliver more than one sample? Answer in terms of level triggering and
  when the line is re-asserted.
* At 1 ms the same two counters are equal. What changed?
* Which status bit would tell you the device had given up and started dropping samples, and did
  it get set?

**g)** A colleague reports "the device is dropping 15% of its interrupts, the driver is broken".
There are at least three things wrong with that sentence. Rewrite it so that every claim in it is
supported by a measurement you have actually taken, and say what you would still not know.

**h)** You are asked for "the interrupt latency of this device" for a datasheet. Given everything
above, say what you would put, what conditions you would state alongside it, and what you would
refuse to claim. [L12](../../L12/README.md) is the lecture that measures this properly, using a
register that does not exist on real hardware; say why that register is necessary.

---
