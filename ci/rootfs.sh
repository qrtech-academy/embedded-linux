#!/usr/bin/env bash
#
# Build the BusyBox initramfs the target boots into.
#
# The whole userland of this machine is one statically linked binary and a shell script, which
# is both the smallest thing that can honestly be called a Linux system and the subject of an
# L02 appendix. Static linking is not an aesthetic choice: an initramfs with a dynamic BusyBox
# in it needs the loader and libc copied in beside it, and the first thing a reader would learn
# is how to debug a missing ld-linux-aarch64.so.1 rather than what an initramfs is.
#
# The output is a directory, build/rootfs, and a cpio archive made from it. ci/test.sh overlays
# each lecture's lab onto a copy of the directory rather than rebuilding this.
#
# Usage:
#   rootfs.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
qa_need_container "$0" "$@"

tree="$QA_BUILD/busybox-$QA_BUSYBOX_VERSION"
tarball="$QA_BUILD/busybox-$QA_BUSYBOX_VERSION.tar.bz2"
root="$(qa_rootfs_dir)"
archive="$(qa_rootfs_archive)"

# The modules this target can actually use. Everything else the kernel built is a driver for
# hardware QEMU is not emulating. Dependencies are resolved from modules.dep, so this is the
# list of things a lecture asks for by name, not the transitive closure.
QA_MODULES="${QA_MODULES:-kunit industrialio kfifo_buf}"

mkdir -p "$QA_BUILD"

export ARCH="$QA_ARCH"
export CROSS_COMPILE="$QA_CROSS_COMPILE"

command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 \
    || qa_die "no ${CROSS_COMPILE}gcc on PATH. Run 'make env'."

if [ ! -d "$tree" ]; then
    if [ ! -f "$tarball" ]; then
        echo "Downloading busybox-$QA_BUSYBOX_VERSION."
        wget --quiet --show-progress --output-document "$tarball.part" "$QA_BUSYBOX_URL" \
            || qa_die "download failed. The URL is in ci/versions.sh."
        mv "$tarball.part" "$tarball"
    fi
    echo "Extracting busybox-$QA_BUSYBOX_VERSION."
    tar --extract --file "$tarball" --directory "$QA_BUILD"
fi

if [ ! -f "$tree/.config" ]; then
    echo "Configuring BusyBox."
    make --directory "$tree" defconfig >/dev/null

    # defconfig builds dynamically and includes a few applets that need headers the cross
    # sysroot does not have. sed on a .config is crude and is what the BusyBox documentation
    # itself suggests; each line below is one applet or one switch, named.
    #
    # The two HWACCEL lines are a BusyBox 1.37.0 bug rather than a preference. Both options pull
    # in hand-written SHA routines that only exist for x86, and the build fails on any other
    # architecture with an undeclared 'sha1_process_block64_shaNI'. Nothing in this course
    # hashes anything, so they go.
    sed --in-place \
        -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
        -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
        -e 's/^CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/' \
        -e 's/^CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' \
        -e 's/^CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' \
        "$tree/.config"
    make --directory "$tree" oldconfig >/dev/null

    grep -qx 'CONFIG_STATIC=y' "$tree/.config" \
        || qa_die "BusyBox is not configured static; the initramfs would need a loader in it."
fi

echo "Building BusyBox."
make --directory "$tree" --jobs "$(nproc)" >/dev/null

echo "Assembling $root."
rm -rf "$root"
mkdir -p "$root"/{bin,sbin,etc,proc,sys,dev,tmp,lab,root}
mkdir -p "$root/sys/kernel/debug"
mkdir -p "$root/lib/modules"

cp "$tree/busybox" "$root/bin/busybox"
chmod 755 "$root/bin/busybox"
ln --symbolic busybox "$root/bin/sh"

cp "$QA_ROOT/tools/target/init" "$root/init"
chmod 755 "$root/init"

