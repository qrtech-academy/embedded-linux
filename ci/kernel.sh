#!/usr/bin/env bash
#
# Download, configure and cross-build the arm64 kernel the whole course boots.
#
# The kernel source is not vendored: it is 1.5 GB of somebody else's git history, and pinning a
# tarball URL in ci/versions.sh says exactly as much about which kernel this is. What is
# vendored is the two config fragments in kernel/, because those are the course's own choices
# and every one of them is defended by a comment naming the lecture that wanted it.
#
# RT=1 merges kernel/rt.config on top, giving a PREEMPT_RT kernel in a separate output
# directory, so the two builds coexist and L12 can boot each in turn and compare them.
#
# Usage:
#   kernel.sh
#   RT=1 kernel.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
qa_need_container "$0" "$@"

tree="$(qa_kernel_tree)"
tarball="$QA_BUILD/linux-$QA_KERNEL_VERSION.tar.xz"

# Separate output directories, so "make kernel" and "make kernel RT=1" do not invalidate each
# other's object files. O= is what makes that possible without two source trees.
if [ "${RT:-0}" = "1" ]; then
    output="$QA_BUILD/kernel-rt"
    fragments=("$QA_ROOT/kernel/trim.config" "$QA_ROOT/kernel/qa.config"
               "$QA_ROOT/kernel/rt.config")
    label="PREEMPT_RT"
else
    output="$QA_BUILD/kernel"
    fragments=("$QA_ROOT/kernel/trim.config" "$QA_ROOT/kernel/qa.config")
    label="PREEMPT"
fi

# kernel/local.config is yours. It is merged last, so it overrides everything above it, and it is
# gitignored, so experimenting with a configuration does not show up as a change to the course.
# L03's lab is exactly this: put one line in it, rebuild, and measure what that line cost.
if [ -f "$QA_ROOT/kernel/local.config" ]; then
    fragments+=("$QA_ROOT/kernel/local.config")
    label="$label + local.config"
fi

mkdir -p "$QA_BUILD"

if [ ! -d "$tree" ]; then
    if [ ! -f "$tarball" ]; then
        echo "Downloading linux-$QA_KERNEL_VERSION."
        wget --quiet --show-progress --output-document "$tarball.part" "$QA_KERNEL_URL" \
            || qa_die "download failed. The URL is in ci/versions.sh; kernel.org retires old
       point releases, so if this 404s the pin needs moving and the prose that quotes it needs
       rereading."
        mv "$tarball.part" "$tarball"
    fi
    echo "Extracting linux-$QA_KERNEL_VERSION."
    tar --extract --file "$tarball" --directory "$QA_BUILD"
fi

# Refuse to run a second build in the same output directory.
#
# Two kbuild runs sharing an output tree corrupt each other's dependency files, and the way that
# surfaces is "fixdep: error opening file: .../.foo.o.d: No such file or directory" several
# minutes later, pointing at a file nobody touched. It looks like a broken source tree and is not.
# The usual way in is interrupting a build and starting another before the first has died.
#
# mkdir is atomic, which is the whole reason it is the lock rather than a file test.
mkdir -p "$output"
lock="$output/.qa-build-lock"
if ! mkdir "$lock" 2>/dev/null; then
    qa_die "another build is already running in $output (lock: $lock).
       Wait for it, or if you are certain nothing is running, remove the lock directory:
         rmdir $lock"
fi
trap 'rmdir "$lock" 2>/dev/null || true' EXIT INT TERM

export ARCH="$QA_ARCH"
export CROSS_COMPILE="$QA_CROSS_COMPILE"

command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 \
    || qa_die "no ${CROSS_COMPILE}gcc on PATH. Run 'make env', or install gcc-aarch64-linux-gnu."

mkdir -p "$output"

# Reconfigure whenever a fragment is newer than the config it produced. Merging is cheap;
# getting a stale config because a fragment changed is a genuinely confusing afternoon.
#
# The list of fragments is recorded too, and a change to the list counts. Without that, deleting
# kernel/local.config leaves its settings baked into a .config that no longer has any file
# claiming them, and the next build silently keeps a configuration nobody can see the source of.
# Adding a file is noticed by the mtime check; removing one is only noticed by this.
needs_config=0
[ -f "$output/.config" ] || needs_config=1
for fragment in "${fragments[@]}"; do
    [ "$fragment" -nt "$output/.config" ] && needs_config=1
done

fragment_list="$output/.qa-fragments"
if [ ! -f "$fragment_list" ] || [ "$(cat "$fragment_list")" != "${fragments[*]}" ]; then
    needs_config=1
fi

if [ "$needs_config" -eq 1 ]; then
    echo "Configuring $label kernel in $output."
    mkdir -p "$output"
    printf '%s' "${fragments[*]}" > "$fragment_list"
    make --directory "$tree" O="$output" defconfig
    "$tree/scripts/kconfig/merge_config.sh" -m -O "$output" "$output/.config" "${fragments[@]}"
    make --directory "$tree" O="$output" olddefconfig

    # merge_config.sh is quiet about an option it could not set, and an option silently dropped
    # is exactly the sort of thing that makes a lecture's lab fail for reasons the reader cannot
    # see. Check each one landed, and say which did not.
    missing=0
    for fragment in "${fragments[@]}"; do
        while IFS= read -r want; do
            grep -qxF "$want" "$output/.config" || {
                echo "warning: $want did not survive olddefconfig" >&2
                missing=$((missing + 1))
            }
        done < <(grep -E '^CONFIG_[A-Z0-9_]+=' "$fragment")
    done
    if [ "$missing" -gt 0 ]; then
        echo "warning: $missing option(s) from the fragments are not in the final .config." >&2
        echo "         Usually this means a dependency is off; check with:" >&2
        echo "           make --directory $tree O=$output menuconfig" >&2
    fi
fi

echo "Building $label kernel ($(nproc) jobs). This takes a while the first time."
make --directory "$tree" O="$output" --jobs "$(nproc)" Image modules

# Staged, not installed: the modules are packed into the initramfs by ci/rootfs.sh, and nothing
# in this course ever writes outside build/.
rm -rf "$output/modules-install"
make --directory "$tree" O="$output" \
    INSTALL_MOD_PATH="$output/modules-install" modules_install >/dev/null

echo
echo "$label kernel: $output/arch/arm64/boot/Image"
ls -lh "$output/arch/arm64/boot/Image" | awk '{ print "  " $5 }'
