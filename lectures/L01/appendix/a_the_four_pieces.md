# Appendix A - The Four Pieces, and How They Assemble Themselves
This appendix is the anatomy of an embedded Linux system: what is actually stored on a product's
flash, what each piece does, and the order in which they hand control to one another between power
being applied and a prompt appearing. It ends with the machine this course runs on, and an honest
account of which parts of the chain that machine skips.

---

## A.1 What is on the flash

An embedded Linux product contains four things. Three of them ship; the fourth never leaves your
build machine and determines everything about the other three.

| Piece           | Ships on the device | What it does                                               |
| --------------- | ------------------- | ---------------------------------------------------------- |
| Bootloader      | Yes                 | Brings up DRAM, finds the kernel, hands it a device tree   |
| Kernel          | Yes                 | Drives the hardware and provides the system call interface |
| Root filesystem | Yes                 | Everything that runs as a process, starting with PID 1     |
| Toolchain       | No                  | Compiles the other three; fixes the ABI they share         |

Almost every question in the rest of this course is a question about which of the four a thing
belongs to. "Why does my driver not load" is a kernel question. "Why is my binary 40 MB" is a
toolchain question. "Why does nothing happen after `Run /init as init process`" is a root
filesystem question, and the answer is nearly always that `/init` is not there, is not executable,
or is dynamically linked against a library that is not there either.

The fourth piece is the one people forget. A toolchain is not just a compiler; it is a compiler, a
C library, a linker, and a set of headers, and the choice of C library in particular is baked into
every binary you ship. You cannot mix a glibc binary and a musl root filesystem, and the failure
when you try is a loader error at run time and not a link error at build time.

---

## A.2 The boot chain

Power is applied. What happens next is a chain of five programs, each one loading the next, and
each one existing because the one before it did not have enough memory to do the next one's job.

```text
  power on
     |
     v
  [1] Boot ROM          on-chip, mask-programmed, a few kilobytes
     |                  reads a strap pin, loads the next stage into on-chip SRAM
     v
  [2] SPL / first stage  ~64 KB, runs from SRAM
     |                  its whole purpose is to initialise the DRAM controller
     v
  [3] Bootloader         ~1 MB, runs from DRAM (U-Boot, or an EFI loader)
     |                  loads the kernel and the DTB into DRAM, then jumps
     v
  [4] Kernel             decompresses itself, drives the hardware
     |                  mounts a root filesystem, then hands over
     v
  [5] /init              PID 1, the first userspace process
                        starts everything else and never exits
```

Two things about this chain are worth stating explicitly because they are the parts people get
wrong.

**The SPL exists because of a chicken-and-egg problem.** U-Boot is around a megabyte and needs DRAM
to run in. DRAM does not work until its controller has been configured, with a long sequence of
board-specific timing values. That configuration code has to run from somewhere, and the only
memory available at that point is the few tens of kilobytes of SRAM on the SoC itself. So the
build produces a second, tiny bootloader whose entire job is to set up DRAM and then load the real
one. If you have ever wondered why a board has both `MLO` and `u-boot.img`, or both `SPL` and
`u-boot`, that is why.

**The boot ROM is the only piece you cannot replace.** It is mask-programmed into the silicon. This
is what makes bricking recoverable on some boards and terminal on others: if the ROM will fall back
to loading over USB or UART when the flash is empty, you can always recover; if it will not, a bad
write to the bootloader partition turns the board into a coaster.

![The boot chain drawn as five boxes, each loading the next: ROM code on the die, SPL in SRAM, U-Boot bringing up DRAM, the kernel Image and DTB, and init as PID 1. The boxes are coloured by which of the four pieces supplies them, with the toolchain named as the piece that never ships.](./images/boot_chain.png)

---

## A.3 What the kernel is handed, and by whom

Step 3 hands step 4 two things: the kernel image, and a **device tree blob**.

