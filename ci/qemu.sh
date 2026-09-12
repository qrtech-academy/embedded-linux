#!/usr/bin/env bash
#
# Build qemu-system-aarch64 with the qa-dev device model compiled in.
#
# The device model lives in tools/qa-dev as ordinary source, and this script grafts it onto a
# pinned QEMU release. The graft is done by tools/qa-dev/integrate.py rather than by a context
# diff, deliberately: a .patch against four files in a tree this size is the sort of thing that
# fails on a whitespace change and leaves a reader staring at a reject file. The Python edits
# are idempotent, they check for what they expect before changing it, and they say which of the
# four steps was already done.
#
# Usage:
#   qemu.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
qa_need_container "$0" "$@"

tree="$QA_BUILD/qemu-$QA_QEMU_VERSION"
tarball="$QA_BUILD/qemu-$QA_QEMU_VERSION.tar.xz"

mkdir -p "$QA_BUILD"

if [ ! -d "$tree" ]; then
    if [ ! -f "$tarball" ]; then
        echo "Downloading qemu-$QA_QEMU_VERSION."
        wget --quiet --show-progress --output-document "$tarball.part" "$QA_QEMU_URL" \
            || qa_die "download failed. The URL is in ci/versions.sh."
        mv "$tarball.part" "$tarball"
    fi
    echo "Extracting qemu-$QA_QEMU_VERSION."
    tar --extract --file "$tarball" --directory "$QA_BUILD"
fi

# The device model is written against one release's device API. QOM class-init, the Resettable
# phase signature and the property-array form have all moved recently, so building against a
# different tag produces a wall of errors that look like the device is wrong when it is the
# version that is wrong. Say so first.
actual="$(cat "$tree/VERSION" 2>/dev/null || echo unknown)"
if [ "$actual" != "$QA_QEMU_VERSION" ]; then
    qa_die "build/qemu-$QA_QEMU_VERSION contains QEMU $actual. tools/qa-dev is written against
       $QA_QEMU_VERSION; remove the tree and re-run, or move the pin in ci/versions.sh and
       expect to fix the device model."
fi

echo "Integrating qa-dev into the QEMU tree."
python3 "$QA_ROOT/tools/qa-dev/integrate.py" "$tree" || qa_die "integration failed."

if [ ! -f "$tree/build/build.ninja" ]; then
    echo "Configuring QEMU. Only the aarch64 system emulator is built; the rest of QEMU is a
lot of compiling for a course that never runs it."
    (
        cd "$tree"
        ./configure \
            --target-list=aarch64-softmmu \
            --disable-docs \
            --disable-guest-agent \
            --disable-tools \
            --disable-werror
    )
fi

echo "Building QEMU ($(nproc) jobs)."
make --directory "$tree/build" --jobs "$(nproc)"

binary="$(qa_qemu_binary)"
[ -x "$binary" ] || qa_die "build finished but $binary is missing."

echo
echo "qemu-system-aarch64: $binary"
"$binary" --version | head -1

# The device is useless if the machine will not accept it, and the failure mode if
# machine_class_allow_dynamic_sysbus_dev was missed is a confusing refusal at run time rather
# than at build time. Prove it here instead.
if "$binary" -machine virt -device help 2>/dev/null | grep -q "^name \"qa-dev\""; then
    echo "qa-dev is registered and accepted by the virt machine."
else
    qa_die "qemu built, but 'qa-dev' is not in '-device help'. The integration did not take."
fi
