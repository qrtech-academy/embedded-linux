#!/bin/sh
#
# L07 on-target test: race a counter, fix it with a lock, and make lockdep object.
#
# Two deliverables, specified in L07's Appendix C:
#
#   qa_race.c   N threads incrementing a shared counter, with and without a lock.
#   qa_abba.c   two locks taken in two orders, so that lockdep reports an inversion.
#
# The race test asserts that the unlocked run *loses* increments. That is an unusual thing for a
# test to require, and it is only safe because the module releases all its threads from a barrier
# rather than letting the first finish before the last is created; measured over ten runs the
# unlocked loss was never zero and ranged from 2% to 38%. If your unlocked run ever comes out
# exact, the barrier is what to look at first.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L07: concurrency and locking"
cd /lab || exit 1

if [ ! -f qa_race.ko ] && [ ! -f qa_abba.ko ]; then
    echo "  Not started: neither qa_race.ko nor qa_abba.ko exists."
    echo "  Write them as specified in L07 Appendix C, in lectures/L07/lab/."
    echo "L07: not started"
    exit 77
fi

# --- the race ----------------------------------------------------------------------------------
if [ -f qa_race.ko ]; then
    # The locked run must be exact. This is the deterministic half and a failure here is a real bug.
    insmod ./qa_race.ko locked=1 threads=4 increments=20000
    check $? "qa_race.ko loads with locked=1"
    line=$(dmesg | grep 'locked=1' | tail -1)
    echo "        $(echo "$line" | sed 's/.*qa_race: //')"
    echo "$line" | grep -q 'lost=0$'
    check $? "with a lock, no increments are lost"
    rmmod qa_race

    # The unlocked run must lose some. Three attempts, because the assertion is about a race and
    # one clean run would not prove the lock is unnecessary, only that this run got lucky.
    lost_any=1
    for i in 1 2 3; do
        insmod ./qa_race.ko locked=0 threads=4 increments=20000 2>/dev/null
        line=$(dmesg | grep 'locked=0' | tail -1)
        echo "        $(echo "$line" | sed 's/.*qa_race: //')"
        echo "$line" | grep -q 'lost=0$' || lost_any=0
        rmmod qa_race
    done
    [ "$lost_any" = "0" ]
    check $? "without a lock, increments are lost"
else
    echo "  skip  qa_race.ko not built"
fi

# --- lockdep -----------------------------------------------------------------------------------
if [ -f qa_abba.ko ]; then
    before=$(dmesg | grep -c 'possible circular locking dependency')

    insmod ./qa_abba.ko
    check $? "qa_abba.ko loads"

    # The module must survive. If taking the locks in two orders actually deadlocked, insmod
    # would never return and this test would time out instead of failing.
    lsmod | grep -q '^qa_abba'
    check $? "the module is loaded, so nothing actually deadlocked"

    after=$(dmesg | grep -c 'possible circular locking dependency')
    [ "$after" -gt "$before" ]
    check $? "lockdep reported a possible circular locking dependency"

    dmesg | grep -q '\*\*\* DEADLOCK \*\*\*'
    check $? "the report contains the DEADLOCK diagram"

    dmesg | grep -q 'print_circular_bug'
    check $? "the backtrace names print_circular_bug"

    dmesg | grep -A 1 'is trying to acquire lock' | tail -1 \
        | sed -e 's/^\[[^]]*\] */        /' -e 's/, at:.*//'

    # Asserted on lsmod: this BusyBox's rmmod exits 0 even when the unload failed.
    rmmod qa_abba
    ! lsmod | grep -q '^qa_abba'
    check $? "qa_abba.ko unloads"
else
    echo "  skip  qa_abba.ko not built"
fi

echo "L07: $failures failure(s)"
exit $failures
