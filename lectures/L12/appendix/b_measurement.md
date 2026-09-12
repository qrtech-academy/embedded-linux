# Appendix B - Measuring Latency Honestly
How to measure interrupt latency, what `cyclictest` does and does not measure, and the caveats that
make a number mean something. This appendix is as much about what to refuse to claim as about how
to obtain the figure.

---

## B.1 Which latency

"Latency" names at least four different intervals, and quoting one when you meant another is the
most common error in the subject.

```text
  device asserts the line
       |                         (1) interrupt latency
       v
  hard IRQ handler runs
       |                         (2) handler-to-thread latency
       v
  threaded handler / bottom half runs
       |                         (3) wakeup latency
       v
  userspace read() returns
       |
       v                         (1)+(2)+(3) = interrupt-to-userspace latency
```

A datasheet that says "latency: 12 us" and does not say which of these it is has told you nothing.
The lab measures (1), and only as a spread, and the stretch from the handler to userspace as an
absolute figure; B.3 is why it cannot give the sum. The exercises ask you to say which you would
quote.

---

## B.2 What `cyclictest` measures, and what it cannot

`cyclictest` is the standard real-time benchmark and it works like this: a thread asks to be woken
in *n* microseconds, records the time when it actually wakes, and reports the difference.

```text
T: 0 (  700) P:80 I:1000 C:  10000 Min:  8 Act: 12 Avg: 14 Max:   67
```

Minimum, current, average and maximum wakeup lateness in microseconds, per thread.

**It measures the timer wakeup path.** That is genuinely the thing most real-time applications
care about, it needs no hardware, and it is comparable across machines, which is why it is the
standard.

**It cannot measure your device's interrupt path**, because there is no device in it. Nothing in
`cyclictest` touches your driver, your handler or your interrupt line, so a good `cyclictest`
result says nothing about whether your device's data reaches userspace on time. That is not a
criticism; it is a statement of what the tool is for.

To measure your path you need a timestamp taken **at the device**, which real hardware almost never
provides. That is why this course built a device that does.

---

## B.3 Measuring by subtraction

`qa-dev` records the instant it asserted its interrupt line, in `TS_LO`/`TS_HI`. So the interval
can be *subtracted* rather than inferred:

```c
handler_ns = ktime_get_ns();                      /* first statement of the handler */
lo = readl(regs + QA_DEV_TS_LO);                  /* reading LO latches the pair */
hi = readl(regs + QA_DEV_TS_HI);
device_ns = ((u64) hi << 32) | lo;
```

**Take `ktime_get_ns()` first.** Every instruction before it is counted as interrupt latency, and
the two register reads are not free.

### The two clocks, and why one interval is harder than the other

The device's timestamp comes from QEMU's virtual clock. The guest's `ktime_get_ns()` counts from
its own boot. **The two have different origins**, and the device publishes nothing that relates
them: recovering the constant between them would mean relying on how QEMU happens to implement its
clocks. Measured on this target, `handler_ns - device_ns` sits at about
**-1,768,000,000 ns**, and over 1,720 consecutive interrupts it ranged over 737 us.

So:

| Interval                 | Both ends in           | Usable as                                |
| ------------------------ | ---------------------- | ---------------------------------------- |
| `handler_ns - device_ns` | Different clocks       | A **spread** above the smallest observed |
| `now - handler_ns`       | Both `CLOCK_MONOTONIC` | An **absolute** figure, no correction    |

The second is exact because `clock_gettime(CLOCK_MONOTONIC)` in userspace and `ktime_get_ns()` in
the kernel are the same clock. The first is not, and the honest treatment is to report it as
"worst case, above the best case observed", which is what the lab's program prints and why it
prints a sentence explaining that the absolute value is unknowable here.

**On real hardware with a device that timestamps, the same subtraction gives an absolute figure**,
because the device and the CPU share a clock domain. The technique is the point; the caveat is
specific to measuring inside an emulator.

![A timeline with three marks: the device asserting its line and recording TS_LO and TS_HI, the handler running and calling ktime_get, and read returning to a program holding CLOCK_MONOTONIC. The first interval spans two clocks and carries a constant unknown offset; the second has CLOCK_MONOTONIC at both ends and is absolute.](./images/three_timestamps.png)

---

## B.4 Reading a histogram

A mean and a maximum are not enough. From the lab, `PREEMPT`, idle, 2,000 samples:

