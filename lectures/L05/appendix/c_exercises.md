# Appendix C - Exercises
Nine, ending with the Cross-check. Do them in order; C.6 onwards need the modules from
[Appendix B](./b_the_driver.md).

Where an exercise can be checked mechanically, a **Check yourself** line says how. Several have a
plausible wrong answer that is worth walking into before you find it.

---

## C.1 Recall: the node and the number

**a)** Your driver calls `alloc_chrdev_region` and gets major 243. A colleague hardcodes 243 in a
deployment script. Give two separate reasons that will eventually break.

**b)** What does `mknod /dev/spare c 243 0` do, given that `/dev/qa_fifo` already exists with the
same numbers? What does opening it do?

**c)** Your driver loads, `/proc/devices` shows your name against a major, and `/dev/qa_fifo` does
not exist. Which of the five init steps did you skip?

**d)** Conversely: the node exists, but opening it returns `ENXIO`. What does that tell you, and
what does it rule out?

---

## C.2 Recall: the table

**a)** `.owner = THIS_MODULE` is one line and easy to omit. Describe precisely what can go wrong
without it, in terms of what a process is holding and what `rmmod` frees.

**b)** You implement `.read` and `.write` but not `.release`. Is that a bug? What is called
instead?

**c)** You implement `.read` but not `.open`. Can userspace open the device?

**d)** After `cdev_add` returns, but before your init function returns, what can happen? Name the
ordering rule this implies.

**e)** `release` is not called once per `close()`. When is it called, and construct a case where
two `close()` calls produce one `release`.

---

## C.3 Hand calculation: return values

For each, say what the driver should return, and what the userspace program will observe.

**a)** `read(fd, buf, 100)` with 40 bytes in the FIFO.

**b)** `read(fd, buf, 100)` with the FIFO empty.

**c)** `read(fd, buf, 0)` with 40 bytes in the FIFO.

**d)** `write(fd, buf, 100)` with 60 bytes of space free.

**e)** `write(fd, buf, 100)` with the FIFO full.

**f)** `read(fd, buf, 100)` where `buf` points at an unmapped page.

Then: **g)** for **b)**, suppose the driver returns 0 instead. Write down what each of these does:
`cat /dev/qa_fifo`; a program looping `while ((n = read(fd, b, 64)) > 0)`; and a program checking
`if (n < 0) perror(...)`. Which of the three reports a problem?

---

## C.4 Hand calculation: a sequence of reads

A FIFO of capacity 8, created empty. Trace this sequence and give the return value of every call
and the FIFO's level after it.

```text
1.  write(fd, "abcdefghij", 10)
2.  read(fd, buf, 3)
3.  write(fd, "klm", 3)
4.  read(fd, buf, 100)
5.  read(fd, buf, 100)
```

**a)** Fill in the ten numbers.

**b)** After step 4, exactly which bytes are in `buf`, in order?

**c)** Step 3 succeeds even though step 1 could not fit everything. Explain why in terms of what
step 2 did.

**d)** Which steps would behave differently if the ring buffer wasted one slot to distinguish full
from empty? Give the old and the new return value for each.

---

## C.5 Design: where does this belong

For each piece of information a driver might expose, choose `read()` on the device node, a **sysfs
attribute**, **debugfs**, or an **ioctl**, and justify it in one sentence.

**a)** The stream of bytes the device produces.

**b)** The FIFO's configured capacity.

**c)** How many bytes have been dropped since load, for a field engineer to read.

**d)** A count of internal retries, useful only while you are debugging the driver.

**e)** An instruction to discard everything currently buffered.

**f)** The device's serial number.

Then: **g)** two of your answers are an ABI you will maintain indefinitely and one is explicitly
not. Which are which, and what follows for a product that ships?

---

## C.6 Code: the ring buffer

