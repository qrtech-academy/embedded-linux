# Appendix B - The Driver, Specified
This is what to build. Everything here is prose rather than code, because the code is yours; what
the course provides is the contract, the header that declares it, and the tests that check it.

Two modules, in this order:

1. **`qa_fifo.c`**, a byte ring buffer with no kernel API in it beyond allocation. Declared by
   [`lab/qa_fifo.h`](../lab/qa_fifo.h) and checked by
   [`lab/qa_fifo_kunit.c`](../lab/qa_fifo_kunit.c), both of which ship with the course.
2. **`qa_chardev.c`**, a character device that exposes one of those buffers at `/dev/qa_fifo`.
   Checked by [`lab/user/qa_fifo_test.c`](../lab/user/qa_fifo_test.c), which also ships.

Write them in that order. The first is pure logic and can be got completely right before anything
touches the kernel's device model; the second is where the kernel API is, and debugging both at
once is what makes a first driver miserable.

---

## B.1 The ring buffer

The declarations are in [`lab/qa_fifo.h`](../lab/qa_fifo.h), and the prose in that header is part
of the specification rather than a comment on it. What follows is what the header cannot say.

**The struct is opaque.** `struct qa_fifo` is declared in the header and defined only in your
`.c`. Nothing outside may look inside it, which means you choose the layout, and the tests cannot
accidentally depend on your choices. It also means every access goes through a function, which is
the habit that makes [L07's](../../L07/README.md) locking tractable: there is exactly one place
per operation to put a lock.

**Every function must be exported.** The KUnit suite is a separate module, so each function in the
header needs an `EXPORT_SYMBOL_GPL`, exactly as in [L04](../../L04/README.md). Forgetting this
produces `Unknown symbol` at `insmod` time for the *test* module, and the lab's `run.sh`
distinguishes that case from a missing KUnit framework and says which it is.

**The capacity is what you asked for.** A FIFO created with capacity 4 must hold 4 bytes, not 3.
The usual ring-buffer implementation keeps head and tail indices and cannot distinguish full from
empty, so it wastes one slot; that implementation fails
`qa_fifo_uses_its_whole_capacity`. Keeping a *level* alongside the head, rather than a tail, is one
way out and there are others.

**Short is not an error.** `qa_fifo_put` given more than fits copies what fits and returns that
count; `qa_fifo_get` on a partly filled buffer copies what is there. Neither is a failure, and the
caller is expected to read the return value. This is the same contract `read()` and `write()` have,
deliberately, so that the character device can pass its arguments almost straight through.

**Wrapping is the part that gets written wrong.** Fill, drain, and fill again: the second fill
straddles the end of the storage. An implementation that tracks positions without wrapping passes
every test in the suite up to the seventh and fails the eighth.

---

## B.2 The character device

`qa_chardev.c` registers one device, backed by one `qa_fifo`.

### What it must provide

| Member     | Required | Behaviour                                                       |
| ---------- | -------- | --------------------------------------------------------------- |
| `.owner`   | **Yes**  | `THIS_MODULE`. See [A.3](./a_character_devices.md#a3-the-table) |
| `.open`    | Yes      | Succeeds. Marks the file as a stream                            |
| `.read`    | Yes      | Below                                                           |
| `.write`   | Yes      | Below                                                           |
| `.release` | No       | There is no per-open state to release                           |

### Module parameter

One parameter, `capacity`, an `int`, default **256**, readable but not writable through sysfs. It
is the capacity of the FIFO created at load time. The userspace tester does not assume a value; it
measures what it can write and reports it, so changing the default does not break the test.

### `open`

Succeed, and mark the file as a stream. `stream_open()` does exactly this and is the one line the
function needs. Note that `no_llseek`, which most older material uses for this, **was removed and
does not exist in 6.12**.

A FIFO has no position, and a driver that silently accepts an offset is lying about what it is.
Two different things refuse one, and it is worth knowing which does what. Since 6.0 the kernel
refuses `lseek` with `-ESPIPE` on any file whose `file_operations` has no `.llseek`, which yours
does not; the userspace tester checks that, and it passes with or without `stream_open`.
**`stream_open` is what refuses the rest.** It makes `pread` and `pwrite` fail with `-ESPIPE` too,
where without it they would succeed and read the FIFO as though the offset meant something, and it
tells the VFS there is no file position at all, so the `pos` your `read` and `write` are handed is
`NULL` and must not be touched.

### `read`

Given a userspace buffer and a count:

* A `count` of 0 returns 0. There is nothing to do and it is not an error.
* **If the FIFO is empty, return `-EAGAIN`.** Not 0.
* Otherwise take up to `count` bytes out of the FIFO and copy them to userspace, and return how
  many. Fewer than `count` is normal.
* If the copy fails, return `-EFAULT`.

You cannot copy straight from the FIFO to the user pointer, because
[A.5](./a_character_devices.md#a5-the-user-pointer-which-is-not-a-pointer-you-may-follow) says you
may not touch that pointer directly. So there is a bounce buffer in the middle: allocate, take from
the FIFO into it, `copy_to_user` out of it, free. Cap the allocation at something sensible; a
program is allowed to ask for a gigabyte and you are not obliged to allocate one.

**The `-EAGAIN` is the whole lecture.** Returning 0 means end of file, and every reader believes
it. [L09](../../L09/README.md) replaces this with blocking, at which point `-EAGAIN` becomes the
answer only for a caller that opened with `O_NONBLOCK`.

### `write`

The mirror image:

* A `count` of 0 returns 0.
* **If the FIFO is full, return `-ENOSPC`.**
* Otherwise copy up to `count` bytes in from userspace and return how many were accepted.
* If the copy fails, return `-EFAULT`.

Note the asymmetry with `read`: a full FIFO is `-ENOSPC` and an empty one is `-EAGAIN`. Both say
"not now", but a reader can reasonably wait for data to arrive, whereas a writer facing a buffer
nobody is draining has a different problem. The codes are different because userspace does
different things with them.

### Init, in the right order

Five things to acquire, and the order is a constraint rather than a preference:

1. Create the FIFO.
2. Allocate a device number **dynamically**, with `alloc_chrdev_region`.
3. `cdev_init` and `cdev_add`.
4. `class_create`.
5. `device_create`, which is what makes `/dev/qa_fifo` appear.

**Everything your callbacks touch must exist before step 3.** `cdev_add` makes the device live;
from that instant a `read()` can arrive, and it will arrive before your init function has returned
if anything is watching `/dev`. Creating the FIFO after adding the cdev is a race you will not
reproduce on demand and will hit eventually.

Print the major and minor you were given at the end, with `pr_info`. You will want it, and it is
different on every boot.

### Exit, in reverse

Undo all five, in the opposite order, and free the FIFO last. Any error path in init must unwind
only what it actually acquired; see
[A.7](./a_character_devices.md#a7-unwinding-in-reverse) for the `goto` ladder that expresses this.

---

## B.3 What the tests check, and what they do not

**The KUnit suite** ([`lab/qa_fifo_kunit.c`](../lab/qa_fifo_kunit.c)) is ten cases against the ring
buffer, run inside the kernel. It says so at the top, and it is worth repeating here: **it checks
nothing about concurrency.** Every case runs on one thread. A ring buffer that passes all ten and
is destroyed by two writers passes all ten. That is [L07](../../L07/README.md).

**The userspace tester** ([`lab/user/qa_fifo_test.c`](../lab/user/qa_fifo_test.c)) is a
statically linked ARM64 program that opens the node and makes one system call at a time. It exists
as a program rather than as shell because several of the things a driver must get right are
invisible from a shell: a `read` returning 0 and a `read` returning `-EAGAIN` both produce no
output from `cat`, and only a program can look at `errno`.

Between them they do **not** check: concurrency, what happens under memory pressure, whether your
error paths unwind correctly, or whether you leak the FIFO on an init failure. Reading the tests
to find out what they are blind to is a habit worth forming, and one of the exercises asks you to
do exactly that.

---

## B.4 Working order

1. Write `qa_fifo.c` and get the KUnit suite to **10 of 10**. Nothing below matters until it does.
2. Write `qa_chardev.c` with `open`, `read` and `write`, and load it. Check `/proc/devices` for
   your major and `/dev/qa_fifo` for the node.
3. Run `./qa_fifo_test` on the target by hand before running `make test`; its output is more
   informative than the harness's summary.
4. `make test L=L05` reports **PASSED**, with eighteen checks.

If the KUnit module refuses to load with `Unknown symbol qa_fifo_create`, you have not exported
the functions. If it refuses with `Unknown symbol kunit_...`, the framework is not loaded and
`run.sh` will say so.

---