# The kernel's own modules, so a lecture can modprobe something it did not write.
#
# Not all of them. A configured kernel stages several hundred modules and this target can use
# about four; copying the lot would put tens of megabytes of drivers for hardware that does not
# exist into a RAM-backed root filesystem, which is both slow to unpack and actively misleading
# about what is on the machine. So the list below is an allowlist, and ci/rootfs.sh resolves
# each entry's dependencies out of modules.dep rather than making somebody maintain them.
#
# QA_ALL_MODULES=1 copies everything, for the one case that wants it: L03's exercise on what a
# configuration costs, which is about exactly this number.
kernel_modules="$(qa_kernel_output)/modules-install/lib/modules"
if [ ! -d "$kernel_modules" ]; then
    echo "note: no kernel modules staged yet; run 'make kernel' if a lab needs modprobe."
elif [ "${QA_ALL_MODULES:-0}" = "1" ]; then
    cp --recursive "$kernel_modules/." "$root/lib/modules/"
    echo "modules: all $(find "$root/lib/modules" -name '*.ko' | wc -l) staged (QA_ALL_MODULES=1)"
else
    release="$(basename "$(find "$kernel_modules" -maxdepth 1 -mindepth 1 -type d | head -1)")"
    src="$kernel_modules/$release"
    dst="$root/lib/modules/$release"
    mkdir -p "$dst"

    # The metadata has to come across whole: modprobe reads modules.dep and modules.alias, and a
    # pruned tree with a full modules.dep in it still works, because modprobe only opens the
    # files it actually needs.
    cp "$src"/modules.* "$dst/" 2>/dev/null || true

    # Resolve each wanted module plus everything modules.dep says it needs. The dep file lists
    # one module per line as "path/to/mod.ko: dep1.ko dep2.ko", all relative to $src.
    python3 - "$src" "$dst" "$QA_MODULES" <<'RESOLVE'
"""Copy the wanted modules, plus everything modules.dep says they need, into the initramfs."""

import os
import shutil
import sys

src, dst, wanted = sys.argv[1], sys.argv[2], sys.argv[3].split()

# modules.dep lists one module per line as "path/to/mod.ko: dep1.ko dep2.ko", relative to src.
deps = {}
with open(os.path.join(src, "modules.dep")) as handle:
    for line in handle:
        target, _, rest = line.partition(":")
        deps[os.path.basename(target.strip())] = [os.path.basename(d) for d in rest.split()]

chosen, queue = set(), [w if w.endswith(".ko") else w + ".ko" for w in wanted]
while queue:
    name = queue.pop()
    if name not in chosen:
        chosen.add(name)
        queue.extend(deps.get(name, []))

copied = set()
for directory, _, files in os.walk(src):
    for name in files:
        if name not in chosen:
            continue
        out = os.path.join(dst, os.path.relpath(directory, src))
        os.makedirs(out, exist_ok=True)
        shutil.copy2(os.path.join(directory, name), os.path.join(out, name))
        copied.add(name)

# A name in the allowlist that the kernel did not build is worth saying out loud: it means the
# config fragment and this list disagree, and the lab that wanted it will fail later and further
# away.
missing = sorted(chosen - copied)
if missing:
    print("warning: requested but not built: " + ", ".join(missing))
print(f"modules: {len(copied)} installed out of {len(deps)} built")
RESOLVE
fi

cat > "$root/etc/passwd" <<'PASSWD'
root:x:0:0:root:/root:/bin/sh
PASSWD

cat > "$root/etc/group" <<'GROUP'
root:x:0:
GROUP

# Owned by root inside the image regardless of who built it. Without --owner/--group a reader's
# own uid ends up in the archive, and every file on the target belongs to a user that does not
# exist there.
( cd "$root" && find . | cpio --create --format=newc --quiet --owner=+0:+0 ) \
    | gzip --best > "$archive"

echo
echo "initramfs: $archive ($(du -h "$archive" | cut -f1))"
