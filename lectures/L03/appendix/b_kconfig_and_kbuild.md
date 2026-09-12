# Appendix B - Kconfig and Kbuild
Configuring a kernel is choosing, from about eighteen thousand options, the few thousand that
describe your machine. This appendix is how that choice is expressed, how it is enforced, and how
the result becomes a kernel. It ends with what a single option costs, which is the Cross-check in
[Appendix C](./c_exercises.md).

---

## B.1 What a configuration is

A `.config` is a plain text file of assignments. The one this course builds has **5,725 lines**:

```text
CONFIG_ARM64=y
CONFIG_HZ=250
CONFIG_MODULES=y
CONFIG_IIO=m
# CONFIG_BTRFS_FS is not set
```

Three forms appear, and the third is not the same as absence:

| Form                    | Means                                                                                         |
| ----------------------- | --------------------------------------------------------------------------------------------- |
| `CONFIG_X=y`            | Built into the kernel image                                                                   |
| `CONFIG_X=m`            | Built as a loadable module                                                                    |
| `# CONFIG_X is not set` | Explicitly off                                                                                |
| *(absent entirely)*     | The symbol does not exist in this tree, or its dependencies are unmet so it was never offered |

That last row is the one that costs people an afternoon. If you add `CONFIG_FOO=y` to a fragment
and it does not appear in the final `.config`, the symbol was not *rejected*; it was never
*asked about*, because something it depends on is off. This course's
[`ci/kernel.sh`](../../../ci/kernel.sh) checks for exactly this after merging and warns by name,
because the failure is otherwise silent.

**The `.config` is generated, not authored.** It is produced by the Kconfig tools from the
`Kconfig` files scattered through the tree, and hand-editing it is a mistake: set one symbol
without its dependencies and the next `make` will either revert it or produce a tree that does not
build.

---

## B.2 Kconfig: the language

Every directory that offers options has a `Kconfig` file. An entry looks like this, from
`drivers/gpio/Kconfig`:

```text
config GPIO_SYSFS
	bool "/sys/class/gpio/... (sysfs interface)" if EXPERT
	depends on SYSFS
	select GPIO_CDEV # We need to encourage the new ABI
	help
	  Say Y here to add the legacy sysfs interface for GPIOs.
```

Line by line, because all five lines do something:

| Line                | Effect                                                 |
| ------------------- | ------------------------------------------------------ |
| `config GPIO_SYSFS` | Declares the symbol, which becomes `CONFIG_GPIO_SYSFS` |
| `bool "..."`        | Its type, and the prompt shown in `menuconfig`         |
| `if EXPERT`         | The *prompt* only appears when `EXPERT` is on          |
| `depends on SYSFS`  | The symbol cannot be enabled unless `SYSFS` is         |
| `select GPIO_CDEV`  | Turning this on turns `GPIO_CDEV` on too               |
| `help`              | The text `menuconfig` shows when you press `?`         |

Types are `bool` (y or n), `tristate` (y, m or n), `int`, `hex` and `string`. Only `tristate`
symbols can be modules, which is why `CONFIG_GPIOLIB` cannot be `=m` however much you would like it
to be.

### `depends on` against `select`

These two are constantly confused and behave oppositely.

**`depends on B` means "do not offer me unless B is on".** It is a precondition. If `B` is off, the
symbol is hidden and cannot be set.

**`select B` means "if I am on, force B on".** It is an imperative, and critically **it does not
check `B`'s own dependencies.** You can `select` a symbol into a state its own `depends on` line
forbids, producing a `.config` that is internally inconsistent and a build that fails somewhere
unrelated.

This is why kernel maintainers discourage `select` for anything with dependencies of its own, and
why `Documentation/kbuild/kconfig-language.rst` says it should be used only for non-visible
symbols. It is also the answer to "how did an option I never chose end up in my `.config`":
something selected it.

`GPIO_SYSFS` above is a live example of both. Adding `CONFIG_GPIO_SYSFS=y` to a fragment in this
course **does not work**, because its prompt is behind `if EXPERT` and `EXPERT` is off, so the
symbol is never offered. That is not hypothetical; it happened while this course was being written,
`ci/kernel.sh` reported `CONFIG_GPIO_SYSFS=y did not survive olddefconfig`, and the fix was to use
`CONFIG_GPIO_CDEV` instead, which is the modern interface and did not need `EXPERT` at all.

---

## B.3 The tools

