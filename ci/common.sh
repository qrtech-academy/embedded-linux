#!/usr/bin/env bash
#
# Helpers shared by every script in ci/.
#
# Two things live here. The first is skipping: almost every target in this repo depends on
# something large that a reader may not have built yet, and the authoring rule is that a check
# which did not run must never read like one that passed. qa_skip prints why, loudly, and exits
# 0, because "you have not built the kernel yet" is not a failure.
#
# The second is the container. Everything in this course builds inside one image so that a
# reader on WSL, on a Mac and on a CI runner get the same compiler and the same QEMU. Rather
# than make every script say so, qa_need_container re-executes the calling script inside the
# image with the repo bind-mounted, and returns immediately when it is already in there.
#
# Usage:
#   source common.sh
set -euo pipefail

QA_CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QA_ROOT="$(cd "$QA_CI_DIR/.." && pwd)"
QA_BUILD="$QA_ROOT/build"

# shellcheck source=versions.sh
source "$QA_CI_DIR/versions.sh"

# Say why something did not run, and exit successfully.
#
# The wording matters. Every message names the target that would fix it, because the reader who
# sees this is usually one command away from the thing working, and a bare "skipped" sends them
# back to the README.
qa_skip() {
    echo "SKIPPED: $*"
    exit 0
}

# Say why something cannot run, and fail.
qa_die() {
    echo "error: $*" >&2
    exit 1
}

# True when running inside the course container.
qa_in_container() {
    [ -f /etc/qa-linux-env ]
}

# Re-execute the calling script inside the container, unless already there.
#
# QA_NO_CONTAINER=1 runs everything on the host instead. That is supported and used by CI,
# which is already a controlled Linux with the packages installed and gains nothing from a
# second layer; it is also the escape hatch for a reader who would rather install the toolchain
# natively. Nothing in the course requires the container except the reproducibility of it.
qa_need_container() {
    if qa_in_container || [ "${QA_NO_CONTAINER:-0}" = "1" ]; then
        return 0
    fi

    command -v docker >/dev/null 2>&1 \
        || qa_die "docker not found. Install it, or set QA_NO_CONTAINER=1 and install the
       toolchain natively; see docker/Dockerfile for the package list."

    docker image inspect "$QA_IMAGE" >/dev/null 2>&1 \
        || qa_skip "container image $QA_IMAGE not built. Run 'make env' first."

    # Allocate a terminal only when there is one to allocate. "make boot" wants an interactive
    # serial console and so needs --tty; CI, nohup and a redirected build have no tty at all and
    # docker refuses outright with "the input device is not a TTY". Deciding per invocation is
    # the difference between a target that works everywhere and one that works only when typed
    # by hand.
    local interactive=()
    if [ -t 0 ]; then
        interactive=(--interactive --tty)
    fi

    # --user keeps every file the build writes owned by the reader rather than by root, which
    # is the single most annoying thing about doing this with a container and the easiest to
    # get wrong. Everything else is bind-mounting the repo at the same path it has outside, so
    # that a path in an error message means something on both sides.
    # Every variable a target reads has to be handed across the container boundary explicitly.
    # docker starts a fresh environment, so anything set on the command line outside is simply
    # gone inside, and the script then runs with defaults while appearing to have been configured.
    # "make kernel RT=1" building a non-RT kernel and saying "PREEMPT kernel" as it did so is the
    # failure this list prevents; it is silent, and the artefact looks right.
    local passthrough=()
    local name
    for name in RT L QA_SMP QA_MEM QA_PERIOD_NS QA_TIMEOUT QA_MODULES QA_ALL_MODULES QA_KEEP; do
        if [ -n "${!name+set}" ]; then
            passthrough+=(--env "$name=${!name}")
        fi
    done

    exec docker run --rm "${interactive[@]}" \
        --user "$(id -u):$(id -g)" \
        --volume "$QA_ROOT:$QA_ROOT" \
        --workdir "$QA_ROOT" \
        --env "QA_INNER=1" \
        "${passthrough[@]}" \
        "$QA_IMAGE" \
        "$@"
}

# Where a built kernel's artefacts land. ci/kernel.sh builds with O=, so the Image is in the
# output directory and not in the source tree; RT=1 selects the second output directory, which
# is what lets L12 boot one kernel and then the other without rebuilding either.
qa_kernel_output() {
    if [ "${RT:-0}" = "1" ]; then
        echo "$QA_BUILD/kernel-rt"
    else
        echo "$QA_BUILD/kernel"
    fi
}

