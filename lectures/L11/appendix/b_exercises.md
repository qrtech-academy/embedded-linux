# Appendix B - Exercises
Nine, ending with the Cross-check. Do them in order; B.6 onwards need the target running.

Where an exercise can be checked mechanically, a **Check yourself** line says how.

---

## B.1 Recall: what a framework gives you

**a)** Your L09 driver works and presents `/dev/qa_wait`. List five things it does not have that a
subsystem would have provided.

**b)** State the trade a framework offers, in one sentence.

**c)** Name three separate costs of adding an `ioctl` of your own. One of them only appears on a
particular kind of system; which, and what kind?

**d)** `ls /sys/bus/iio/devices` finds every IIO device on a machine. What is the equivalent
command for finding every device that implements your own ioctl?

---

## B.2 Recall: the tour

For each device, name the subsystem or subsystems it belongs to.

**a)** A temperature sensor on an I2C bus.

**b)** A pin that drives an LED.

**c)** A hardware timer that resets the board if not kicked.

**d)** A rotary encoder a person turns.

**e)** A NAND flash chip.

**f)** A 16-bit ADC on SPI.

**g)** A crystal oscillator feeding three peripherals.

Then:

**h)** Two of your answers are "more than one subsystem". Which, and why is that not a
contradiction?

**i)** Which of the ten subsystems in
[Appendix A.3](./a_frameworks.md#a3-the-tour) presents **nothing** to userspace, and what is it
for instead?

---

## B.3 Hand calculation: reading an IIO device

A device exposes `in_voltage0_raw` and `in_voltage0_scale`. Reading them gives:

```text
in_voltage0_raw    = 2048
in_voltage0_scale  = 0.805664
```

**a)** What is the voltage? What are the units of `scale`, and how do you know?

**b)** Why does IIO split the value into a raw count and a scale, rather than having the driver
report volts directly?

**c)** The driver adds `IIO_CHAN_INFO_OFFSET` and it reads `-100`. Recompute the voltage. In what
order are raw, offset and scale applied?

**d)** Your device reports a plain counter with no physical meaning at all. Which of `raw`, `scale`
and `offset` should the driver implement, and what should it do about `type`?

---

## B.4 Design: the pin that is not yet a GPIO

**a)** Before a pin can be driven as a GPIO, something must have multiplexed it as one rather than
as a UART line. Which subsystem, and where is the configuration written?

**b)** Should your driver perform that multiplexing in `probe`? Give the reason.

**c)** Your device needs a clock enabled before its registers respond. Write the two calls, and say
what happens if you instead write the SoC's clock gate register directly and a second driver shares
that clock.

**d)** Your device has a regulator that must be on. Same question: what does the framework do that
a direct register write does not?

**e)** All three of these are dependencies that may not be ready when your `probe` runs. What
should `probe` return, and what does the core do with it?

---

## B.5 Design: when a character device is right

**a)** Give a device that genuinely fits no subsystem, and say why.

**b)** For it, would you register the long way as in [L05](../../L05/README.md), or use
`misc_register`? Justify it.

**c)** You add two `ioctl`s. Write down what you now owe the people who use them, and for how long.

**d)** A colleague proposes an ioctl that returns a `struct` containing a `long` and a pointer.
Name both problems.

**e)** State the difference between "no subsystem fits" and "implementing a subsystem interface
looked like more work". Which is a reason and which is an excuse?

---

## B.6 Code: register with two frameworks

Rewrite your L10 driver as `lectures/L11/lab/qa_frameworks.c`.

**IIO:**

* Allocate with `devm_iio_device_alloc`, sized for your private structure, and get it back with
  `iio_priv`.
* One channel: `IIO_VOLTAGE`, indexed, channel 0, with `IIO_CHAN_INFO_RAW`.
* `read_raw` returns the most recent sample your interrupt handler stored, as `IIO_VAL_INT`.
* Name the device `qa_dev`, mode `INDIO_DIRECT_MODE`, and register with
  `devm_iio_device_register`.

**GPIO:**

* A `gpio_chip` with eight lines, labelled with `dev_name(&pdev->dev)`, `.base = -1`, parented to
  your platform device.
