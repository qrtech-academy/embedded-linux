#!/bin/sh
#
# L06 on-target test: map qa-dev's registers and prove the mapping is right.
#
# The deliverable is qa_mmio.c, specified in L06's Appendix C.7: a module that takes a physical
# address as a parameter, claims the region, maps it, and reads the device's identity.
#
# The address is not discovered by the module. You work it out by hand from the device tree, which
# is the Cross-check, and pass it in. A driver that finds its own address is L10; doing it by hand
# first is what makes L10's deletion of that parameter mean something.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L06: memory, MMIO, and resource management"
cd /lab || exit 1

if [ ! -f qa_mmio.ko ]; then
    echo "  Not started: /lab/qa_mmio.ko does not exist."
    echo "  Write qa_mmio.c as specified in L06 Appendix C.7, in lectures/L06/lab/."
    echo "L06: not started"
    exit 77
fi

# The address the module should be given. Derived here from the device tree rather than written
# as a constant, so that this test does not quietly encode the answer the Cross-check asks for.
dt=/sys/firmware/devicetree/base
node=$(find $dt -name 'qa-dev@*' -type d 2>/dev/null | head -1)
if [ -z "$node" ]; then
    echo "  FAIL  no qa-dev node in the device tree; is QEMU running with -device qa-dev?"
    echo "L06: 1 failure(s)"
    exit 1
fi
parent=$(dirname "$node")

# reg and ranges are arrays of 32-bit big-endian cells, stored as raw bytes.
#
# Read them a byte at a time and reassemble. Using "od -tx4" instead is the obvious shortcut and
# is wrong: it decodes four bytes as a *native-endian* integer, so on this little-endian host
# every cell comes out byte-swapped and 0x0C000000 reads as 0x0000000C. The number looks
# plausible, which is what makes it dangerous. The Cross-check asks you to reproduce this.
cells() {
    od -An -tx1 -v "$1" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$' \
        | awk '{ b = b $0; if (length(b) == 8) { print b; b = "" } }'
}
reg_child=$(cells "$node/reg" | sed -n 1p)
reg_size=$(cells "$node/reg" | sed -n 2p)
ranges_parent=$(cells "$parent/ranges" | sed -n 3p)

base=$(printf '%d' "0x$ranges_parent")
child=$(printf '%d' "0x$reg_child")
phys=$((base + child))
size=$(printf '%d' "0x$reg_size")

printf "        device tree says: child 0x%s, parent base 0x%s, size 0x%s\n" \
    "$reg_child" "$ranges_parent" "$reg_size"
printf "        so the registers are at 0x%x, %d bytes\n" "$phys" "$size"

insmod ./qa_mmio.ko base=$phys 2>/tmp/err
status=$?
check $status "qa_mmio.ko loads with base=0x$(printf '%x' $phys)"
if [ $status -ne 0 ]; then sed 's/^/        /' /tmp/err | head -3; fi

if lsmod | grep -q '^qa_mmio'; then
    # A claimed region appears in /proc/iomem under the name the driver gave it. Before L06
    # nothing claimed this range; L01's exercise looked and found nothing.
    grep -qi 'qa_mmio\|qa-dev' /proc/iomem
    check $? "the region is claimed and named in /proc/iomem"
    grep -i 'qa_mmio\|qa-dev' /proc/iomem | sed 's/^/        /'

    # The identity register is the proof that the mapping landed on the right page.
    dmesg | grep -q 'id=0x51414456'
    check $? "the driver read QA_DEV_ID as 0x51414456"

    dmesg | grep -q 'version=0x0100'
    check $? "the driver read QA_DEV_VERSION as 0x0100"

    # A constant read correctly could still be a mapping that is read-only or aliased. Writing
    # and reading back a scratch register is what distinguishes a working mapping from a lucky one.
    dmesg | grep -q 'scratch ok'
    check $? "SCRATCH written and read back correctly"

    dmesg | tail -6 | grep -E 'qa_mmio' | sed 's/^/        /'

    # Asserted on lsmod: this BusyBox's rmmod exits 0 even when the unload failed.
    rmmod qa_mmio
    ! lsmod | grep -q '^qa_mmio'
    check $? "qa_mmio.ko unloads"

    # And releasing the region has to actually release it, or a second load fails.
    grep -qi 'qa_mmio\|qa-dev' /proc/iomem
    [ $? -ne 0 ]
    check $? "the region is released again on unload"

    insmod ./qa_mmio.ko base=$phys && rmmod qa_mmio
    check $? "the module can be loaded a second time"
fi

# A bad address must be refused rather than crashing the machine. 0 is not a valid MMIO base.
insmod ./qa_mmio.ko base=0 2>/dev/null
if lsmod | grep -q '^qa_mmio'; then
    echo "  FAIL  loading with base=0 succeeded; it should have been refused"
    failures=$((failures + 1))
    rmmod qa_mmio
else
    echo "  ok    loading with base=0 is refused rather than attempted"
fi

echo "L06: $failures failure(s)"
exit $failures