Write `lectures/L05/lab/qa_fifo.c` to the specification in
[`lab/qa_fifo.h`](../lab/qa_fifo.h) and [Appendix B.1](./b_the_driver.md#b1-the-ring-buffer).

**Check yourself:** load `qa_fifo.ko` and then `qa_fifo_kunit.ko` on the target and read `dmesg`.
The suite must report `pass:10 fail:0`. `make test L=L05` does this for you and prints the summary
line.

Two things worth knowing before you start, both of which the suite checks and neither of which is
obvious:

* A FIFO of capacity 4 must hold **four** bytes.
* Test 8 is the one that fails first for most people, and it is the eighth of ten, so seven passing
  tests tell you very little.

---

## C.7 Code: the character device

Write `lectures/L05/lab/qa_chardev.c` to [Appendix B.2](./b_the_driver.md#b2-the-character-device).

**Check yourself:** `make test L=L05` reports **PASSED** with eighteen checks, and the userspace
tester prints `qa_fifo_test: 0 failure(s)`.

**a)** Before running the tester, load your module and record the major from `/proc/devices` and
from `dmesg`. Reboot and do it again. Are they the same? Should a script rely on that?

**b)** Load the module twice without unloading. What happens, and where does the failure come from?

**c)** Deliberately omit `stream_open` from your `open` and rerun the tester. Which checks fail?
Explain the result from [B.2](./b_the_driver.md#b2-the-character-device), then find a system call
that does behave differently without `stream_open`, and say what the difference means for a program
that assumes a file offset means something.

---

## C.8 Design: reading the tests for what they miss

Read [`lab/qa_fifo_kunit.c`](../lab/qa_fifo_kunit.c) and
[`lab/user/qa_fifo_test.c`](../lab/user/qa_fifo_test.c) before answering.

**a)** The KUnit suite says at the top that it checks nothing about concurrency. Construct a
specific interleaving of two `qa_fifo_put` calls that corrupts the buffer, and say which of the ten
tests would notice. (The answer is none, which is the point.)

**b)** Name three other properties neither test suite checks. For each, say whether it would be
worth testing and how you would do it.

**c)** The userspace tester exists as a compiled program rather than as shell. Name two checks in
it that a shell script genuinely could not make, and say why.

**d)** Your driver leaks the FIFO if `class_create` fails. Would either suite catch it? What
would?

---

## C.9 Cross-check: a byte count worked out twice

Predict a sequence of return values by hand, then have the machine produce them, and reconcile.

**a) By hand.** Your FIFO has the default capacity of 256. Predict the exact return value of every
call in this sequence, and the level after each:

```text
1.  write of 200 bytes
2.  write of 100 bytes
3.  read  of 512 bytes
4.  read  of 512 bytes
5.  write of 300 bytes
```

Write down all five return values, all five levels, and the total number of bytes that will have
passed through the device when the sequence ends.

**b) By machine.** Write a short program in `lectures/L05/lab/user/` that performs exactly that
sequence against `/dev/qa_fifo` and prints each return value and `errno`. Anything you put in that
directory is cross-compiled by `make build` and copied to `/lab` on the target, so you can run it
there directly.

**c) Reconcile.** Compare your ten numbers against the machine's. Then answer:

* Step 2 is the one people get wrong. What did you predict, what happened, and which contract in
  [Appendix B.2](./b_the_driver.md#b2-the-character-device) decides it?
* Did any call return a value you had classed as an error, or an error you had classed as a value?
* The total bytes through the device: does your figure count step 2's outcome the same way the
  machine does?

**d) Now change one thing.** Reload the module with `insmod ./qa_chardev.ko capacity=128` and run
the same program without changing it. Which of the five return values change, and which do not?
Explain each unchanged one.

**e)** Your program hardcodes 256 in its predictions; the shipped `qa_fifo_test` does not, and
measures the capacity instead. Say what the shipped tester would report on a `capacity=128` device
and what yours would, and draw the general lesson about tests that encode a configuration.

**f)** A colleague reports "the device only accepted 56 bytes of my 300-byte write, it is broken".
Given the sequence above, say what actually happened, what their program should have done, and
which single line of [Appendix A.4](./a_character_devices.md#a4-the-functions-and-what-they-owe)
they had not read.

---