```text
latency         count    cum %
       32 us        1    0.05%
       64 us       12    0.65%
      128 us      209   11.10%  ####
      256 us     1309   76.55%  ##########################
      512 us      399   96.50%  #######
     1024 us       61   99.55%  #
     2048 us        6   99.85%
     4096 us        2   99.95%
     8192 us        1  100.00%
```

Four things to read off it:

**The bulk.** 77% of samples are under 512 us. That is the number a throughput argument would
quote and it is the least interesting one here.

**The tail.** Seventy samples out of 2,000 are at 1,024 us or more, nine at 2,048 us or more, and
one is above 8 ms. **The tail is the system**, for a real-time purpose: a deadline of 1 ms is
missed at least 3.5% of the time, which is dozens of times a second at this rate.

**The shape.** A distribution with a long thin tail is a system with a rare blocking event. A
distribution with a second hump is a system with two different behaviours, and finding out what
distinguishes them is usually productive.

**The buckets are logarithmic.** Latency spans orders of magnitude, and linear microsecond buckets
either lose the bottom or produce ten thousand rows. Anyone showing you a linear latency histogram
that covers both 30 us and 30 ms has hidden something.

---

## B.5 The caveats that make a number mean something

A latency figure without these is not a measurement, it is a number.

**Under what load.** The lab measures idle and under four spinning processes on two CPUs. Those
differ by a factor of about four in the mean and about three in the maximum. An idle-system latency
figure describes a system that is not doing anything, which is not the system you are shipping.

**For how long.** A worst case over 2,000 samples is two seconds of evidence. Real qualification
runs for hours or days, because the interesting events are rare by definition. Running the lab's
idle measurement twice on the same kernel gave worst cases of **11,321 us and 2,502 us**: more than
a factor of four, from the same code on the same machine. **One run does not establish a worst
case.**

**On what kernel, with what configuration.** `CONFIG_PROVE_LOCKING`, which this course enables for
[L07](../../L07/README.md), does bookkeeping on every lock acquisition and is not something you
measure latency on. Debug options, tracing and `CONFIG_DEBUG_*` all cost, and a latency number
from a debug kernel is not the number your product has. **This course's own numbers are such
numbers.** Both of its kernels keep lockdep and `CONFIG_DEBUG_ATOMIC_SLEEP` on, `qa.config` for
L07 and `rt.config` so that a driver that sleeps in the wrong place says so, and every figure in
this appendix carries their bookkeeping, on both sides of the comparison.

**And on what machine.** Which is the caveat this course cannot escape.

---

## B.6 What this measurement is blind to

Stated plainly, because everything above is otherwise an invitation to quote a number that is not
true.

**QEMU is not a real-time host.** It is a userspace process on a general-purpose Linux, scheduled
by that kernel, competing with everything else on the machine, on a virtual clock that advances in
steps the guest cannot see. The guest's "interrupt latency" therefore includes the host's
scheduling of QEMU, which has nothing to do with the guest kernel at all and is frequently the
largest term.

**So the absolute numbers are worthless.** Not approximate: worthless. A worst case of 4,964 us on
this target predicts nothing whatever about the same kernel on real silicon, where the equivalent
figure would typically be tens of microseconds.

**What survives is the comparison.** Both kernels run in the same emulator, under the same host
conditions, with the same load, measured the same way. The emulator's contribution is a common
term, and the *difference* between the two columns is still informative even though neither column
is. That is why [Appendix A.8](./a_realtime.md#a8-the-comparison-measured) presents them side by
side and never on their own.

**And even the comparison has a limit**: it establishes the *direction* and roughly the *shape* of
what `PREEMPT_RT` does, and it does not establish the factor. Do not carry "2.3x better worst
case" out of this course.

### What you would need instead

To measure this properly:

* Real hardware, with the device and CPU in one clock domain.
* A kernel with debug options off.
* Hours of running under a load that resembles the product's.
* A device or a scope providing the reference timestamp, or a GPIO toggled by the handler and
  watched externally, which is what people actually do.
* And the discipline to report the maximum, the duration, the load and the configuration together.

That last point is the one that generalises beyond this lecture. It is the same conclusion
[L03's Cross-check](../../L03/appendix/c_exercises.md) reached about an `Image` size and
[L02's](../../L02/appendix/c_exercises.md) reached about a context-switch rate: **a number is
meaningless without the conditions it was measured under**, and the cost of forgetting that rises
with how much the number matters.

---
