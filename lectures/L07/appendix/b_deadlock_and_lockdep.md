# Appendix B - Deadlock, Lock Ordering, and Lockdep
Deadlock is the failure mode that testing does not find, because it depends on two things happening
in an order that almost never occurs. This appendix is what deadlock is, the discipline that
prevents it, and the tool that finds violations of that discipline **without the deadlock having
to happen**.

That last clause is the whole reason lockdep matters, and it is worth being precise about it up
front: lockdep does not detect deadlocks. It detects *the conditions* for one, the first time it
sees them, in a program that ran perfectly.

---

## B.1 The four conditions

A deadlock needs all four of these at once:

| Condition        | Meaning                                 |
| ---------------- | --------------------------------------- |
| Mutual exclusion | The resource cannot be shared           |
| Hold and wait    | A holder may request another resource   |
| No preemption    | The resource cannot be taken away       |
| Circular wait    | A cycle exists in the "waits for" graph |

In kernel locking the first three are given: locks are exclusive, code does take a second lock
while holding a first, and nothing revokes a held lock. **So the only one you can attack is the
fourth**, and every practical anti-deadlock discipline is a way of making a cycle impossible.

In the general case that is a theorem about resource graphs; here it collapses to one rule.

---

## B.2 The rule: a global order

**Define an order over your locks, and always take them in that order.**

If every thread takes locks in the same order, no cycle can form, because a cycle requires at least
one thread to have gone the other way. The order can be anything as long as it is total and
written down: address order, an order documented in a comment, or the structural order implied by a
hierarchy (device lock before channel lock before buffer lock).

The classic violation is called **ABBA**:

```c
/* Thread 1 */                    /* Thread 2 */
spin_lock(&a);                    spin_lock(&b);
spin_lock(&b);                    spin_lock(&a);
```

Each holds one and waits for the other. Both stop, and so does everything that later needs either
lock, which on a busy system is soon everything.

**The reason this survives testing** is that it needs the two threads to interleave in a narrow
window. Thread 1 must acquire `a`, then thread 2 must acquire `b`, then both must ask for the
other, all before either releases. Miss the window and both sequences complete happily. Code with
this bug can run for years.

---

## B.3 Lockdep watches the order, not the outcome

`CONFIG_PROVE_LOCKING`, enabled for this course in
[`kernel/qa.config`](../../../kernel/qa.config), makes the kernel record, for every lock
acquisition, which locks were already held. From that it builds a graph of "lock X has been taken
while holding lock Y" and checks each new edge for a cycle.

**So it does not need the deadlock to happen.** It needs only to see `a` taken while holding `b`,
having previously seen `b` taken while holding `a`, at any earlier point, on any CPU, in any
thread. The first time the second ordering appears, it reports.

The lab's `qa_abba` module demonstrates this in the least dramatic way possible: **one thread, no
concurrency at all, two sequential critical sections.**

```c
spin_lock(&lock_a);
spin_lock(&lock_b);
spin_unlock(&lock_b);
spin_unlock(&lock_a);

spin_lock(&lock_b);
spin_lock(&lock_a);          /* lockdep objects here */
spin_unlock(&lock_a);
spin_unlock(&lock_b);
```

Nothing deadlocks. Nothing can: there is one thread, and each lock is released before the next pair
is taken. The module loads successfully and prints a cheerful message afterwards. Lockdep reports a
deadlock anyway, because it is reporting the *ordering*, and the ordering is wrong.

---

## B.4 Reading the report

This is the real output from the lab on this target, abridged where it repeats. It is worth reading
in order, because the parts are in a deliberate sequence.

**The header: what was being attempted, and what was already held.**

```text
======================================================
WARNING: possible circular locking dependency detected
6.12.30 #6 Tainted: G           O
------------------------------------------------------
insmod/121 is trying to acquire lock:
ffffbfba4a6bc020 (lock_a){+.+.}-{2:2}, at: qa_abba_init+0x6c/0xff8 [qa_abba]

but task is already holding lock:
ffffbfba4a6bc060 (lock_b){+.+.}-{2:2}, at: qa_abba_init+0x64/0xff8 [qa_abba]
```

Two locks, named, with the address of each and **the source location where each was taken**. That
is usually enough on its own.

The `{+.+.}` is the lock's usage signature, recording the contexts it has been used in, which is
how lockdep distinguishes a lock used in interrupt context from one that is not. `-{2:2}` is its
wait type, outer and inner, and 2 means a lock that spins; it is how lockdep catches a lock that
may sleep being taken inside one that may not. You rarely need either.

