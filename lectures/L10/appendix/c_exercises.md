# Appendix C - Exercises
Nine, ending with the Cross-check. Do them in order; C.6 onwards need the target running.

Where an exercise can be checked mechanically, a **Check yourself** line says how.

---

## C.1 Recall: bus, device, driver

**a)** Define each of the three, in one sentence, without naming a physical bus.

**b)** The platform bus corresponds to nothing on any schematic. What is it for, and what property
do its devices share?

**c)** On the target, `/sys/bus/platform/devices/c000000.qa-dev` exists before any driver is
loaded. Who created it, from what, and when?

**d)** Does a device have to exist before its driver is registered? Describe both orders and say
what the driver author has to do differently for each.

**e)** A device can appear under both `/sys/bus` and `/sys/class`. What is the difference in what
they group by, and which one would a program looking for "all the serial ports" use?

---

## C.2 Recall: probe and remove

**a)** `probe` can be called more than once for one loaded module. When, and what does that rule
out about where a driver keeps its state?

**b)** A driver keeps `static void __iomem *regs;` at file scope and sets it in `probe`. It works.
Describe the machine on which it stops working.

**c)** `remove` returns `void` in this kernel. Why is it not allowed to fail?

**d)** What is `-EPROBE_DEFER` for, what does the core do with it, and what is the alternative that
makes your driver depend on link order?

**e)** In `probe`, what should be done last, and why? Relate it to
[L05's](../../L05/appendix/a_character_devices.md#a3-the-table) rule about `cdev_add`.

---

## C.3 Hand calculation: reading a device tree

```text
/ {
        #address-cells = <2>;
        #size-cells = <2>;

        bus@10000000 {
                #address-cells = <1>;
                #size-cells = <1>;
                ranges = <0x1000 0x0 0x10000000 0x100000>;

                thing@2000 {
                        compatible = "acme,thing-v2", "acme,thing";
                        reg = <0x2000 0x40>;
                        interrupts = <0 45 1>;
                };
        };
};
```

**a)** How many cells does `thing`'s `reg` occupy, and how do you know?

**b)** How many cells does the bus's `ranges` occupy? Account for each.

**c)** What physical address do `thing`'s registers start at? Show the arithmetic, and note that
this `ranges` does not start its child range at zero.

**d)** `compatible` has two entries. Which does the kernel prefer? What is the second for?

**e)** Decode `interrupts = <0 45 1>` for a GIC. What hardware interrupt number is that, and what
trigger type?

**f)** A driver's `of_match_table` contains only `"acme,thing"`. Does it bind? What if it contained
only `"acme,thing-v3"`?

---

## C.4 Hand calculation: what the helpers do

For each, say what it reads out of the device tree and what it returns on failure.

**a)** `devm_platform_ioremap_resource(pdev, 0)`

**b)** `platform_get_irq(pdev, 0)`

**c)** `of_property_read_u32(node, "fifo-depth", &v)`

Then:

**d)** One of the three returns a negative error code as an `int`, one returns an error packed into
a pointer, and one returns zero for success. Say which is which and how each is checked.

**e)** A driver checks `if (!irq)` after `platform_get_irq`. On which boards does that work, and on
which does it silently do the wrong thing?

**f)** `devm_platform_ioremap_resource` replaces four separate calls from
[L06](../../L06/appendix/b_mmio_and_resources.md#b7-the-whole-sequence-and-its-unwind). Name all
four.

---

## C.5 Design: what belongs in a device tree

For each, say whether it belongs in the device tree, in a module parameter, or neither, and why.

**a)** The physical address of the device's registers.

**b)** Which interrupt it raises.

**c)** How deep the driver's software FIFO should be.

**d)** The number of hardware channels the chip has.

**e)** Whether to enable verbose debugging.

**f)** The crystal frequency feeding the device.

**g)** The name of the `/dev` node to create.

Then: **h)** state the rule in one sentence. **i)** A device tree is an ABI. What follows for
anything you put in one, and why is that a stronger constraint than it is for a module parameter?

---

## C.6 Code: a driver that is told nothing

Rewrite your L08 driver as `lectures/L10/lab/qa_platform.c`, a platform driver.

* An `of_device_id` table matching `QA_DEV_DT_COMPATIBLE`, and `MODULE_DEVICE_TABLE`.
* `probe` uses `devm_kzalloc` for a per-device private structure, and
  `platform_set_drvdata` to attach it.
* Registers from `devm_platform_ioremap_resource`, interrupt from `platform_get_irq`, handler
  from `devm_request_irq` named with `dev_name(&pdev->dev)`.
* Check the identity register and fail with `-ENODEV` if it is wrong.
* Two read-only sysfs attributes, `interrupts` and `samples`, exposed through the driver's
  `.dev_groups` so that the core adds and removes them for you.
* `remove` stops the device. It must do nothing else.
* Use `dev_info` and `dev_err`, not `pr_info`.

**There must be no address and no interrupt number anywhere in the file**, and no `goto` ladder.

