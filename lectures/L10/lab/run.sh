#!/bin/sh
#
# L10 on-target test: the driver stops being told where its hardware is.
#
# The deliverable is qa_platform.c, specified in L10's Appendix C.6: the L08 driver rewritten as a
# platform driver that probes off the device tree node, with no address and no interrupt number
# anywhere in its source, and with every acquisition managed by devm_.
#
# The unbind and rebind at the end are the point of the whole lecture. They are what proves that
# devm_ is attached to the device's binding rather than to the module's lifetime, which is the
# claim L06 made and could not demonstrate.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

DEV=/sys/bus/platform/devices/c000000.qa-dev
DRV=/sys/bus/platform/drivers/qa_platform

echo "L10: the device model and the device tree"
cd /lab || exit 1

if [ ! -f qa_platform.ko ]; then
    echo "  Not started: /lab/qa_platform.ko does not exist."
    echo "  Write qa_platform.c as specified in L10 Appendix C.6, in lectures/L10/lab/."
    echo "L10: not started"
    exit 77
fi

# --- the device exists before any driver does ----------------------------------------------------
[ -d "$DEV" ]
check $? "a platform device exists for the node, without any driver"
echo "        $(tr -d '\0' < $DEV/of_node/compatible) at $(basename $DEV)"

[ ! -e "$DEV/driver" ]
check $? "and nothing is bound to it yet"

# --- loading the module binds it -----------------------------------------------------------------
insmod ./qa_platform.ko 2>/tmp/err
check $? "qa_platform.ko loads"

[ -e "$DEV/driver" ]
check $? "loading the module bound the driver to the device"
if [ ! -e "$DEV/driver" ]; then
    sed 's/^/        /' /tmp/err | head -3
    echo "        Nothing called probe. Check of_match_table and the compatible string."
    echo "L10: $((failures)) failure(s)"
    exit $failures
fi
echo "        bound to $(basename "$(readlink "$DEV/driver")")"

# --- the resources came from the device tree -----------------------------------------------------
# /proc/iomem now names the *device*, not a string the driver chose. In L06 this line read
# "qa_mmio", because the driver passed that name to request_mem_region itself.
grep -q 'c000000.qa-dev' /proc/iomem
check $? "the region is claimed under the device's own name"
grep 'qa-dev' /proc/iomem | sed 's/^/        /'

grep -q 'c000000.qa-dev' /proc/interrupts
check $? "the interrupt is registered under the device's own name"
grep 'qa-dev' /proc/interrupts | sed 's/^/        /'

grep -q 'OF_FULLNAME' "$DEV/uevent"
check $? "the device's uevent records where in the device tree it came from"
grep -E 'OF_FULLNAME|OF_COMPATIBLE_0' "$DEV/uevent" | sed 's/^/        /'

# --- the sysfs attributes the driver added -------------------------------------------------------
[ -r "$DEV/interrupts" ] && [ -r "$DEV/samples" ]
check $? "the driver's sysfs attributes appeared on the device"

a=$(cat "$DEV/interrupts")
sleep 1
b=$(cat "$DEV/interrupts")
[ "$b" -gt "$a" ]
check $? "the interrupt count is climbing ($a then $b)"

# --- unbind: the whole point ---------------------------------------------------------------------
echo c000000.qa-dev > "$DRV/unbind"
[ ! -e "$DEV/driver" ]
check $? "the driver can be unbound by hand, without unloading the module"

lsmod | grep -q '^qa_platform'
check $? "and the module is still loaded"

# devm_ released everything at unbind, not at module unload. If the driver had acquired anything
# by hand without releasing it in remove, these two would still be here.
[ "$(grep -c 'c000000.qa-dev' /proc/iomem)" = "0" ]
check $? "unbinding released the memory region"

[ "$(grep -c 'c000000.qa-dev' /proc/interrupts)" = "0" ]
check $? "unbinding released the interrupt"

[ ! -e "$DEV/interrupts" ]
check $? "unbinding removed the driver's sysfs attributes"

# --- and rebind ----------------------------------------------------------------------------------
echo c000000.qa-dev > "$DRV/bind"
[ -e "$DEV/driver" ]
check $? "the driver can be bound again by hand"

[ -r "$DEV/interrupts" ]
check $? "and probe ran again, so the attributes are back"

# Asserted on lsmod: this BusyBox's rmmod exits 0 even when the unload failed.
rmmod qa_platform
! lsmod | grep -q '^qa_platform'
check $? "qa_platform.ko unloads"

[ ! -e "$DEV/driver" ]
check $? "unloading the module unbound it too"

[ -d "$DEV" ]
check $? "but the device itself is still there, waiting for a driver"

echo "L10: $failures failure(s)"
exit $failures
