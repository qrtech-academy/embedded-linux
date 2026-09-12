# Appendix B - Deferred Work
A handler must be quick and must not sleep. Most real work is one or the other. This appendix is
the four places to put it, what each costs, and why one of them is the answer nearly every time
now.

---

## B.1 The split, and why it has two names

The kernel's traditional vocabulary is **top half** and **bottom half**. The top half is the
handler that runs in interrupt context: acknowledge the device, take the data out of it, and get
out. The bottom half is everything else, run later, in a context with fewer restrictions.

The names are old and slightly misleading, because "bottom half" also names one specific mechanism
(`local_bh_disable` still refers to it). Modern material says **hard IRQ handler** and **deferred
work**, and this appendix does too.

The question is not whether to split, it is **what to split at**. The dividing line is: the hard
handler does what only it can do, which is whatever must happen before the device is quiet and
whatever would be lost if it waited. Everything else is deferred.

For the lab's device that means: read `IRQ_STATUS`, acknowledge, drain the FIFO so no samples are
dropped, return. Formatting, copying to userspace, waking readers and anything that allocates
belongs on the other side.

---

## B.2 Four places to put it

| Mechanism            | Context       | May sleep | Priority          | Use it                                     |
| -------------------- | ------------- | --------- | ----------------- | ------------------------------------------ |
| **Softirq**          | Interrupt-ish | **No**    | Fixed, very high  | Almost never. Networking and timers own it |
| **Tasklet**          | Interrupt-ish | **No**    | Fixed             | **Deprecated.** Recognise it in old code   |
| **Workqueue**        | Kernel thread | **Yes**   | Schedulable       | Work that sleeps and is not urgent         |
| **Threaded handler** | Kernel thread | **Yes**   | Settable, per-IRQ | The default answer for a driver            |

### Softirqs

A fixed, compile-time set of ten or so, defined in the kernel and not extensible by modules. They
run after the hard handler returns, still in a context that may not sleep, and they can run
concurrently with themselves on different CPUs. Networking and the timer wheel use them. **You will
not add one**, and the reason to know they exist is that they are what `local_bh_disable` and
`spin_lock_bh` are protecting against.

### Tasklets

A softirq with a nicer interface, historically the standard bottom half for drivers. **They are
deprecated**, and the kernel's own documentation says so. Two reasons: they run at a fixed high
priority nobody can tune, and they still cannot sleep, so they solve only half the problem. Code
using them is not broken, it is old; new code should not add any.

```c
/* You will meet this. Do not write it. */
DECLARE_TASKLET(my_tasklet, my_func);
tasklet_schedule(&my_tasklet);
```

### Workqueues

Work runs on a kernel thread, so it **may sleep**: allocate with `GFP_KERNEL`, take mutexes, do
I/O.

```c
static void my_work_fn(struct work_struct *work) { /* may sleep */ }
static DECLARE_WORK(my_work, my_work_fn);

/* from the hard handler */
schedule_work(&my_work);
```

`schedule_work` puts it on the shared system queue, which is convenient and means your work waits
behind everyone else's. A driver that cares creates its own with
`alloc_workqueue`, and one that cares about ordering uses a single-threaded one.

The catch is that **the same work item cannot be queued twice**. If it is already pending, a second
`schedule_work` does nothing, so a burst of interrupts produces one run. Sometimes that is exactly
right; when it is not, you need a queue of your own between the two halves, which is what the FIFO
in this course's driver is.

---

## B.3 What runs when

Worth having straight, because the ordering explains a class of confusing latency.

```text
device asserts line
  -> CPU takes the interrupt, masks it
     -> hard IRQ handler runs          (atomic, fast, must not sleep)
  -> handler returns
     -> softirqs run                   (still atomic)
        -> tasklets are a softirq
     -> scheduler may now run something else
        -> workqueue thread runs when scheduled   (may sleep)
        -> threaded IRQ handler runs when scheduled (may sleep)
```

The hard handler is the only part guaranteed to run promptly. Everything below it runs *when the
scheduler gets to it*, and how soon that is depends on load, priority and the preemption model,
which is [L12](../../L12/README.md)'s subject entirely.

---

## B.4 Threaded handlers

The modern answer, and the one to reach for by default:

