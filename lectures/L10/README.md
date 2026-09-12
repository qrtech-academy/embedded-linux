# L10 - The Device Model and the Device Tree

## Agenda
* Bus, device and driver, and the match that puts the three together.
* kobjects and sysfs, and the reference counting under a device's lifetime.
* `probe` and `remove`: what may be done in each, and what must not.
* The platform bus, and what "platform device" really means.
* `of_match_table`, module aliases, and how autoloading actually happens.
* Device tree syntax: `compatible`, `reg`, `interrupts`, phandles, `#address-cells`, `ranges`.
* Bindings, dt-schema, and where the DTB enters the boot flow.
* Live: delete every address from your driver and make it probe anyway.

---

## Lecture plan
Worked in this order:

1. **Three things and a match.** A *bus* is a matching policy. A *device* is something that
   exists. A *driver* is something that knows how to handle a class of devices. The kernel keeps
   lists of the second and third per bus, and every time either list changes it tries to match
   them. `probe` is what it calls when it succeeds. Everything else in this lecture is detail.
2. **sysfs is the model, made visible.** Walk `/sys/bus/platform/devices` and
   `/sys/bus/platform/drivers`. Every device and driver directory is a kobject, every kobject is
   refcounted, and the tree the reader saw in L02 is now generated rather than mysterious.
3. **The platform bus.** For devices that cannot be discovered, which is most of an SoC. There is
   no enumeration; something has to declare that the device exists, and on an embedded system that
   something is the device tree.
4. **Device tree, properly.** `compatible` is the match key and is a list, most specific first.
   `reg` is address and size, in cells whose number the *parent* declares. `interrupts` is
   interpreted by the interrupt parent, not by the kernel generally. Phandles are pointers.
   Then `ranges`, and the translation the reader already did by hand in
   [L06](../L06/README.md); this is where it stops being an exercise and becomes the mechanism.
5. **Read the real thing.** `dtc -I dtb -O dts` on the DTB QEMU generated, and find `qa-dev` in
   it. Nobody wrote that node; QEMU emitted it, with the address and interrupt it chose. That is
   exactly what U-Boot hands a kernel on a real board.
6. **`probe`, and what changes.** `platform_get_resource`, `platform_get_irq`, and the fact that
   your driver now contains no addresses at all. Then the lifetime rules: `probe` can be called
   more than once (once per matching device), `remove` must undo exactly what `probe` did, and
   `devm_` from L06 is what makes the second of those tractable.
7. **Autoloading.** `MODULE_DEVICE_TABLE` puts the compatible strings into the module's metadata,
   `depmod` collects them into `modules.alias`, and udev matches an uevent against that and calls
   `modprobe`. Four steps, no magic, and the reader can see each one.
8. **Live coding.** Convert the L08 driver into a platform driver. Delete the address.
   Delete the interrupt number. Watch it still work, and then watch it *not* probe when you change
   one character of the compatible string.

**If the hour runs short, compress step 7.** Do not compress step 4; the cells and the translation
are where people actually get stuck.

---

## Before the lecture
* Read [Appendix A](./appendix/a_device_model.md), which is the device model.
* Read Appendix B, which is the device tree.
* Have `make test L=L09` passing.

## After the lecture
* Work through the exercises appendix, ending with the **Cross-check**: read `reg` and the parent
  `ranges` out of `/sys/firmware/devicetree` as raw bytes, work out the physical address and the
  interrupt number by hand, then print what `platform_get_resource` and `platform_get_irq`
  actually handed your `probe`, and reconcile.
* Make `make test L=L10` report **PASSED**.

---

## What you should be able to do afterwards
* Say what a bus is, in the device model's sense, without naming a physical bus.
* Follow a device from its device tree node to the `probe` call that handled it.
* Write a device tree node for a memory-mapped, interrupt-driven device.
* Say how many cells a `reg` entry has, and where that number is declared.
* Translate a child address through a `ranges` property.
* Write a `platform_driver` with an `of_match_table` and no addresses in its source.
* Explain the four steps between plugging in a device and its module being loaded.
* Say what `remove` must undo, and why `devm_` changes the answer.

---

## Questions to test yourself
* Your driver's `probe` is never called. List, in order, the five things you would check.
* `compatible` holds three strings. Which one does the kernel match on, and what are the other two
  for?
* A node has `reg = <0x1 0x2 0x3>`. Is that one region or an error? What do you need to know to
  answer?
* Why is `interrupts = <0 112 4>` meaningless without knowing the interrupt parent?
* What is the difference between `probe` failing and `probe` deferring, and when would you defer?
* You unbind a driver from a device by writing to sysfs while a process holds the device node
  open. What stops the memory being freed underneath it?

---

## Reference
* [Appendix A](./appendix/a_device_model.md) is the device model;
  [Appendix B](./appendix/b_device_tree.md) is the device tree;
  [Appendix C](./appendix/c_exercises.md) contains the exercises.
* [`tools/qa-dev/integrate.py`](../../tools/qa-dev/integrate.py) contains the code that generates
  `qa-dev`'s device tree node inside QEMU. It is short, and reading the thing that *writes* a node
  is an unusual and useful angle on reading nodes.
* [L06](../L06/README.md)'s Cross-check did this translation by hand already.

---

## Next lecture
* Why your driver should probably not be a character device at all.
* What registering with a subsystem gives you, for free, that you have been writing by hand.
* The `ioctl` you would invent, and the ABI you would then maintain forever.
* Doing without a `/dev` node of your own, and getting something better in exchange.

---