qa_kernel_image() {
    echo "$(qa_kernel_output)/arch/arm64/boot/Image"
}

# Fail unless the kernel has been built, naming the target that builds it.
qa_need_kernel() {
    local image
    image="$(qa_kernel_image)"

    if [ ! -f "$image" ]; then
        if [ "${RT:-0}" = "1" ]; then
            qa_skip "no PREEMPT_RT kernel at $image. Run 'make kernel RT=1' first."
        fi
        qa_skip "no kernel at $image. Run 'make kernel' first."
    fi
}

# Fail unless the patched QEMU has been built.
qa_need_qemu() {
    [ -x "$(qa_qemu_binary)" ] \
        || qa_skip "no patched qemu-system-aarch64. Run 'make qemu' first."
}

# Where the initramfs lands. RT-aware for the same reason the kernel output is: the modules in it
# are built against one kernel and carry its vermagic, so an initramfs built for the PREEMPT
# kernel cannot load its modules under PREEMPT_RT and the other way round. L12 boots both in one
# sitting, so the two have to coexist rather than overwrite each other.
qa_rootfs_dir() {
    if [ "${RT:-0}" = "1" ]; then
        echo "$QA_BUILD/rootfs-rt"
    else
        echo "$QA_BUILD/rootfs"
    fi
}

qa_rootfs_archive() {
    echo "$(qa_rootfs_dir).cpio.gz"
}

# Fail unless the initramfs has been built.
qa_need_rootfs() {
    local archive
    archive="$(qa_rootfs_archive)"

    if [ ! -f "$archive" ]; then
        if [ "${RT:-0}" = "1" ]; then
            qa_skip "no PREEMPT_RT initramfs at $archive. Run 'make rootfs RT=1' first."
        fi
        qa_skip "no initramfs at $archive. Run 'make rootfs' first."
    fi
}

# Where the patched QEMU lands.
qa_qemu_binary() {
    echo "$QA_BUILD/qemu-$QA_QEMU_VERSION/build/qemu-system-aarch64"
}

# The kernel tree.
qa_kernel_tree() {
    echo "$QA_BUILD/linux-$QA_KERNEL_VERSION"
}

# Every lecture directory that exists, as bare names: L01 L02 ...
#
# Takes an optional filter, which is what "make test L=L05" passes down. An unknown lecture is
# an error rather than an empty loop, because a typo in L= would otherwise report success
# having tested nothing.
qa_lectures() {
    local filter="${1:-}"
    local dir found=0

    for dir in "$QA_ROOT"/lectures/L[0-9][0-9]; do
        [ -d "$dir" ] || continue
        local name
        name="$(basename "$dir")"
        if [ -n "$filter" ] && [ "$name" != "$filter" ]; then
            continue
        fi
        echo "$name"
        found=1
    done

    if [ -n "$filter" ] && [ "$found" -eq 0 ]; then
        qa_die "no such lecture: $filter"
    fi
}

# The QEMU command line the whole course boots, in one place so that "make boot" and
# ci/test.sh cannot drift apart. Everything a lecture needs to vary is a variable:
#
#   QA_SMP        Number of CPUs. Two by default, because a single-CPU target quietly hides
#                 every race L07 is about; a lecture that wants the contrast can ask for one.
#   QA_MEM        Memory, in MiB.
#   QA_PERIOD_NS  qa-dev's reset sample period.
#
# -no-reboot matters for the test path: a kernel panic reboots by default, and a test harness
# watching a serial log would then watch the same failure scroll past forever instead of
# ending. With it, a panic stops the machine and the host notices.
qa_qemu_args() {
    local append="$1"

    echo "-machine virt" \
         "-cpu cortex-a72" \
         "-smp ${QA_SMP:-2}" \
         "-m ${QA_MEM:-512}" \
         "-nographic" \
         "-no-reboot" \
         "-kernel $(qa_kernel_image)" \
         "-initrd $(qa_rootfs_archive)" \
         "-device ${TYPE_QA_DEV_NAME:-qa-dev},period-ns=${QA_PERIOD_NS:-1000000}" \
         "-append \"$append\""
}
