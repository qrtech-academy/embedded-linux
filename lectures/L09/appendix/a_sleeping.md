# Appendix A - Sleeping and Waiting
The other half of [L08](../../L08/README.md). That lecture was about the half the hardware drives:
a line goes high and a handler runs. This one is about the half the software drives: a program has
asked for data that does not exist yet, and something has to happen to it in the meantime.

[Appendix B](./b_time.md) is time, delays and timers.

The idea to carry: **sleeping is not waiting.** A sleeping task is off the run queue entirely and
costs nothing; a spinning task is on it and costs a CPU. The whole of this appendix is machinery
for getting into the first state safely.

---

## A.1 What sleeping is

A task has a state. The ones that matter:

| State                  | `ps` shows | On the run queue | Woken by                       |
| ---------------------- | ---------- | ---------------- | ------------------------------ |
| `TASK_RUNNING`         | `R`        | Yes              | It is already running or ready |
| `TASK_INTERRUPTIBLE`   | `S`        | **No**           | An explicit wake, or a signal  |
| `TASK_UNINTERRUPTIBLE` | `D`        | **No**           | An explicit wake only          |

To sleep, a task sets its state to something other than `TASK_RUNNING` and calls `schedule()`. The
scheduler then does not consider it again until something sets it back to `TASK_RUNNING`. That is
all a wait queue is built out of.