```c
request_threaded_irq(irq, qa_hard, qa_thread, IRQF_ONESHOT, "qa_irq", priv);
```

Two functions. `qa_hard` runs in interrupt context and returns `IRQ_WAKE_THREAD`; `qa_thread` then
runs in a dedicated kernel thread and may sleep.

You can see the thread:

```text
# ps | grep irq
   85 root      0:00 [irq/17-qa_irq]
```

It is an ordinary task, with a PID, that the scheduler can preempt, prioritise and account for.
That is the whole advantage over a workqueue: **the deferred work has an identity**. You can
give it a real-time priority, pin it to a CPU, and see it in `top` when it misbehaves.

**`IRQF_ONESHOT` is not optional for a level-triggered device.** It keeps the interrupt masked
from the moment the hard handler returns until the thread has finished. Without it the line is
unmasked as soon as the hard handler returns, and since a level-triggered device is still
asserting until acknowledged, the hard handler is re-entered immediately, which is
[A.6](./a_interrupts.md#a6-what-a-missing-acknowledgement-does). Either the hard handler
acknowledges before returning, or you use `IRQF_ONESHOT`.

Passing `NULL` as the hard handler is allowed and means "wake the thread for every interrupt";
`IRQF_ONESHOT` is then mandatory.

### Measured, on this target

The lab's module both ways, at a one-millisecond period, over two seconds:

|                   | Elapsed | Interrupts serviced | Shortfall against ideal |
| ----------------- | ------- | ------------------- | ----------------------- |
| Hard handler only | 2.11 s  | 1789                | 15.2%                   |
| Threaded handler  | 2.10 s  | 1792                | 14.7%                   |

**The threaded version is not slower**, which surprises people who expect the extra context switch
to cost. For work of this size the scheduler absorbs it, and what you bought is a handler that may
sleep and a thread you can prioritise. Under `PREEMPT_RT` almost every handler becomes one of these
whether you asked or not, which is why L12 revisits this table.

---

## B.5 Choosing

In order of preference:

1. **Do it in the hard handler**, if it is a few register accesses and cannot sleep.
2. **Threaded handler**, if it needs to sleep or is long enough to matter. This is the default.
3. **Workqueue**, if the work is not per-interrupt: something periodic, or triggered from several
   places, or genuinely low priority.
4. **Tasklet**, never in new code.
5. **Softirq**, not available to you.

Two questions decide between 2 and 3. *Is this work one-per-interrupt?* If yes, a threaded handler
already has the plumbing. *Does it need its own priority?* If yes, a threaded handler has one and
the shared workqueue does not.

---

## B.6 What deferring does not fix

It moves work; it does not make it free, and three things stay broken.

**The device still has to be serviced promptly.** `qa-dev` has a FIFO of sixteen samples and sets
`OVERRUN` when it overflows. Deferring the drain does not slow the device down; it just means the
FIFO fills while you wait. If the hard handler does not empty it, no amount of deferred work will
recover the samples that were dropped.

**A high interrupt rate is still a high interrupt rate.** At a hundred-microsecond period the lab's
module services about 13,000 interrupts in two seconds against an ideal of 21,300, a **39%
shortfall**, and no arrangement of deferred work improves that: the cost is in taking the
interrupt at all.

What *does* happen at that rate is visible in the driver's own two counters:

```text
period=1000000   hard=1813   samples=1813     <- one sample per interrupt
period=100000    hard=13708  samples=14389    <- more samples than interrupts
```

At 1 ms the handler keeps up exactly. At 0.1 ms it does not, and the device's level-triggered line
does the only sensible thing: a sample arriving while the line is still asserted does not generate
a second interrupt, it simply joins the FIFO that the handler is about to drain. **The interrupts
coalesced, and no data was lost.**

That is level triggering paying for itself, and it is the answer to why a device under load
generates fewer interrupts than its nominal rate rather than more. Push harder and the FIFO fills,
`OVERRUN` sets, and samples do start being lost; at that point the answer is hardware, in the shape
of a bigger FIFO, explicit coalescing, or DMA.

**The total work is unchanged.** Deferring improves *latency for everything else* and worsens
*latency for this device's data*, which is a trade rather than a win. Knowing which of the two you
are optimising is the point, and L12 is where it gets measured rather than argued about.

---
