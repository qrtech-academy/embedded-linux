#!/bin/sh
#
# L05 on-target test: run the shipped KUnit suite against the ring buffer you wrote, then
# exercise the character device from userspace.
#
# Two mechanisms, because there are two kinds of thing to check. KUnit runs inside the kernel and
# tests the ring buffer as pure logic. The userspace part tests what a program outside the kernel
# actually sees, which is the only place a bug in copy_to_user or in a return value can show up.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L05: character device drivers"
cd /lab || exit 1

if [ ! -f qa_fifo.ko ]; then
    echo "  skip  qa_fifo.ko not built"
    echo "L05: $failures failure(s)"
    exit $failures
fi

insmod ./qa_fifo.ko
check $? "qa_fifo.ko loads"

# --- KUnit -------------------------------------------------------------------------------------
if [ -f qa_fifo_kunit.ko ]; then
    # KUnit is a module here, not built in, so the framework has to be loaded before a suite
    # that uses it. Without this the suite fails to resolve kunit's own symbols and the error
    # looks exactly like a missing EXPORT_SYMBOL_GPL on your side, which sends you off editing
    # the wrong file.
    modprobe kunit 2>/dev/null

    insmod ./qa_fifo_kunit.ko 2>/tmp/kunit-err
    if [ $? -ne 0 ]; then
        echo "  FAIL  qa_fifo_kunit.ko would not load"
        sed 's/^/        /' /tmp/kunit-err
        # Say which of the two causes it is, rather than guessing. The unknown symbol names are
        # in the kernel log and they tell you whose symbols are missing.
        if dmesg | tail -20 | grep -q 'Unknown symbol kunit'; then
            echo "        The missing symbols are KUnit's own, so the framework is not loaded."
            echo "        'modprobe kunit' should have done it; check /lib/modules."
        else
            echo "        The missing symbols are qa_fifo's, so your implementation is not"
            echo "        exporting them. Each function in qa_fifo.h needs an EXPORT_SYMBOL_GPL,"
            echo "        as in L04."
        fi
        failures=$((failures + 1))
    else
        # KUnit prints a TAP report to the kernel log. The summary line is what decides it.
        dmesg | grep -q '# qa_fifo: pass:'
        check $? "the KUnit suite ran"

        summary=$(dmesg | grep -o '# qa_fifo: pass:.*' | tail -1)
        echo "        $summary"

        echo "$summary" | grep -q 'fail:0'
        check $? "every KUnit case passed"

        rmmod qa_fifo_kunit 2>/dev/null
    fi
else
    echo "  skip  qa_fifo_kunit.ko not built"
fi

# --- the character device, from userspace ------------------------------------------------------
#
# KUnit tested the ring buffer as pure logic. Everything below is about what a program outside the
# kernel actually sees, which is where copy_to_user, return values and error codes live and where
# a bug in any of them shows up for the first time.
if [ ! -f qa_chardev.ko ]; then
    echo "  skip  qa_chardev.ko not built"
elif [ ! -x qa_fifo_test ]; then
    echo "  FAIL  qa_fifo_test is missing; ci/build.sh should have cross-compiled it"
    failures=$((failures + 1))
else
    insmod ./qa_chardev.ko
    check $? "qa_chardev.ko loads"

    # The node has to exist before anything can open it. If the driver only registered a device
    # number and never created a class and a device, this is where that shows up.
    [ -c /dev/qa_fifo ]
    check $? "/dev/qa_fifo exists and is a character device"

    if [ -c /dev/qa_fifo ]; then
        major=$(stat -c '%t' /dev/qa_fifo)
        echo "        /dev/qa_fifo major 0x$major, from $(grep qa_fifo /proc/devices || echo '?')"

        ./qa_fifo_test
        check $? "the userspace tester reports no failures"
    fi

    rmmod qa_chardev 2>/dev/null
    [ ! -c /dev/qa_fifo ]
    check $? "/dev/qa_fifo is gone after rmmod"
fi

rmmod qa_fifo 2>/dev/null

echo "L05: $failures failure(s)"
exit $failures
