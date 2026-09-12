# Appendix A - Real Time
What the term claims, where latency comes from, and what `PREEMPT_RT` changes about the driver you
have spent eleven lectures writing.

[Appendix B](./b_measurement.md) is how to measure any of it without lying.

---

## A.1 The definition, and the trap in it

**A real-time system is one in which being late is being wrong.** Not fast: correct within a stated
deadline, every time.

The trap is that "real time" sounds like a performance claim and is not. Consider:

|          | Average | Worst observed |
| -------- | ------- | -------------- |
| System A | 50 us   | 30 ms          |
| System B | 5 ms    | 5.1 ms         |

**System B is real time for a 6 ms deadline and system A is not**, despite being a hundred times
slower on average. A is faster; B is predictable. If your requirement is a 6 ms deadline, A fails
it several times an hour and no amount of tuning its average will help.

Everything in this lecture is about the right-hand column. **An average is not evidence**, and a
measurement without a stated worst case, a stated load and a stated duration is not a measurement
of anything.

Two more distinctions worth having:

* **Hard real time**: a missed deadline is a system failure. An airbag, a motor commutation loop.
* **Soft real time**: a missed deadline degrades quality. Audio, video.

Linux with `PREEMPT_RT` is good soft real time and is used for hard real time by people who have
measured their own system very carefully. It is not a hard real-time operating system in the sense
that a small RTOS with a provable worst case is.

---

## A.2 Where latency comes from

Three sources, and only three. Every real-time problem you will meet is one of them.

