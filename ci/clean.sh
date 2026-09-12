#!/usr/bin/env bash
#
# Remove what the labs build, and nothing else.
#
# What this deliberately does not remove is the kernel tree, the QEMU tree and the BusyBox tree
# under build/. Between them they are several gigabytes and the better part of an hour, and a
# clean target that threw them away would be a clean target nobody dares run. "make clean" is
# for the state that gets in your way; deleting build/ by hand is for the state that is stale.
#
# Usage:
#   clean.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

removed=0

# Kbuild leaves a lot behind, and it is all reproducible from the reader's own .c file.
while IFS= read -r path; do
    rm -rf "$path"
    removed=$((removed + 1))
done < <(find "$QA_ROOT/lectures" \
    \( -name '*.o' -o -name '*.ko' -o -name '*.mod' -o -name '*.mod.c' \
       -o -name '.*.cmd' -o -name '.*.d' -o -name '*.o.d' \
       -o -name 'modules.order' -o -name 'Module.symvers' \
       -o -name '.tmp_versions' -o -name '.thinlto-cache' \
       -o -name '.qa-built-against' \) -print)

# Only the per-lecture test roots, which ci/test.sh regenerates in seconds. The patterns are
# deliberately narrow: "rootfs-*" would also match build/rootfs-rt.cpio.gz, which is the real
# PREEMPT_RT initramfs and costs a BusyBox build and a module install to recreate.
# Cross-compiled userspace test programs. They have no extension, so the inverted-whitelist
# .gitignore already keeps them untracked; this is about not leaving stale ones behind.
while IFS= read -r path; do
    rm -f "$path"
    removed=$((removed + 1))
done < <(find "$QA_ROOT/lectures" -path '*/lab/user/*' -type f -perm -u+x ! -name '*.c' -print)

for path in "$QA_BUILD"/rootfs-test-* "$QA_BUILD"/rootfs-rt-test-* "$QA_BUILD/test-logs"; do
    if [ -e "$path" ]; then
        rm -rf "$path"
        removed=$((removed + 1))
    fi
done

echo "Clean: removed $removed item(s)."
echo "Kept: the kernel, QEMU and BusyBox trees under build/. Remove build/ by hand to rebuild."