The device tree matters enough to have a lecture of its own (L10), but the reason it exists belongs
here. An x86 PC can discover its own hardware: PCI is enumerable, ACPI describes the rest, and a
single kernel image boots on any machine. An embedded SoC can do none of that. There is no bus to
walk that will tell you a UART lives at `0x09000000` and raises interrupt 33. Somebody has to say
so, and the device tree is a data file that says so, kept separate from the kernel so that one
kernel image can boot many boards.

So the kernel receives, in a register, a pointer to a blob that describes the machine. It parses
it, and every driver that later probes gets its addresses from it. That is the whole idea, and L10
is about the mechanism.

---

## A.4 What this course skips, and what that costs

`make boot` runs this:

```bash
qemu-system-aarch64 -machine virt -kernel Image -initrd rootfs.cpio.gz -append "..."
```

`-kernel` skips steps 1, 2 and 3 entirely. QEMU writes the kernel image into the guest's memory,
generates a device tree describing the machine it is emulating, puts a pointer to it in the right
register, and jumps to the kernel's entry point. It is doing U-Boot's job, without being U-Boot.

**What that costs you is real and worth naming.** You will not learn here how to configure a DRAM
controller, how to write a U-Boot environment, how to recover a board whose bootloader you
overwrote, or what the serial output of a failing SPL looks like. Those are important skills and
this course does not teach them.

**What it buys is that everything after step 3 is identical.** The kernel does not know or care
whether U-Boot or QEMU put it in memory; it reads the same device tree and probes the same drivers
either way. Every lecture from L03 onwards would be word-for-word the same on a real board.

---

## A.5 The toolchain, and why your compiler is the wrong one

The target runs 64-bit ARM. Your build machine almost certainly does not. So the compiler that
produces target binaries is not `gcc` but `aarch64-linux-gnu-gcc`, and that prefix is a
**triplet**, or in this case something closer to a quadruplet:

```text
  aarch64  -  linux  -  gnu
     |          |        |
     |          |        +--  C library and ABI: gnu (glibc). Others: musl, uclibc.
     |          +-----------  operating system: linux. Others: none, elf, darwin.
     +----------------------  architecture: aarch64. Others: arm, x86_64, riscv64.
```

The single most useful demonstration of what that means is one command:

```bash
$ gcc -o hello-host hello.c && file hello-host
hello-host: ELF 64-bit LSB pie executable, x86-64, ...

$ aarch64-linux-gnu-gcc -o hello-target hello.c && file hello-target
hello-target: ELF 64-bit LSB pie executable, ARM aarch64, ...
```

Same source, same command line, two files that share nothing. The second will not run on your
laptop and the first will not run on the target.

**The sysroot is the other half.** A cross-compiler must not use your machine's libraries, because
those describe your machine. It uses a *sysroot*: a directory that mirrors the target's filesystem,
holding the target's headers and the target's libraries. A toolchain built by Buildroot or Yocto
names that directory when asked. Debian's, the one in the course's container, answers `/`:

```bash
$ aarch64-linux-gnu-gcc -print-sysroot
/
```

That is because Debian keeps the target's files beside your machine's rather than in a tree of
their own: the target's C library and headers in `/usr/aarch64-linux-gnu`, other arm64 libraries
in `/usr/lib/aarch64-linux-gnu`, and headers that are the same on every architecture in
`/usr/include`, which this compiler searches too. What it never searches is
`/usr/lib/x86_64-linux-gnu`, where your machine's own libraries are.

Two consequences follow, and both of them bite people. A library your program needs must be
installed *for the target*, not for your machine; installing `libfoo-dev` with apt installs your
machine's library, which the cross linker cannot use. And the target's glibc version sets the
oldest target root filesystem your binary will run on, because glibc guarantees that a binary runs
on a newer glibc than the one it was built against, and not on an older one.

