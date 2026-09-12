# Appendix A - Character Device Drivers
This appendix is how a driver presents itself to userspace: what a device node is, how the kernel
routes a `read()` on it into your function, and what each of those functions owes its caller.
[Appendix B](./b_the_driver.md) is the specification of the driver you write.

The framing worth keeping: **a character driver is a table of callbacks and nothing else.** You
fill in a `struct file_operations`, you register it against a number, and from then on the kernel
calls you. There is no main loop, no thread of yours, and nothing running between calls.

---

## A.1 The node, and the two numbers

[L02](../../L02/appendix/b_proc_sys_dev.md#b5-dev-and-the-two-numbers) established that a device
node carries a **major** and a **minor** where a regular file has a size. Major selects the driver;
minor selects which of that driver's devices.

Three facts follow, and all three surprise people the first time.

**A node is just a name.** `mknod` writes a directory entry containing a type and two numbers, and
consults nothing. You can create a node for a driver that does not exist; the failure comes later,
at `open`, as `ENXIO`.

**A node is not unique.** Two nodes with the same major and minor are the same device. Deleting one
removes a name and nothing else.

**The driver does not create the node.** Your driver registers a *number*. Something else makes a
file appear in `/dev`. On this target that something is **devtmpfs**, prompted by your call to
`device_create`; on a desktop, **udev** sits on top and applies naming and permission rules.

---

## A.2 Getting a number

Two ways, and you want the second.

```c
/* Static: you pick the major and hope nobody else has it. */
register_chrdev_region(MKDEV(240, 0), 1, "qa_fifo");

/* Dynamic: the kernel picks, and tells you. */
alloc_chrdev_region(&devno, 0, 1, "qa_fifo");
```

Static allocation is how it was done for years and is a bad idea now: the major space is shared,
the "local/experimental" range is small, and a collision produces `-EBUSY` at load time on
somebody else's machine and not on yours. **Always allocate dynamically**, then find out what you
got:

```text
# grep qa_fifo /proc/devices
243 qa_fifo
```

243 is not a constant. It is whatever was free, it can differ between boots, and any script that
hardcodes it is wrong. This is precisely why `device_create` and udev exist: userspace should find
the device by *name*, and the number should be nobody's business.

---

## A.3 The table

```c
static const struct file_operations qa_fops = {
        .owner   = THIS_MODULE,
        .open    = qa_open,
        .read    = qa_read,
        .write   = qa_write,
};
```

**Every member is optional except `.owner`.** A missing `.read` is not an error; the kernel
substitutes a default, and for `read` the default returns `-EINVAL`. So a driver that forgets to
implement something fails at the point userspace tries to use it, with an error that says nothing
about what is missing.

**`.owner = THIS_MODULE` is what stops the module being unloaded while a process has the device
open.** It is one line, it is easy to leave out, and leaving it out means `rmmod` succeeds while a
process still holds a file whose operations have just been freed. The result is not an error
message.

Registering the table against the number takes two more calls:

```c
cdev_init(&cdev, &qa_fops);
cdev.owner = THIS_MODULE;
cdev_add(&cdev, devno, 1);
```

After `cdev_add` the device is **live**: a `read()` on a matching node reaches your function, even
though you have not finished your init function yet. Everything your callbacks depend on has to be
ready before this call, not after it. That ordering constraint is the single most common source of
a crash-on-load in a first driver.

---

## A.4 The functions, and what they owe

### `open` and `release`

```c
static int qa_open(struct inode *inode, struct file *file);
static int qa_release(struct inode *inode, struct file *file);
```

`open` returns 0 or a negative error. `release` is called when the **last** descriptor referring to
the open file is closed, which is not once per `close()`: a `fork` duplicates descriptors, and
`release` runs when the last of them goes.

`inode` identifies the device; `file` identifies this particular opening of it, and its
`private_data` is where per-open state belongs.

### `read` and `write`

```c
static ssize_t qa_read(struct file *file, char __user *buf, size_t count, loff_t *pos);
static ssize_t qa_write(struct file *file, const char __user *buf, size_t count, loff_t *pos);
```

The return value **is** the interface, and there are four cases:

| Return                | Means                                                                   |
| --------------------- | ----------------------------------------------------------------------- |
| `n`, `0 < n <= count` | This many bytes were transferred. A short count is normal, not an error |
| `0` from `read`       | **End of file.** Nothing more will ever come                            |
| `0` from `write`      | Nothing was written, and it is not an error. Rarely what you mean       |
| negative              | An error; the value is `-Exxx` and userspace sees it as `errno`         |

**The `0` row is the one this lecture exists for.** If your `read` returns 0 because it has nothing
*right now*, every reader concludes the device is finished. `cat` exits, a loop terminates, and a
program waiting for data quietly stops waiting. Nothing reports an error, because nothing went
wrong as far as userspace can tell.

Until [L09](../../L09/README.md) gives you wait queues, the honest answer when a driver has nothing
to give is **`-EAGAIN`**: "not now, ask again". L09 replaces it with blocking, and `-EAGAIN` then
becomes the answer only for `O_NONBLOCK` openers.

### Which error code

The code you return is part of the interface, because userspace acts on it.

| Code           | Use for                                                           |
| -------------- | ----------------------------------------------------------------- |
| `-EAGAIN`      | No data now; try again                                            |
| `-ENOSPC`      | No room; the write cannot be satisfied                            |
| `-EFAULT`      | A userspace pointer was bad. Return this when `copy_*_user` fails |
| `-EINVAL`      | The arguments do not make sense                                   |
| `-ENOMEM`      | An allocation failed                                              |
| `-EIO`         | The hardware failed                                               |
| `-ENODEV`      | The device is gone                                                |
| `-ERESTARTSYS` | A signal arrived while sleeping. L09                              |

![Four situations a read faces, each with an arrow to what it must return: data available gives a byte count that may be short, empty and blocking sleeps, empty with O_NONBLOCK gives -EAGAIN, and a signal gives -ERESTARTSYS. A red box below states that zero is not on the list, because it means end of file.](./images/read_contract.png)

---

## A.5 The user pointer, which is not a pointer you may follow

`buf` is an address **in the calling process's address space**. It looks like a `char *` and the
compiler will let you dereference it. Do not.

```c
memcpy(kbuf, buf, count);              /* WRONG */
if (copy_from_user(kbuf, buf, count))  /* right */
        return -EFAULT;
```

Three separate things are wrong with the first line, and it is worth having all three rather than
a rule to memorise:

* **The page may not be present.** Userspace memory is demand-paged and can be swapped or not yet
  faulted in. A direct dereference from kernel context faults where no handler expects it.
* **The address may not belong to the caller at all.** It may point into kernel memory, and a
  driver that copies from it hands kernel memory to a userspace program that asked for it. That is
  not a theoretical class of bug; it is a large fraction of real kernel CVEs.
* **The mapping can change under you.** Another thread in the same process can `munmap` it between
  your check and your copy.

`copy_to_user` and `copy_from_user` check the range, handle the fault, and **return the number of
bytes they could not copy**, so zero means success, which reads backwards the first time:

```c
if (copy_to_user(buf, kbuf, n))
        return -EFAULT;
```

They may also **sleep**, because faulting in a page can block. That is fine here and is not fine in
an interrupt handler, which is [L08](../../L08/README.md).

---

## A.6 Making a node appear

`cdev_add` makes the device reachable. It does not put anything in `/dev`.

```c
cls = class_create("qa_fifo");
device_create(cls, NULL, devno, NULL, "qa_fifo");
```

`class_create` makes a directory under `/sys/class/`, and `device_create` adds a device to it,
which emits a uevent that devtmpfs (or udev) turns into `/dev/qa_fifo`.

**Both of these have changed signature within recent memory**, which matters because most tutorials
you will find are older than the change:

* `class_create` took an owner argument until 6.4 and takes only a name now.
* `no_llseek` was a real function for decades and **does not exist in 6.12**; code using it will
  not compile.

This is [L03's](../../L03/appendix/a_the_kernel_and_its_tree.md#a2-the-one-public-interface-and-the-one-that-is-not)
"the internal API has no stability guarantee" arriving in the first driver you write. When a
tutorial does not compile, the tutorial is usually right and old.

---

## A.7 Unwinding, in reverse

Every one of those calls can fail, and each that succeeded must be undone in reverse order:

```c
        ...
        cls = class_create("qa_fifo");
        if (IS_ERR(cls)) { ret = PTR_ERR(cls); goto err_cdev; }
        ...
err_class:  class_destroy(cls);
err_cdev:   cdev_del(&cdev);
err_region: unregister_chrdev_region(devno, 1);
err_fifo:   qa_fifo_destroy(fifo);
        return ret;
```

The `goto` ladder is the kernel's house idiom for this and is not the sin it would be elsewhere:
each label undoes exactly one thing, and the order falls out of the order they were acquired. Write
it once here, because [L06](../../L06/README.md) shows you `devm_` and you delete the whole ladder.

`IS_ERR` and `PTR_ERR` are the other idiom: functions returning pointers pack an error into the
pointer rather than using a separate output parameter. `IS_ERR(p)` tests it and `PTR_ERR(p)`
extracts the `-Exxx`. Checking for `NULL` instead is a bug that survives testing, because the
failure it misses is the rare one.

---

## A.8 The shortcut

Everything above is about forty lines. The misc device is six:

```c
static struct miscdevice qa_misc = {
        .minor = MISC_DYNAMIC_MINOR,
        .name  = "qa_fifo",
        .fops  = &qa_fops,
};
misc_register(&qa_misc);
```

One shared major (10), a dynamically allocated minor, and the node created for you. **Most small
drivers should use it.** It is taught second because it hides the number, the `cdev`, the class and
the unwind path, and those are the parts worth having seen once.

---

## A.9 `ioctl`, and why to think twice

```c
long qa_ioctl(struct file *file, unsigned int cmd, unsigned long arg);
```

`cmd` is an encoded number built with `_IO`, `_IOR`, `_IOW` or `_IOWR`, packing a direction, a
type, a number and the argument's size, so that a wrong call is usually caught rather than
misinterpreted.

The argument against adding one:

* **It is an ABI you now own forever.** The moment a second program uses it, the numbers and the
  structure layout are frozen.
* **It is a portability trap.** A 32-bit process on a 64-bit kernel passes a differently sized
  structure, and handling that needs `compat_ioctl` and a struct with no implicit padding.
  Getting this wrong is a standing source of bugs.
* **There is usually a subsystem that already defines the operation.** That argument is
  [L11](../../L11/README.md), and it is the reason this course's driver eventually deletes its
  character device entirely.

Use one when the operation genuinely is device-specific and no framework covers it. Reach for
sysfs for single values and debugfs for things that are not an ABI at all.

---