**The chain: how it already knew about the other order.**

```text
the existing dependency chain (in reverse order) is:

-> #1 (lock_b){+.+.}-{2:2}:
       _raw_spin_lock+0x50/0x70
       qa_abba_init+0x40/0xff8 [qa_abba]
       ...

-> #0 (lock_a){+.+.}-{2:2}:
       __lock_acquire+0x12f4/0x1f48
       lock_acquire+0x1fc/0x330
       _raw_spin_lock+0x50/0x70
       qa_abba_init+0x6c/0xff8 [qa_abba]
```

Note the two different offsets into the same function: `qa_abba_init+0x40` is where `lock_b` was
taken the first time, and `+0x6c` is where `lock_a` is being taken now. **Lockdep is showing you
both halves of the contradiction, with a line number for each.**

**The diagram: the interleaving that would deadlock.**

```text
 Possible unsafe locking scenario:

       CPU0                    CPU1
       ----                    ----
  lock(lock_b);
                               lock(lock_a);
                               lock(lock_b);
  lock(lock_a);

 *** DEADLOCK ***
```

This is the part people misread. **Those two CPUs are hypothetical.** Nothing ran on CPU1; the
module is single-threaded. Lockdep is telling you what *would* happen given the orderings it has
observed, if two threads ever hit them together.

**The backtrace**, which names `print_circular_bug` and `check_noncircular`, the functions that
found it. Seeing those two in a trace is how you recognise a lockdep report at a glance.

---

## B.5 What lockdep does and does not find

**It finds**, without the failure occurring:

* Lock ordering inversions (ABBA), across threads, CPUs and time.
* Taking a sleeping lock in atomic context.
* A lock used both with and without interrupts disabled, in a way that could deadlock against
  its own interrupt handler.
* Recursive acquisition of a non-recursive lock.

**It does not find:**

* **Missing locks.** A data structure with no lock at all has no ordering to violate. `qa_race`
  loses up to 38% of its increments with lockdep fully enabled and lockdep says nothing, because
  nothing did anything wrong with a lock. This is the single most important limitation and the
  reason the lab has two modules rather than one.
* Deadlocks not built from lock ordering: two threads each waiting for the other to signal a
  completion, or a lock against a hardware condition that never arrives.
* Anything on a code path that never executed. It is a runtime tool, so an ordering that only
  happens in an error path nobody exercised is an ordering lockdep has not seen.

That last point has a practical consequence: **lockdep finds what your tests reach.** It turns
"we would have to be unlucky" into "we ran the path once", which is an enormous improvement and is
not the same as proof.

---

## B.6 The cost, and what to do about it

Lockdep is expensive. Every acquisition does bookkeeping, and the graph grows. Kernels built with
`CONFIG_PROVE_LOCKING` are measurably slower, which is why production kernels do not have it and
why `qa.config` says, in a comment, that the contrast is part of the lecture.

The working practice that follows:

* **Development and CI kernels: on.** The cost is irrelevant next to finding an ordering bug.
* **Production: off**, and accept that you are now relying on having exercised the paths.
* **Do not measure latency on a lockdep kernel.** [L12](../../L12/README.md) needs numbers, and a
  kernel doing this bookkeeping in every lock is not the kernel whose latency you care about. This
  course breaks its own rule: both of its kernels keep the validator on, and
  [L12 Appendix B.5](../../L12/appendix/b_measurement.md#b5-the-caveats-that-make-a-number-mean-something)
  says what that costs the figures it publishes.

And one interaction worth remembering from [L04](../../L04/appendix/a_modules.md): **loading a
proprietary module switches lockdep off for the rest of that boot**, with the single line
`Disabling lock debugging due to kernel taint`. A development kernel with a proprietary module on
it has silently lost the tool you would use to find the deadlock that module might be causing.

---

## B.7 Practical discipline

Ordered by how much they are worth:

1. **Hold locks for as little code as possible.** A short critical section cannot contain a call
   into something that takes another lock, which is where orderings come from.
2. **Do not call out of a critical section into unfamiliar code.** You do not know what it locks.
   This is why callbacks are usually invoked with no lock held.
3. **Write the order down**, in a comment beside the lock definitions, the first time a second
   lock appears.
4. **Prefer one lock.** Two locks are more than twice the trouble of one, and a driver's data is
   usually small enough that one lock protecting all of it costs nothing measurable.
5. **Run the error paths.** Lockdep only sees what executes, and error paths are where the unusual
   orderings live.

---