**Interrupts disabled.** Between `local_irq_disable()` and the matching enable, no interrupt is
taken, including yours. `spin_lock_irqsave` does this for the length of its critical section, which
is why [L07](../../L07/appendix/a_concurrency_and_locks.md#a5-spinlocks) insisted that those be
short.

**Preemption disabled.** The interrupt is taken but the scheduler cannot switch to your task
afterwards. Holding any spinlock disables preemption, so a long critical section anywhere in the
kernel delays every high-priority task on that CPU.

**Priority inversion.** Your high-priority task is runnable but waiting on a lock held by a
low-priority task, which is itself not running because a medium-priority task is using the CPU. The
high-priority task now waits behind the medium one, which is the inversion.

The first two are code somebody wrote. The third is structural and needs a mechanism, which is A.3.

---

## A.3 Priority inversion, and Mars

The canonical example is worth knowing accurately, because it is usually told badly.

Mars Pathfinder landed in 1997 and began resetting itself. A high-priority bus-management task
needed a mutex held by a low-priority meteorological task; a medium-priority communications task
was runnable and preempted the low-priority one; the low-priority task therefore never finished and
never released the mutex; the high-priority task missed its deadline; a watchdog concluded the
system had failed and reset it.

The fix was to enable **priority inheritance** on that mutex, and it was uploaded to Mars.

Priority inheritance is the mechanism: while a low-priority task holds a lock that a high-priority
task is waiting for, it **temporarily inherits the higher priority**, so it cannot be preempted by
anything in between. It finishes, releases the lock, and drops back.

The reason this story matters to a driver author is that the bug got through testing: it had
caused one or two resets in months of pre-flight testing, and nobody could reproduce or explain
them. It needed three tasks, one lock and a specific interleaving. It is
[L07's](../../L07/appendix/b_deadlock_and_lockdep.md) point about ordering bugs, one level up: **a
system that has never missed a deadline is not a system that cannot.**

---

## A.4 The four preemption models

One question distinguishes them: **when a high-priority task becomes runnable, at what points can
the kernel switch to it?**

| Model               | Switches at                                       | For                                              |
| ------------------- | ------------------------------------------------- | ------------------------------------------------ |
| `PREEMPT_NONE`      | Only on return to userspace, or a voluntary sleep | Throughput. Servers                              |
| `PREEMPT_VOLUNTARY` | Those, plus explicit `might_sleep` points         | Desktops, historically                           |
| `PREEMPT`           | Those, plus almost anywhere in the kernel         | Desktops and embedded. **This course's default** |
| `PREEMPT_RT`        | Those, plus inside most spinlock sections         | Real time                                        |

The progression is one of removing places where the kernel refuses to be interrupted. Each step
costs throughput, because each adds preemption points that must be checked, and buys a lower
worst case.

**`PREEMPT_RT` was merged into mainline in 6.12**, which is the kernel this course builds. That is
recent and it matters: before it, running a real-time Linux meant applying an out-of-tree patch
series that trailed the kernel it patched, sometimes did not exist for a given version, and was a
standing porting cost. [`kernel/rt.config`](../../../kernel/rt.config) is now **four lines**, and
the whole of the difference between the two kernels this lecture compares.

One of those four lines is `CONFIG_EXPERT=y`, and it is not decoration: `PREEMPT_RT` is declared
`depends on EXPERT && ARCH_SUPPORTS_RT`, so without it the symbol is never offered and
`CONFIG_PREEMPT_RT=y` is silently discarded, leaving a kernel that builds, boots, says `PREEMPT`
and is not real time. That is exactly the hidden-prompt mechanism
[L03's exercises](../../L03/appendix/c_exercises.md) make you work through with `GPIO_SYSFS`.

---

## A.5 What `PREEMPT_RT` actually changes

Four things, and the first is the one that reaches your code.

**Most spinlocks become sleeping locks.** `spinlock_t` is replaced by an rt_mutex underneath, so
code holding one can be preempted and can even sleep. That removes the largest source of
preemption-disabled time in the kernel at a stroke.

It also **changes what your driver is allowed to assume.** Code that took a `spinlock_t` and
relied on preemption being disabled, for instance to touch per-CPU data safely, is wrong under
`PREEMPT_RT` and was correct before.

**Most interrupt handlers become threads.** Every handler registered with `request_irq` runs in a
kernel thread by default, exactly like the threaded handlers
[L08](../../L08/appendix/b_deferred_work.md#b4-threaded-handlers) introduced, unless it asks not to
with `IRQF_NO_THREAD`; per-CPU interrupts, and a primary handler requested with `IRQF_ONESHOT`,
stay in hard interrupt context as well. So the hard-interrupt path shrinks to almost nothing and
your handler becomes schedulable, preemptible and prioritisable.

**Mutexes get priority inheritance**, which is A.3's fix applied by default.

**Softirqs are threaded too**, removing another unbounded source of delay.

### What does not change

`raw_spinlock_t` still spins, still disables preemption, and still cannot sleep. It exists for the
places that genuinely cannot be preempted: the scheduler itself, the timer core, the interrupt
entry path.

**Reaching for `raw_spinlock_t` to make your driver faster reintroduces exactly the latency
`PREEMPT_RT` removed**, and does so in a way that is invisible until somebody measures the worst
case. A driver should essentially never contain one.

---

## A.6 What makes a driver hostile to real time

Four habits. Look for them in your own driver; at least two are in it.

**Long critical sections.** Anything held across a loop, a copy, or a call into unfamiliar code.
The fix is to shorten it, not to change the lock type.

**Interrupts disabled across real work.** `spin_lock_irqsave` around a page of processing rather
than around the three lines that touch shared state.

**Busy-waiting.** `udelay(50)` is legal, works, and spends fifty microseconds of a CPU doing
nothing. [L09](../../L09/appendix/b_time.md#b3-delaying-against-sleeping) is where the alternatives
are; the rule is that `udelay` is for a few microseconds of genuine hardware settling time and
nothing else.

**Per-CPU assumptions.** Code that updates a per-CPU variable while holding a `spinlock_t`,
relying on preemption being disabled to keep every other task on that CPU away from it. Correct on
`PREEMPT`, wrong on `PREEMPT_RT`, where the lock still keeps the task on its CPU but no longer
keeps other tasks off it. `local_lock_t` is the lock that does that on both kernels.

---

## A.7 Priorities, and the throttle that saves you

Making a task real-time is one call, and the consequences deserve a paragraph.

| Policy           | Behaviour                                                    |
| ---------------- | ------------------------------------------------------------ |
| `SCHED_OTHER`    | The normal fair scheduler. Everything by default             |
| `SCHED_FIFO`     | Runs until it blocks or a higher priority becomes runnable   |
| `SCHED_RR`       | The same, with a time slice between equal priorities         |
| `SCHED_DEADLINE` | Declares a period and a budget; the kernel admits or refuses |

**A `SCHED_FIFO` task that does not block will not be preempted by anything of lower priority,
including the shell you would use to kill it.** On a single-CPU machine that is an unrecoverable
hang, and it is the classic first mistake.

Linux therefore throttles: `sched_rt_runtime_us` defaults to 950,000 in every 1,000,000, so
real-time tasks get at most 95% of a CPU and something else can always run. That saves you, and it
also means **a real-time task can be preempted by the throttle**, which people discover as an
unexplained 50 ms gap. Turning the throttle off is possible and should be a deliberate, documented
decision.

`SCHED_DEADLINE` is the interesting one for periodic work: you state a period and a worst-case
execution time and the kernel performs an admission test, refusing the request if the deadline
tasks together would need more CPU time than the system allows them. On one CPU that is a real
guarantee rather than a priority; on several it bounds how late a task can be rather than
promising it never is, which is still more than a priority says.

**Two tools that belong next to this, and that this course does not teach.** On a real system you
would also reach for **CPU isolation** (`isolcpus`, `nohz_full`) to keep everything else off the
core your task runs on, and **IRQ affinity** (`/proc/irq/N/smp_affinity`) to decide which core takes
the interrupt. Both are absent here, and the reason is the target rather than the topic: this course
runs on a two-CPU QEMU guest, and isolating one of two emulated CPUs from a scheduler that is itself
emulated produces a number that says nothing about a real machine. That is the same standard B.6
applies to everything else measured here. Know that the two knobs exist and that they are usually
the next thing tried after `PREEMPT_RT`; measure them somewhere with real cores.

---

## A.8 The comparison, measured

The lab measures handler-to-userspace latency, the interval
[Appendix B.3](./b_measurement.md#b3-measuring-by-subtraction) can give as an absolute figure, on
both kernels, idle and under four spinning processes on two CPUs. One run of each:

| Kernel       | Load | Mean     | **Worst**     |
| ------------ | ---- | -------- | ------------- |
| `PREEMPT`    | idle | 449 us   | **11,321 us** |
| `PREEMPT_RT` | idle | 551 us   | **4,964 us**  |
| `PREEMPT`    | busy | 1,685 us | **29,729 us** |
| `PREEMPT_RT` | busy | 2,393 us | **18,559 us** |

Read the two columns separately, because they disagree.

**The mean is worse under `PREEMPT_RT`**, by about 23% idle and 42% loaded. That is the cost of the
extra preemption points, the threaded handlers and the inheritance bookkeeping, and it is expected.

**The worst case is better under `PREEMPT_RT`**, by a factor of 2.3 idle and 1.6 loaded.

**That is the whole trade, and it is the definition of real time in one table.** A change that made
the average worse and the maximum better would be a straightforward regression on a throughput
system and is exactly what you are buying here.

**And every number above is worthless on its own**, for reasons [Appendix B](./b_measurement.md)
sets out in full. They were measured under an emulator, over 2,000 samples, on one run. Repeating
the idle `PREEMPT` measurement gave a worst case of 2,502 us rather than 11,321. The *shape* of the
comparison survives that; the values do not.

---

![Two panels of grouped bars. On the left, mean latency, where PREEMPT is lower at 449 against 551 microseconds idle and 1,685 against 2,393 busy. On the right, the worst case, where PREEMPT_RT is lower at 4,964 against 11,321 idle and 18,559 against 29,729 busy, annotated with the same PREEMPT measurement repeated at 2,502.](./images/latency.png)

---

