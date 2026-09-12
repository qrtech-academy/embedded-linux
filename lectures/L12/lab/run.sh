#!/bin/sh
#
# L12 on-target test: measure interrupt latency by subtraction, on whichever kernel is booted.
#
# The deliverable is qa_latency.c, specified in L12's Appendix C. This script runs on both the
# PREEMPT and the PREEMPT_RT kernel and checks the same things of each, because the point of the
# lecture is the comparison and a test that only worked on one of them could not make it.
#
#   make test L=L12          the PREEMPT kernel
#   RT=1 make test L=L12     the PREEMPT_RT kernel
#
# Note that the module must be rebuilt between the two. A module carries the vermagic of the
# kernel it was built against, which is L04's material; ci/build.sh notices the change and cleans
# for you, and without that you get "invalid module format".

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L12: real-time Linux"
cd /lab || exit 1

if [ ! -f qa_latency.ko ]; then
    echo "  Not started: /lab/qa_latency.ko does not exist."
    echo "  Write qa_latency.c as specified in L12 Appendix C, in lectures/L12/lab/."
    echo "L12: not started"
    exit 77
fi

model=$(grep -o 'PREEMPT_RT\|PREEMPT_DYNAMIC\|PREEMPT' /proc/version | head -1)
echo "        this kernel is $model"

insmod ./qa_latency.ko period_ns=1000000 2>/tmp/err
check $? "qa_latency.ko loads"
if ! lsmod | grep -q '^qa_latency'; then
    sed 's/^/        /' /tmp/err | head -2
    echo "        'invalid module format' means it was built against the other kernel."
    echo "        Rebuild with 'make build L=L12' or 'RT=1 make build L=L12' to match."
    echo "L12: $((failures + 1)) failure(s)"
    exit $((failures + 1))
fi

[ -c /dev/qa_latency ]
check $? "/dev/qa_latency exists"

[ -x qa_latency_test ]
check $? "the measurement program was cross-compiled"

# --- idle ----------------------------------------------------------------------------------------
echo "  --- idle ---"
./qa_latency_test 2000 > /tmp/idle 2>&1
check $? "the measurement runs on an idle system"
sed 's/^/  /' /tmp/idle

idle_max=$(sed -n 's/.*max \([0-9]*\) us.*/\1/p' /tmp/idle | head -1)
[ -n "$idle_max" ] && [ "$idle_max" -gt 0 ]
check $? "it reports a maximum ($idle_max us)"

# The device timestamp and ktime have different origins, so the interrupt-to-handler figure can
# only be a spread. The program must say so rather than printing a number that looks absolute.
grep -q 'spread above the best case' /tmp/idle
check $? "interrupt-to-handler is reported as a spread, not as an absolute"

# --- under load --------------------------------------------------------------------------------
echo "  --- under load ---"
i=0
while [ $i -lt 4 ]; do
    (while : ; do : ; done) &
    i=$((i + 1))
done
sleep 1

./qa_latency_test 2000 > /tmp/load 2>&1
check $? "the measurement runs under load"
sed 's/^/  /' /tmp/load

kill %1 %2 %3 %4 2>/dev/null

load_max=$(sed -n 's/.*max \([0-9]*\) us.*/\1/p' /tmp/load | head -1)
[ -n "$load_max" ] && [ "$load_max" -gt "$idle_max" ]
check $? "load makes the worst case worse ($idle_max us idle, $load_max us loaded)"

# Under load the reader cannot keep up and the driver's ring overflows. That is a result, not a
# malfunction: it is what a fixed-size buffer does when the consumer is starved.
grep -q 'dropped by the driver: [1-9]' /tmp/load
check $? "and the driver drops records, because the reader is starved"

# Asserted on lsmod: this BusyBox's rmmod exits 0 even when the unload failed.
rmmod qa_latency
! lsmod | grep -q '^qa_latency'
check $? "qa_latency.ko unloads"

echo "        $model: worst case $idle_max us idle, $load_max us under load"
echo "L12: $failures failure(s)"
exit $failures