| Command              | Does                                                            |
| -------------------- | --------------------------------------------------------------- |
| `make defconfig`     | The architecture's default configuration                        |
| `make menuconfig`    | Interactive, with search: press `/`                             |
| `make olddefconfig`  | Take the existing `.config`, answer new questions with defaults |
| `make savedefconfig` | Write a *minimal* config: only what differs from the defaults   |
| `make allnoconfig`   | Everything off that can be                                      |
| `make tinyconfig`    | The smallest kernel that builds                                 |

Two of these matter more than the others for real work.

**`olddefconfig` is what you run after changing anything.** It resolves the consequences of your
change: symbols that are now offered get their defaults, symbols that are now impossible get
removed. Every merge in this course is followed by one.

**`savedefconfig` is how you store a configuration.** A full `.config` is 5,725 lines, of which
perhaps a hundred are choices anyone made; the rest are defaults. `savedefconfig` strips it to the
difference, which is what `arch/arm64/configs/*_defconfig` files are and why they are readable.
Committing a full `.config` to a product repository is a mistake for the same reason as committing
generated code.

### Config fragments

A fragment is a partial `.config` merged over a base:

```bash
scripts/kconfig/merge_config.sh -m -O $OUT $OUT/.config frag1.config frag2.config
make olddefconfig
```

This is how this course configures its kernel, and the reason is maintainability: the base is
`defconfig`, and the course's own choices are three small files where each line can carry a comment
saying why it is there. [`kernel/qa.config`](../../../kernel/qa.config) names the lecture that
wanted each option; [`kernel/trim.config`](../../../kernel/trim.config) says what each removal was
for. A 5,725-line `.config` can say neither.

Later fragments override earlier ones, which is why `kernel/local.config` is merged last: it is
yours, and it wins.

![Five boxes in a row: defconfig, fragments, merge, olddefconfig and .config. A red arrow drops from olddefconfig to a callout reading CONFIG_PREEMPT_RT=y, silently discarded, because it depends on EXPERT and a symbol whose dependencies are unmet has no prompt.](./images/kconfig_flow.png)

---

## B.4 Kbuild: turning a configuration into a kernel

The build reads the same `CONFIG_` symbols, from two directions.

**In Makefiles**, the symbol chooses whether an object is built and how:

```makefile
obj-$(CONFIG_RTC_DRV_PL031) += rtc-pl031.o
```

`obj-y` is built into the kernel, `obj-m` becomes a module, and when the symbol is not set the line
adds to `obj-`, which nothing reads. So that one line expands to one of three things depending on a
symbol, and this is the entire mechanism by which a configuration selects code.

**In C**, the same symbols are available as macros, generated into
`include/generated/autoconf.h`:

```c
#ifdef CONFIG_SMP
        /* ... */
#endif

if (IS_ENABLED(CONFIG_IIO)) { ... }   /* true for =y and =m */
```

`IS_ENABLED` is preferred over `#ifdef` where possible, because the code inside it is still
compiled and type-checked even when the option is off, and then discarded by the optimiser. Code
behind `#ifdef` rots, because nobody builds it.

### The variables that matter

| Variable        | Meaning                                               |
| --------------- | ----------------------------------------------------- |
| `ARCH`          | Target architecture; selects `arch/$(ARCH)/`          |
| `CROSS_COMPILE` | Toolchain prefix, for example `aarch64-linux-gnu-`    |
| `O=`            | Build output directory, keeping the source tree clean |
| `M=`            | Build an out-of-tree module in this directory (L04)   |
| `-j`            | Parallel jobs                                         |

`O=` is worth insisting on. It puts every generated file in one directory, so two configurations
can share one source tree; this course builds `build/kernel` and `build/kernel-rt` from the same
`build/linux-6.12.30`, which is what lets L12 boot one and then the other without a second
download.

### What comes out

| Artefact                | What it is                                                         |
| ----------------------- | ------------------------------------------------------------------ |
| `vmlinux`               | The linked kernel as an ELF object, with symbols. 31,468,440 bytes |
| `arch/arm64/boot/Image` | The same, stripped and laid out for a bootloader. 24,943,104 bytes |
| `*.ko`                  | Loadable modules, scattered through the tree                       |
| `System.map`            | Symbol addresses, for decoding an oops                             |
| `*.dtb`                 | Compiled device trees, when the platform has them                  |

**The bootloader loads `Image`, not `vmlinux`.** `vmlinux` is what you point a debugger at.

`make modules_install INSTALL_MOD_PATH=<dir>` stages the modules into a directory tree and runs
`depmod` to generate `modules.dep`, which is what `modprobe` reads. This course stages into
`build/kernel/modules-install` and then copies a curated handful into the initramfs; **458 modules
are built and 3 are installed**, because the target can use three of them.