**Check yourself:** `make test L=L10` reports **PASSED**, with nineteen checks. `grep -c '0xC000'`
on your source returns 0.

**a)** Compare the line count against your L08 driver. Where did the difference go?

**b)** Your L06 driver named its own region and the entry in `/proc/iomem` read `qa_mmio`. What does
it read now, and who chose that name?

**c)** Change one character of the compatible string in your `of_match_table` and reload. What
happens, what does `dmesg` say, and how would you have diagnosed it without knowing what you had
changed?

---

## C.7 Code: bind, unbind, and what `devm_` is attached to

With your driver loaded and bound:

**a)** Unbind it by hand:

```sh
echo c000000.qa-dev > /sys/bus/platform/drivers/qa_platform/unbind
```

Check `lsmod`, `/proc/iomem`, `/proc/interrupts` and the device's sysfs attributes. Which of them
changed, and is the module still loaded?

**b)** From that result, state precisely what event releases `devm_` resources. Is it module
unload? Give the evidence.

**c)** Bind it again. Did `probe` run? How do you know from the sysfs attributes alone?

**d)** Now unload the module without unbinding first. What happens, and in what order?

**e)** Why is `unbind` useful in real work? Give two uses that are not demonstrations.

**f)** A process has your device open when you unbind. What keeps the memory alive, and what is
now dangerous about any pointer your file operations still hold?

---

## C.8 Design: autoloading

This target has no udev, so modules are loaded by hand. The rest of the mechanism is present.

**a)** Name the four steps between a device appearing and its module being loaded, and say which
one is missing here.

**b)** Which of the four does `MODULE_DEVICE_TABLE` participate in? What breaks if you omit it,
and does the driver still work when loaded by hand?

**c)** Find the `MODALIAS` or `OF_COMPATIBLE_0` line in your device's `uevent`. Where did that
string come from?

**d)** Run `modinfo` on your `.ko` and find the alias it advertises. Which file would `depmod`
have collected it into?

**e)** A USB device you plug in is autoloaded by the same four steps. Where does the string its
`uevent` carries come from, and why does a device soldered to the board need a device tree to
supply it?

---

## C.9 Cross-check: an address derived three ways

You have now computed this address by hand once, in [L06](../../L06/README.md). This time you
compute it, the harness computes it, and the kernel computes it, and all three must agree.

**a) By hand, from the raw bytes.** On the target:

```sh
dt=/sys/firmware/devicetree/base
node=$(find $dt -name 'qa-dev@*' -type d | head -1)
od -An -tx1 -v "$node/reg"
od -An -tx1 -v "$(dirname "$node")/ranges"
od -An -tx1 -v "$node/interrupts"
```

Write out every cell, four bytes each, most significant first. Then compute the physical address,
the size, and the GIC hardware interrupt number.

**b) From the kernel's own naming.** Look at
`ls /sys/bus/platform/devices/ | grep qa-dev`. The device's name contains a number. Which of your
computed values is it, and what does that tell you about when the translation happened?

**c) From the driver.** Have your `probe` print what it was handed. `platform_get_resource(pdev,
IORESOURCE_MEM, 0)` gives a `struct resource` with `start` and `end`; print both, and print the
value `platform_get_irq` returned.

**d) Reconcile.** All three should agree on the address. Answer:

* Do they? If your hand figure differs, which `ranges` cell did you use as the parent base?
* The driver's IRQ number and the GIC number from **a)** are *different numbers*, and both are
  right. Explain, and say which one `/proc/interrupts` shows in which column.
* Repeat **a)** with `od -An -tx4` instead of `-tx1`. Every non-zero cell changes. Which is
  correct, what is `-tx4` doing, and why is the wrong answer plausible rather than obviously
  broken?

**e) The point of the whole lecture.** `grep` your driver's source for the address and for the
interrupt number. Neither is there.

* Where is the address, then? Name the file, the node and the property.
* Give QEMU a **second** `-device qa-dev` on the command line and boot again. Two devices appear,
  and your driver probes both:

  ```text
  qa_platform c000000.qa-dev: probed, irq 17
  qa_platform c001000.qa-dev: probed, irq 18
  0c000000-0c000fff : c000000.qa-dev qa-dev@0
  0c001000-0c001fff : c001000.qa-dev qa-dev@1000
   17:  426  0  GIC-0 144 Level  c000000.qa-dev
   18:  420  0  GIC-0 145 Level  c001000.qa-dev
  ```

  Read the two devices' `interrupts` attributes. They differ. What would have happened if your
  private structure had been a file-scope `static` rather than `devm_kzalloc`ed per device?
  Would your L06 driver, with its `base=` parameter, have coped with this at all?

* Notice the second device's address. You have seen `0xC001000` before, in
  [L06's C.9](../../L06/appendix/c_exercises.md), where reading it took the machine down. What is
  different now, and what does that say about how much a driver can infer from an address alone?
* State what would have to change in your driver to move this device to a different SoC.

**f)** A colleague proposes putting the address back in the driver as a fallback, "in case the
device tree is wrong". Give the argument against, in terms of what a device tree is and who owns
it.

---
