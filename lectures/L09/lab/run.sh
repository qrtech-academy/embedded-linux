#!/bin/sh
#
# L09 on-target test: block a reader until the interrupt has data for it, and support poll.
#
# Two deliverables, specified in L09's Appendix C:
#
#   qa_wait.c    L08's interrupt driver plus a character device whose read() blocks, honours
#                O_NONBLOCK, and implements poll.
#   qa_timing.c  a measurement module for the Cross-check.
#
# The userspace half is qa_wait_test, which ships with the course. It is a program rather than a
# shell script because the three things it checks are invisible from a shell: whether a read
# blocked, whether it returned -EAGAIN or 0, and whether select reported readiness or timed out.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L09: sleeping, waiting, and time"
cd /lab || exit 1

if [ ! -f qa_wait.ko ] && [ ! -f qa_timing.ko ]; then
    echo "  Not started: neither qa_wait.ko nor qa_timing.ko exists."
    echo "  Write them as specified in L09 Appendix C, in lectures/L09/lab/."
    echo "L09: not started"
    exit 77
fi

# --- blocking, non-blocking and poll -------------------------------------------------------------
if [ -f qa_wait.ko ]; then
    if [ ! -x qa_wait_test ]; then
        echo "  FAIL  qa_wait_test is missing; ci/build.sh should have cross-compiled it"
        failures=$((failures + 1))
    else
        insmod ./qa_wait.ko period_ns=1000000
        check $? "qa_wait.ko loads with the device running"

        [ -c /dev/qa_wait ]
        check $? "/dev/qa_wait exists"

        ./qa_wait_test running
        check $? "blocking read, a read that waits, and select all behave"
        rmmod qa_wait

        # The same driver with nothing producing samples. This is where a reader that returns 0
        # instead of -EAGAIN, or a poll that always reports readable, is caught.
        insmod ./qa_wait.ko period_ns=0
        check $? "qa_wait.ko loads with the device stopped"

        ./qa_wait_test stopped
        check $? "non-blocking read gives -EAGAIN and select times out"
        # Asserted on lsmod: this BusyBox's rmmod exits 0 even when the unload failed.
        rmmod qa_wait
        ! lsmod | grep -q '^qa_wait'
        check $? "qa_wait.ko unloads"
    fi
else
    echo "  skip  qa_wait.ko not built"
fi

# --- the timing measurement ----------------------------------------------------------------------
if [ -f qa_timing.ko ]; then
    insmod ./qa_timing.ko reps=200
    check $? "qa_timing.ko loads and runs its measurements"

    dmesg | grep -q 'HZ=250'
    check $? "the module reports HZ, and this kernel is HZ=250"

    dmesg | grep -E 'HZ=|each=' | sed 's/.*qa_timing: /        /'

    # msleep(1) and msleep(4) must come out the same, because both round to two jiffies. A module
    # that reports them as different has measured something other than what it thinks.
    one=$(dmesg | grep 'msleep(1)' | sed 's/.*each=//; s/ us//' | tail -1)
    four=$(dmesg | grep 'msleep(4)' | sed 's/.*each=//; s/ us//' | tail -1)
    awk -v a="$one" -v b="$four" 'BEGIN { exit !(a > 0 && b > 0 && (a > b ? a - b : b - a) < 500) }'
    check $? "msleep(1) and msleep(4) take the same time ($one us and $four us)"

    # And usleep_range, which uses hrtimers, must do better than a jiffy.
    ur=$(dmesg | grep 'usleep_range(1000)' | sed 's/.*each=//; s/ us//' | tail -1)
    awk -v v="$ur" 'BEGIN { exit !(v > 0 && v < 4000) }'
    check $? "usleep_range(1000) beats a jiffy ($ur us against 4000 us)"

    rmmod qa_timing
else
    echo "  skip  qa_timing.ko not built"
fi

echo "L09: $failures failure(s)"
exit $failures
