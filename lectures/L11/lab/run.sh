#!/bin/sh
#
# L11 on-target test: the device is driven entirely by things you did not write.
#
# The deliverable is qa_frameworks.c, specified in L11's Appendix B: the L10 platform driver
# registering with two subsystems instead of presenting a character device of its own.
#
# Read the checks below and notice what is missing. There is no /dev node belonging to this
# driver, no ioctl of its own, and no read() it implements. Everything userspace does here goes
# through an interface that existed before the driver did, which is the whole argument.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L11: kernel frameworks"
cd /lab || exit 1

if [ ! -f qa_frameworks.ko ]; then
    echo "  Not started: /lab/qa_frameworks.ko does not exist."
    echo "  Write qa_frameworks.c as specified in L11 Appendix B, in lectures/L11/lab/."
    echo "L11: not started"
    exit 77
fi

# IIO is a module on this kernel, so the framework has to be there before a driver that uses it.
modprobe industrialio 2>/dev/null
insmod ./qa_frameworks.ko 2>/tmp/err
check $? "qa_frameworks.ko loads"
if ! lsmod | grep -q '^qa_frameworks'; then
    sed 's/^/        /' /tmp/err | head -3
    echo "        If this says Unknown symbol iio_..., industrialio is not loaded."
    echo "L11: $failures failure(s)"
    exit $failures
fi

# --- IIO ------------------------------------------------------------------------------------------
IIO=$(echo /sys/bus/iio/devices/iio:device*)
[ -d "$IIO" ]
check $? "an IIO device appeared under /sys/bus/iio/devices"

[ "$(cat "$IIO/name" 2>/dev/null)" = "qa_dev" ]
check $? "it carries the name the driver gave it"

[ -r "$IIO/in_voltage0_raw" ]
check $? "the channel is exposed as in_voltage0_raw"
echo "        $(ls "$IIO" | tr '\n' ' ')"

# The device is in counter mode, so successive samples increase. Reading the attribute twice a
# second apart measures the sample rate without the driver providing any way to do that.
a=$(cat "$IIO/in_voltage0_raw")
sleep 1
b=$(cat "$IIO/in_voltage0_raw")
[ "$b" -gt "$a" ]
check $? "the sample value advances ($a then $b, $((b - a)) in a second)"

# --- GPIO -----------------------------------------------------------------------------------------
chip=$(ls -d /sys/bus/gpio/devices/gpiochip* 2>/dev/null | while read -r c; do
    [ "$(basename "$(readlink -f "$c/..")")" = "c000000.qa-dev" ] && basename "$c"
done)
[ -n "$chip" ]
check $? "a gpiochip appeared as a child of the platform device ($chip)"

[ -e "/sys/bus/gpio/devices/$chip/of_node" ]
check $? "and it is linked back to the device tree node it came from"

[ -c "/dev/${chip}" ]
check $? "/dev/$chip exists, which is the interface libgpiod speaks"

# GPIO_SYSFS is deliberately off; the character device replaced it. A driver that needed
# /sys/class/gpio would be a driver written against the deprecated interface.
[ ! -d /sys/class/gpio ]
check $? "there is no /sys/class/gpio, because that interface is deprecated"

if [ -x qa_gpio_test ]; then
    ./qa_gpio_test
    check $? "the standard GPIO character device ABI drives the lines"
else
    echo "  FAIL  qa_gpio_test is missing; ci/build.sh should have cross-compiled it"
    failures=$((failures + 1))
fi

# --- what is no longer there ------------------------------------------------------------------------
# The character device carried since L05 is gone. Nothing in /dev belongs to this driver except
# the one the GPIO framework created for it.
[ ! -e /dev/qa_fifo ] && [ ! -e /dev/qa_wait ]
check $? "the driver's own /dev node is gone; it presents no character device of its own"

grep -q 'c000000.qa-dev' /proc/interrupts
check $? "the interrupt is still serviced, under the device's name"

# Asserted on lsmod: this BusyBox's rmmod exits 0 even when the unload failed.
rmmod qa_frameworks
! lsmod | grep -q '^qa_frameworks'
check $? "qa_frameworks.ko unloads"

[ ! -e "/dev/${chip}" ]
check $? "and the framework removed /dev/$chip with it"

echo "L11: $failures failure(s)"
exit $failures
