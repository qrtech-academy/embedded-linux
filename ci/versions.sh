#!/usr/bin/env bash
#
# Every version this course pins, in one place.
#
# A course that says "build a recent kernel" is a course that stops working. Each pin below is
# quoted somewhere in the lectures, and moving one means rereading the prose that quotes it.
#
# Usage:
#   source versions.sh
#
# shellcheck disable=SC2034

# The kernel. 6.12 is a long-term-stable release, and it is the first one with PREEMPT_RT
# merged into mainline; before it, real time meant applying an out-of-tree patch series that
# lagged the kernel it patched. L12 depends on that: "make kernel RT=1" is a config change
# here, not a patch, and the lecture says so.
QA_KERNEL_VERSION="6.12.30"
QA_KERNEL_MAJOR="6"
QA_KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${QA_KERNEL_MAJOR}.x/linux-${QA_KERNEL_VERSION}.tar.xz"

# QEMU. The qa-dev device model in tools/qa-dev is written against this tag's device API;
# QOM property registration and the memory-region API both moved within recent memory, so the
# patch does not apply cleanly to an arbitrary version.
QA_QEMU_VERSION="9.2.0"
QA_QEMU_URL="https://download.qemu.org/qemu-${QA_QEMU_VERSION}.tar.xz"

# BusyBox, which is the entire userland of the target. L02 spends an appendix on what that
# choice costs, so the version a reader measures needs to be the version the appendix measured.
QA_BUSYBOX_VERSION="1.37.0"
QA_BUSYBOX_URL="https://busybox.net/downloads/busybox-${QA_BUSYBOX_VERSION}.tar.bz2"

# The container image the whole course builds inside.
QA_IMAGE="qacademy-linux:1"

# The cross toolchain prefix, and the architecture every kernel target needs.
QA_CROSS_COMPILE="aarch64-linux-gnu-"
QA_ARCH="arm64"
