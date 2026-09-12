#!/usr/bin/env bash
#
# Boot the target and drop to a shell on the serial console.
#
# This is the command every lecture's lab is run by hand from, and it is worth reading once
# rather than treating as an incantation. There is no disk, no bootloader and no firmware here:
# QEMU loads the kernel image into memory, loads the initramfs beside it, and jumps to it. A
# real board would have a ROM, an SPL and U-Boot in front of that, which is what L01 draws;
# -kernel is the shortcut that skips all three, and L01 says what that costs.
#
# Ctrl-A X quits. Ctrl-A C reaches the QEMU monitor.
#
# Usage:
#   boot.sh
#   RT=1 boot.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
qa_need_container "$0" "$@"

qa_need_qemu
qa_need_kernel
qa_need_rootfs

append="console=ttyAMA0 rdinit=/init"

echo "Booting $(qa_kernel_image)."
echo "Ctrl-A X quits."
echo

# shellcheck disable=SC2046,SC2086
eval exec "$(qa_qemu_binary)" $(qa_qemu_args "$append")