**Kernel code has no sysroot and no C library at all.** It is compiled `-nostdinc`, against the
kernel's own headers. There is no `printf`, no `malloc`, and no `double`. L04 covers what that
environment is actually like; the point here is that the kernel does not use the C library the rest
of the toolchain is built around, which is why "the toolchain" and "the kernel" are two of the four
pieces and not one.

---

## A.6 Buildroot and Yocto, in one section

The three shipping pieces have to be built, configured and packaged together, reproducibly, by
somebody who is not you and possibly on a build server. That is a real problem and there are two
mainstream answers to it.

|               | Buildroot                         | Yocto / OpenEmbedded                        |
| ------------- | --------------------------------- | ------------------------------------------- |
| Model         | One `make`, one config, one image | Layers of recipes, one per package          |
| Output        | A root filesystem image           | A root filesystem image, and a package feed |
| Rebuild cost  | Often a full rebuild              | Incremental, per recipe                     |
| Learning cost | An afternoon                      | Weeks                                       |
| Fits          | Small, fixed products             | Products with variants, updates, or a team  |

The honest summary is that Buildroot is a build system and Yocto is a distribution builder, and
teams pick the wrong one about half the time. A product with one variant and no field updates does
not need Yocto's machinery. A product with four hardware variants, two customers and an OTA update
channel will outgrow Buildroot's single-config model.

**This course uses neither.** Its root filesystem is one statically linked BusyBox and a shell
script, assembled by [`ci/rootfs.sh`](../../../ci/rootfs.sh) in about a hundred lines. That is not
what a product does, and it is not held up as an example of what to do. It is the smallest thing
that boots, which makes it the right thing to learn on, and it means every file on the target is
one you can account for.

---

## A.7 The machine this course builds

Running `make kernel`, `make qemu`, `make rootfs` and `make boot` produces this:

| Piece           | What it is here                                       | Size    |
| --------------- | ----------------------------------------------------- | ------- |
| Bootloader      | None. QEMU's `-kernel` does the job                   | 0       |
| Kernel          | `Image`, Linux 6.12.30, cross-built for arm64         | ~24 MB  |
| Root filesystem | `rootfs.cpio.gz`: BusyBox, static, plus three modules | ~1.3 MB |
| Toolchain       | `aarch64-linux-gnu-gcc` 12, from the container image  | n/a     |

The two sizes are worth staring at for a moment, because the ratio is the wrong way round from what
most people expect. **The kernel is roughly twenty times the size of the entire userland.** That is
not because the kernel is bloated in some abstract sense; it is because the configuration it was
built from still enables a great deal that this machine cannot use. Finding out how much, and
taking it out, is L03's lab.

The exercises in [Appendix C](./c_exercises.md) ask you to produce both of those numbers yourself
rather than take them from this table, and the Cross-check asks you to predict one of them before
you measure it.

---

## A.8 Where to look on a running system

Once `make boot` gives you a prompt, four files tell you which of the four pieces you are looking
at. L02 is about this in earnest; these are the ones worth knowing today.

```text
/proc/version      the kernel: version, compiler, and when it was built
/proc/cmdline      what the bootloader (here, QEMU) told the kernel at handover
/proc/iomem        the physical address map, as the kernel understands it
/sys/firmware/devicetree/base
                   the device tree, unpacked into a directory per node
```

That last one is worth a minute now even though L10 is where it is explained. The device tree the
kernel was handed is exposed as a directory tree, one directory per node and one file per property.
The device this course is built around appears there:

```text
/sys/firmware/devicetree/base/platform-bus@c000000/qa-dev@0/
    compatible      "qacademy,qa-dev-1.0"
    reg             00 00 00 00 00 00 10 00
    interrupts      00 00 00 00 00 00 00 70 00 00 00 04
```

Nobody typed those numbers. QEMU chose where to put the device, wrote the node, and handed the
result to the kernel, which is exactly what a bootloader does on a real board. Reading them back
and working out what physical address they describe is L06's Cross-check.

---