---

## B.5 Built in or module

The choice is per-symbol and it is not free either way.

|                  | `=y` built in          | `=m` module                          |
| ---------------- | ---------------------- | ------------------------------------ |
| Available at     | Boot, immediately      | After the root filesystem is mounted |
| Costs image size | Always                 | Only when loaded                     |
| Can be updated   | No, rebuild the kernel | Yes, replace the `.ko`               |
| Can be unloaded  | No                     | Yes                                  |
| Boot time        | Included               | Deferred                             |

**The rule that follows from row one is absolute:** anything needed to reach the root filesystem
cannot be a module, because the modules live on the root filesystem. The driver for your storage
controller, its bus, and the filesystem type must all be `=y`, or must be in an initramfs, which
is a root filesystem in RAM that exists precisely to break this circularity.

Everything this target uses is built in except three modules, and the target's root filesystem is
an initramfs, so the circularity never arises. On a product with real storage it is the first thing
to get right.

---

## B.6 What one option costs

The Cross-check asks you to predict this, so the method matters more than the answer.

**Step 1: find the objects.** An option builds one or more objects. `CONFIG_IKCONFIG` builds
`kernel/configs.o`, which embeds a compressed copy of the `.config` so the running kernel can be
asked what it was built with.

**Step 2: measure them.** `size -A` gives the per-section sizes:

```text
$ size -A build/kernel/kernel/configs.o
section                         size   addr
.text                             76      0
.data                              0      0
.bss                               0      0
.rodata                        34048      0
.initcall6.init                    4      0
.rodata.str1.8                    10      0
.exit.text                        40      0
.init.text                       108      0
__patchable_function_entries      16      0
.discard.addressable               8      0
.exitcall.exit                     8      0
.modinfo                         150      0
.comment                          32      0
.note.GNU-stack                    0      0
.note.gnu.property                32      0
Total                          34532
```

Four of these are the option's content: its code (`.text`), its read-only data and strings
(`.rodata`, `.rodata.str1.8`), and the 4-byte entry that has its init function called at boot
(`.initcall6.init`). That is **34,138 bytes**, and nearly all of the 34,048 is the compressed
configuration itself. The rest is 148 bytes of `__init` and `__exit` code, a few bookkeeping
entries of 8 to 16 bytes, and sections that describe the object rather than add to the kernel,
such as `.modinfo` and `.comment`; `Total` counts all of them. You can check the 34,048
independently two ways: `gzip -9 -c build/kernel/.config | wc -c` gives 33,944, and
on the running target `ls -l /proc/config.gz` shows 33,936. Three routes, agreeing to within a
fraction of a percent.

**Step 3: change one line and rebuild.**

```bash
echo '# CONFIG_IKCONFIG is not set' > kernel/local.config
make kernel
```

**Step 4: measure the result, and be specific about what you measured.** This is where the
exercise turns, because there are three artefacts and they give three different answers. Working
that out is [Appendix C.9](./c_exercises.md#c9-cross-check-what-one-config-option-costs).

The general lesson, which applies well beyond this option: **"how big is it" is not a question with
one answer.** Content, sections and image are three different measurements of the same change, they
differ by roughly a factor of two here, and quoting one without saying which is how size budgets go
wrong.

---

## B.7 Where this course's configuration comes from

Reading the three fragments is the fastest way to see the whole mechanism in use.

| File                                                | Purpose                                                   |
| --------------------------------------------------- | --------------------------------------------------------- |
| [`kernel/trim.config`](../../../kernel/trim.config) | Removes what the emulated machine cannot have             |
| [`kernel/qa.config`](../../../kernel/qa.config)     | Adds what the course needs, naming the lecture per option |
| [`kernel/rt.config`](../../../kernel/rt.config)     | `PREEMPT_RT`, for L12. Four lines                         |
| `kernel/local.config`                               | Yours. Gitignored, merged last, and the lab               |

`trim.config` is the interesting one for this lecture. arm64 `defconfig` is not a minimal
configuration; it is the union of every arm64 machine anyone has upstreamed, and it enables **44
SoC platform families**, compiling clock, pinctrl, DMA and PHY drivers for forty-four vendors'
silicon. QEMU's `virt` machine is none of them.

Turning those off is what took this course's build from **about an hour and roughly two thousand
modules** to **eighteen minutes and 458**. That is one fragment, and its effect is larger than
every other configuration decision in the course put together. It is also the answer to why the
`Image` is 24 MB and not 3 MB: it is still not a minimal kernel, and the exercises ask you to find
out how much further it could go.

---
