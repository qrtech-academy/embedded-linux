#!/bin/sh
#
# L01 on-target test: prove the machine you built is the machine the course expects.
#
# This lab builds no code, so what there is to check is the system itself. Every assertion below
# corresponds to one of the four pieces from Appendix A, and if one of them fails the message
# says which piece is wrong rather than that "the test failed".
#
# Run by /init when the kernel command line carries qa.test=L01. ci/test.sh reads the exit
# status off the console.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L01: the machine you built"

# The kernel. ci/versions.sh pins this, and every appendix that quotes a kernel behaviour quotes
# it for this version.
version=$(sed 's/^Linux version \([^ ]*\).*/\1/' /proc/version)
echo "  kernel  $version"
case "$version" in
    6.12.*) check 0 "kernel is the pinned 6.12 series" ;;
    *)      check 1 "kernel is the pinned 6.12 series (found $version)" ;;
esac

# The root filesystem. One statically linked binary is the whole userland, which is the point of
# the L02 appendix on what that costs.
[ -x /bin/busybox ]; check $? "BusyBox is present and executable"

# The three filesystems that are not filesystems. L02 takes these apart.
[ -d /proc/self ];              check $? "/proc is mounted"
[ -d /sys/kernel ];             check $? "/sys is mounted"
[ -c /dev/null ];               check $? "/dev is populated"

# The device tree. QEMU generated this node itself, with the address and interrupt it assigned;
# nobody typed either number anywhere. L10 is about how a driver finds it.
dt=/sys/firmware/devicetree/base
node=$(find $dt -name 'qa-dev@*' -type d 2>/dev/null | head -1)
if [ -n "$node" ]; then
    check 0 "qa-dev has a device tree node ($(basename "$node"))"
    [ -f "$node/reg" ];        check $? "the node has a reg property"
    [ -f "$node/interrupts" ]; check $? "the node has an interrupts property"

    compatible=$(tr -d '\0' < "$node/compatible")
    [ "$compatible" = "qacademy,qa-dev-1.0" ]
    check $? "compatible is qacademy,qa-dev-1.0 (found $compatible)"
else
    check 1 "qa-dev has a device tree node"
    echo "        Did QEMU get -device qa-dev? Check that 'make qemu' succeeded."
fi

# Nothing has claimed the device yet, which is correct: no driver for it exists until L06. The
# region is still listed, because the platform bus registered it.
grep -q 'qa-dev' /proc/iomem 2>/dev/null \
    && echo "  note    a driver has already claimed qa-dev's registers" \
    || echo "  note    qa-dev's registers are unclaimed, which is right until L06"

echo "L01: $failures failure(s)"
exit $failures