**Use `TASK_INTERRUPTIBLE` in a driver, essentially always.** The uninterruptible state exists for
short, uninterruptible hardware operations, and a task stuck in `D` cannot be killed, not even with
signal 9, which is [L02's](../../L02/appendix/a_shell_and_processes.md#a5-processes-the-tree-and-the-states)
observation arriving with a cause.

---

## A.2 The wrong version, and why it is wrong every time

The obvious implementation of "wait until there is data":

```c
/* WRONG */
while (fifo_empty())
        schedule();
```

Two things are wrong. It never sets its state, so it stays `TASK_RUNNING` and the scheduler keeps
picking it: this is a busy-wait with extra steps, and it burns a CPU doing nothing. And it is on no
wait queue, so even if it did sleep, no wake-up could ever find it.

The obvious fix is worse, because it looks right. Take it that the reader has already joined the
queue the handler wakes; the snippet leaves that line out, because what is wrong is elsewhere:

```c
/* WRONG, and subtly */
if (fifo_empty()) {
        set_current_state(TASK_INTERRUPTIBLE);
        schedule();
}
```

Consider the interleaving. The reader evaluates `fifo_empty()` and finds it true. **The interrupt
fires here.** The handler adds data and calls `wake_up_interruptible`, which finds nothing asleep
on the queue and does nothing at all. The reader then sets its state and calls `schedule()`, and
sleeps waiting for a wakeup that has already happened: until the next one, if there is a next one,
and forever if there is not.

**This is the lost wakeup, and it is not a rare race.** The window is two instructions wide, but
with an interrupt arriving every millisecond it is hit within seconds. It is not the kind of bug
that waits for production; it is the kind that fails in your first test and then works on the
second, which is worse.

![A sequence diagram with a lane for the reader and a lane for the handler. The reader tests fifo_empty and finds it true; the handler then pushes a sample and calls wake_up, which finds nothing asleep to wake; the reader then sets its state and calls schedule, and sleeps until the next wake, if one ever comes.](./images/lost_wakeup.png)

---

## A.3 What the macro actually does

`wait_event_interruptible` is the correct version, and reading its expansion is worth more than
memorising its usage. From `include/linux/wait.h`, abridged:

```c
for (;;) {
        long __int = prepare_to_wait_event(&wq_head, &__wq_entry, state);

        if (condition)
                break;

        if (___wait_is_interruptible(state) && __int) {
                __ret = __int;
                goto __out;
        }

        schedule();
}
finish_wait(&wq_head, &__wq_entry);
```

Three things close the window in A.2, in this order:

1. **`prepare_to_wait_event` first.** It adds the task to the queue *and* sets its state, before
   the condition is looked at. From that moment a `wake_up` cannot be missed: it will find this
   task on the queue and set it runnable.
2. **The condition is tested after being queued.** If the data arrived during step 1, the test
   sees it and breaks out without ever sleeping.
3. **It is a loop.** After `schedule()` returns, the condition is tested again.

Step 3 is why the macro takes a *condition* and not a flag. **A wake does not mean the condition
is true.** Several readers may be woken and the first to run may take all the data; a wake may be
spurious. The sleeper must re-check, and the loop does it for you.

Two consequences for how you write the condition: it is evaluated **many times**, so it must be
cheap and free of side effects, and it is evaluated **from the waiting task's context**, so it must
be safe to call there.

---

## A.4 Using it

```c
static DECLARE_WAIT_QUEUE_HEAD(qa_readq);

/* the reader */
for (;;) {
        n = take_the_data();        /* under the lock; 0 if there was none */
        if (n)
                break;
        if (file->f_flags & O_NONBLOCK)
                return -EAGAIN;
        if (wait_event_interruptible(qa_readq, !fifo_empty()))
                return -ERESTARTSYS;
}

/* the interrupt handler */
if (got_data)
        wake_up_interruptible(&qa_readq);
```

**The reader loops for the same reason the macro does.** A wake says there was data when the waker
looked; with two readers, the other may have taken it by the time this one runs. A reader that
takes nothing goes back to waiting, because returning 0 would tell its caller the device had
finished.

| Function                    | Wakes                                         |
| --------------------------- | --------------------------------------------- |
| `wake_up_interruptible`     | Tasks in `TASK_INTERRUPTIBLE`                 |
| `wake_up`                   | Those and `TASK_UNINTERRUPTIBLE`              |
| `wake_up_interruptible_all` | The same, and every exclusive waiter, not one |

An *exclusive* waiter is one that asked, with `wait_event_interruptible_exclusive`, to be woken on
its own. The first two wake every other waiter on the queue and at most one exclusive one.

**Waking is safe from interrupt context** and does not sleep, which is what makes this the natural
join between L08's handler and this lecture's reader.

**A name to avoid.** Calling the queue `readq` does not compile: the kernel already has `readq`,
the 64-bit MMIO accessor from [L06](../../L06/appendix/b_mmio_and_resources.md#b4-readl-and-writel),
and the error is `'readq' redeclared as different kind of symbol`. The kernel namespace is flat and
short names are taken; prefix yours with the driver's name.

---

## A.5 Blocking `read()`, properly

Four cases, and a driver has to get all four right:

| Situation                   | Return                    |
| --------------------------- | ------------------------- |
| Data available              | The bytes, and how many   |
| Empty, blocking             | Sleep until there is data |
| Empty, `O_NONBLOCK`         | **`-EAGAIN`**             |
| Signal arrives while asleep | **`-ERESTARTSYS`**        |

**Never 0.** Zero means end of file, which is [L05's](../../L05/appendix/a_character_devices.md)
subject and the reason that lecture returned `-EAGAIN` unconditionally. This lecture upgrades that:
`-EAGAIN` is now the answer only for a caller who asked for it with `O_NONBLOCK`.

### `-ERESTARTSYS`

`wait_event_interruptible` returns non-zero when a signal arrived. The driver returns
`-ERESTARTSYS`, which never reaches userspace: the kernel sees it and either restarts the system
call transparently or converts it to `-EINTR`, depending on how the signal handler was installed.

**Getting this wrong makes your device un-interruptible with Ctrl-C**, and users notice. A driver
that returns `-EINTR` directly is close but takes the restart decision away from the kernel; one
that ignores the return value and carries on has a reader that cannot be killed.

### Toggling `O_NONBLOCK`

Worth knowing because it catches people writing tests. A descriptor's blocking behaviour is a
property of the open file, changeable at run time:

```c
int flags = fcntl(fd, F_GETFL, 0);
fcntl(fd, F_SETFL, flags | O_NONBLOCK);
```

The course's own tester needs this: draining a blocking descriptor attached to a device that
produces a sample every millisecond never terminates, because there is always more data a
millisecond from now.

---

## A.6 `poll`, and what it buys

Two lines of driver code, and every multiplexing interface in userspace works on your device.

```c
static __poll_t qa_poll(struct file *file, struct poll_table_struct *wait)
{
        poll_wait(file, &qa_readq, wait);
        return fifo_empty() ? 0 : (EPOLLIN | EPOLLRDNORM);
}
```

**`poll_wait` does not wait.** It registers the caller's interest in your wait queue and returns
immediately; the sleeping is done by the `select`/`poll`/`epoll` machinery above you, on all the
descriptors at once. Your function is then called a second time after any wake, to ask again.

So the function must do exactly two things: register on every queue that could make it ready, and
return a mask describing readiness *now*.

| Bit           | Means                                                    |
| ------------- | -------------------------------------------------------- |
| `EPOLLIN`     | Readable                                                 |
| `EPOLLRDNORM` | Readable, normal data. Conventionally set with `EPOLLIN` |
| `EPOLLOUT`    | Writable                                                 |
| `EPOLLERR`    | An error                                                 |
| `EPOLLHUP`    | Hung up                                                  |

What it buys is that **one thread can wait on your device and a socket and a timer together**,
which is the whole architecture of most userspace daemons. Without `poll`, a program that wants to
watch your device and anything else needs a thread per descriptor.

Measured on the target: with the device running, `select` reports the descriptor readable within a
second; with the device stopped, `select` given a 300 ms timeout returns 0 after **305 ms**.

---

## A.7 Completions

For the common special case of "wait for this one thing to finish once".

```c
static DECLARE_COMPLETION(setup_done);

wait_for_completion(&setup_done);       /* the waiter */
complete(&setup_done);                  /* whoever finished */
```

A completion is a wait queue plus a "has it happened" flag, so it has no lost-wakeup problem to
solve: completing before anyone waits is fine, and the waiter returns immediately.

Use a completion for a one-shot event (initialisation finished, a DMA transfer completed) and a
wait queue for a recurring condition (data is available). Choosing a wait queue for a one-shot
means writing the flag yourself, which is where the lost wakeup comes back.

`wait_for_completion_interruptible` and `wait_for_completion_timeout` exist and are usually what
you want in a driver, for the same reasons as their `wait_event` equivalents.

---

## A.8 What may sleep, and where

The rules from [L07](../../L07/appendix/a_concurrency_and_locks.md#a7-atomic-context) and
[L08](../../L08/appendix/a_interrupts.md#a7-what-a-handler-may-not-do), stated once more because
this is the lecture where you deliberately sleep:

| Context                  | May sleep |
| ------------------------ | --------- |
| A system call, so `read` | **Yes**   |
| A threaded IRQ handler   | **Yes**   |
| A workqueue              | **Yes**   |
| A hard IRQ handler       | No        |
| Holding a spinlock       | No        |
| A timer callback         | No        |

The one that catches people in this lecture: **you may not sleep while holding a spinlock**, and
`wait_event_interruptible` sleeps. So the condition is checked under the lock, the lock is
dropped, and the wait happens outside it. Doing it the other way round deadlocks the machine, and
`CONFIG_DEBUG_ATOMIC_SLEEP` turns that into a `BUG: sleeping function called from invalid context`
rather than a hang.

---
