# L11 - Kernel Frameworks

## Agenda
* What a subsystem gives you: a stable userspace ABI, existing tools, and power management.
* The cost of the shortcut: an `ioctl` you invented is an ABI you maintain forever.
* GPIO and pinctrl, and what a `gpiochip` has to provide.
* clk and regulator, and why a driver should not be turning power on by writing a register.
* I2C and SPI, and `regmap` as the thing that makes a register map declarative.
* IIO for anything that samples; input, MTD and watchdog in a sentence each.
* How to tell which subsystem a device belongs to, and what to do when the answer is none.
* Live: register with two frameworks, and drop the character device L05 and L09 built.

---

## Lecture plan
Worked in this order:

1. **The argument.** Your driver works. Since L09 it has had a `/dev` node, a `read()` and a
   `poll()`. Now name what it does not have: a way for `libgpiod` to drive it, a documented ABI,
   suspend and resume, a triggered buffer, any tool anyone has already written. A subsystem is
   where those come from, and you get them by implementing an interface rather than by writing
   them.
2. **What the shortcut costs.** The next step down that road is an `ioctl`, and its numbers are an
   ABI the moment a second program uses them. You will maintain them forever, you will get them
   wrong in a way that shows up on a 32-bit userspace over a 64-bit kernel, and nobody else's tool
   will ever speak them. Say this plainly, because "just add an ioctl" is the path of least
   resistance every time.
3. **GPIO, concretely.** A `gpio_chip` is a handful of callbacks: direction in, direction out, get,
   set. Implement them and `/dev/gpiochip0` appears, `gpioinfo` describes your lines, and
   `gpioset` drives them. Nobody wrote a `/dev` node, an `ioctl` or a tool. Do it live with
   `qa-dev`'s eight lines, four outputs wired back to four inputs, and note that the sysfs
   interface under `/sys/class/gpio` is the deprecated one and is not what to teach anyone in 2026.
4. **pinctrl, briefly.** The pin is multiplexed before it is a GPIO. Whose job that is, and why
   your driver should not be doing it.
5. **clk and regulator.** Two subsystems that exist because the answer to "turn the device on" is
   shared between drivers and refcounted across them. A driver that writes a clock gate register
   directly works until a second driver on the same clock disagrees with it.
6. **regmap.** The observation that most drivers contain the same fifty lines of read-modify-write
   over I2C or SPI, and that `regmap` replaces them with a description: register width, cacheable
   ranges, volatile registers. Show a before and after.
7. **IIO, which is where `qa-dev` belongs.** A device that produces samples at a rate is an IIO
   device. Channels, `read_raw`, and then the part worth the lecture: a buffer and a trigger get
   you a stream to userspace with no `read()` of your own, and `/sys/bus/iio/` describes the device
   to anything that wants to know.
8. **Choosing.** The question is what the device *is*, not what it does. A table, and honest
   guidance about what to do when nothing fits, which is that a character device is a legitimate
   last resort and the misc device is how to write one.
9. **Live coding.** Register `qa-dev` as an IIO device and as a `gpiochip`, with no character
   device, no `ioctl` and no `/dev` node of your own, and drive the whole thing with the shipped
   `qa_gpio_test` and `cat /sys/bus/iio/devices/iio:device0/in_voltage0_raw`.

**If the hour runs short, compress steps 4 and 5.** Do not compress step 9; deleting code that
works and getting more capability in exchange is the argument, and it does not survive being read.

---

## Before the lecture
* Read [Appendix A](./appendix/a_frameworks.md), which is the frameworks and the argument for
  them.
* Have `make test L=L10` passing.

## After the lecture
* Work through [Appendix B](./appendix/b_exercises.md), ending with the **Cross-check**: predict
  the IIO sample values from `qa-dev`'s counter mode, read them out of `/sys/bus/iio/devices/`,
  and account for the difference. You will have seen the number before.
* Make `make test L=L11` report **PASSED**. Its `run.sh` drives your device entirely with
  standard tools, and contains no reference to a `/dev` node of yours.

---

## What you should be able to do afterwards
* List four things a subsystem provides that a character device does not.
* Say why an `ioctl` you invent is a long-term cost, and name the specific portability trap.
* Implement a `gpio_chip` and drive it with `libgpiod` tools.
* Say what pinctrl is for, and why it is a separate subsystem from GPIO.
* Explain why a driver should acquire a clock rather than write a clock gate register.
* Say what `regmap` replaces, and when it is not worth it.
* Register an IIO device with one channel, and read it from sysfs.
* Given an unfamiliar device, name the subsystem it belongs to, or say honestly that none does.

---

## Questions to test yourself
* Your driver exposes a `/dev` node and two `ioctl`s. Name three things a `gpiochip` would have
  given you that you would otherwise write yourself.
* Why is `/sys/class/gpio` deprecated, and what replaced it?
* Two drivers share a clock. One disables it when it suspends. What goes wrong, and which
  subsystem exists to prevent it?
* What does `regmap` know about your device that your read-modify-write code did not?
* An IIO device with a buffer and a trigger delivers samples to userspace. Through what, given
  that you did not implement `read`?
* You have a device that genuinely fits no subsystem. What do you write, and what do you owe the
  people who will use it?

---

## Reference
* [Appendix A](./appendix/a_frameworks.md) is the material;
  [Appendix B](./appendix/b_exercises.md) contains the exercises.
* [`kernel/qa.config`](../../kernel/qa.config) enables `CONFIG_GPIO_CDEV` and not
  `CONFIG_GPIO_SYSFS`, with a comment saying why. That choice is step 3's argument in one line.
* `gpioinfo`, `gpioget` and `gpioset` are not on the target, which carries BusyBox and the
  course's own programs and nothing else. The shipped `qa_gpio_test` speaks the same ABI they do.

---

## Next lecture
* What all of this costs in latency, and how you would know.
* Where latency actually comes from, which is three places and not one.
* What `PREEMPT_RT` changes about the driver you have just finished.
* A measurement that is honest about what it cannot see.

---