* `get`, `set`, `direction_input`, `direction_output` and `get_direction`. Lines 0 to 3 are
  outputs; lines 4 to 7 are inputs wired back to them by the hardware.
* Register with `devm_gpiochip_add_data`.

**And no character device**: no `file_operations`, no `read`, no `poll` and no `/dev` node of
your own, where your L09 driver had all four.

**Check yourself:** `make test L=L11` reports **PASSED**, with twenty-two checks, of which eight
come from a GPIO test program that contains no reference to your driver.

**a)** `devm_iio_device_alloc` allocates your private structure for you. Which call from your L10
driver does that replace, and why does the framework want to own the allocation?

**b)** Your module fails to load with `Unknown symbol devm_iio_device_alloc`. What is wrong, and
what is the one command that fixes it? Why is IIO a module here at all?

**c)** `.base = -1`. What would happen on this target if you hardcoded 0 instead?

---

## B.7 Code: drive it with tools you did not write

**a)** Read `/sys/bus/iio/devices/iio:device0/name` and `in_voltage0_raw`. Which of these did you
write code to create?

**b)** Find your gpiochip under `/sys/bus/gpio/devices/`. What is its parent, and what does its
`of_node` symlink point at? Trace that path back to
[L10](../../L10/appendix/b_device_tree.md).

**c)** Run the shipped `qa_gpio_test`. Read its source. Identify every line that would have to
change if it were pointed at a completely different GPIO driver on different hardware.

**d)** `ls /sys/class/gpio` fails. Explain why that is correct rather than a missing feature, and
name the config option and the lecture that decided it.

**e)** `libgpiod`'s `gpioinfo`, `gpioget` and `gpioset` are not on this target. Would they work if
they were? What exactly would they be talking to?

---

## B.8 Design: what you gave up

**a)** Your L09 driver could block a reader until data arrived. Can a program using
`in_voltage0_raw` do that? What has been lost?

**b)** IIO has an answer to **a)**, which this lab does not implement. Find it in the kernel
documentation and describe in two sentences what it provides and what a driver must add.

**c)** Name one thing about your driver that is now *harder* than it was with a character device.

**d)** Name a device for which forcing it into IIO would produce worse code than a character
device, and say what makes it a bad fit.

**e)** The GPIO character device is on its second version, `GPIO_V2_*`. What does that tell you
about the claim that a framework removes the ABI problem? Restate the claim accurately.

---

## B.9 Cross-check: a sample rate measured through an interface that knows nothing about it

The device is in counter mode, so sample *n* has the value *n*. That makes the value readable
through IIO a running total, and the difference between two reads a measurement of something the
IIO interface has no concept of.

**a) Predict.** Your device is programmed with `PERIOD_NS=1000000`. Predict:

* the value of `in_voltage0_raw` one second after the driver loads;
* the difference between two reads taken one second apart;
* what both would be at `period_ns=500000`.

**b) Measure.** Read `in_voltage0_raw` twice, a second apart, and record both values and the
difference. Do this three times.

**c) Reconcile.** Answer each:

* The difference is not 1000. What is it, roughly, and where have you seen that number before?
  Give the lecture and the effect.
* Is the shortfall here the same as the one you measured in
  [L08](../../L08/appendix/c_exercises.md), or has the framework added something of its own?
  How would you tell?
* You have measured a sample rate using an interface that exposes no rate, no timestamp and no
  counter. What made that possible, and what would you have had to do instead if the device were
  in `QA_DEV_MODE_NOISE`?

**d) The reads are not free either.** Time a thousand reads of `in_voltage0_raw` from a shell loop
and from a C program. Which is faster, by how much, and what does that tell you about the sysfs
path as a way of moving samples?

**e)** From **d)**, state the sample rate above which reading `in_voltage0_raw` in a loop stops
being a sensible way to get data out. What does IIO offer instead, and why does it exist?

**f)** A colleague reports "the IIO driver only delivers 880 samples a second when the device is
configured for 1000". Rewrite that as an accurate sentence, naming which component each part of the
shortfall belongs to and which parts you have actually measured rather than inferred.

---
