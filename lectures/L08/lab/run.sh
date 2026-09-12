#!/bin/sh
#
# L08 on-target test: take the device's interrupt, acknowledge it, and defer the work.
#
# The deliverable is qa_irq.c, specified in L08's Appendix C.6.
#
# One thing this test relies on and it is worth knowing before you read it: the counts in
# /proc/interrupts belong to the *interrupt descriptor*, not to your handler registration. They
# survive free_irq, so unloading and reloading your module does not reset them. Everything below
# takes a delta.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

count() { grep qa_irq /proc/interrupts | awk '{ print $2 + $3 }'; }

echo "L08: interrupts and deferred work"
cd /lab || exit 1

if [ ! -f qa_irq.ko ]; then
    echo "  Not started: /lab/qa_irq.ko does not exist."
    echo "  Write qa_irq.c as specified in L08 Appendix C.6, in lectures/L08/lab/."
    echo "L08: not started"
    exit 77
fi

# --- the interrupt arrives at all ----------------------------------------------------------------
insmod ./qa_irq.ko period_ns=1000000 2>/tmp/err
check $? "qa_irq.ko loads"
if ! lsmod | grep -q '^qa_irq'; then
    sed 's/^/        /' /tmp/err | head -3
    echo "L08: $failures failure(s)"
    exit $failures
fi

grep -q qa_irq /proc/interrupts
check $? "the handler is registered and appears in /proc/interrupts"
grep qa_irq /proc/interrupts | sed 's/^/        /'

# The three numbers. The device tree says SPI 112; the GIC knows it as 112 + 32 = 144; Linux
# calls it whatever the fourth column of /proc/interrupts says. All three are different and all
# three are correct.
hw=$(grep qa_irq /proc/interrupts | awk '{ print $5 }')
[ "$hw" = "144" ]
check $? "the GIC hardware interrupt number is 144, which is SPI 112 plus the 32 SPI base"

n0=$(count); t0=$(cut -d' ' -f1 /proc/uptime)
sleep 2
n1=$(count); t1=$(cut -d' ' -f1 /proc/uptime)
delta=$((n1 - n0))

[ "$delta" -gt 100 ]
check $? "interrupts are actually firing (delta $delta over two seconds)"

awk -v a="$t0" -v b="$t1" -v d="$delta" 'BEGIN {
    el = b - a; e = el * 1000; s = 100 * (e - d) / e;
    printf "        elapsed %.2fs, expected ~%.0f at 1 ms, got %d, %.1f%% short\n", el, e, d, s }'

# On the way out the driver prints what it counted. B.6 is about why those counts and the device's
# need not agree. The unload is asserted on lsmod rather than on rmmod's exit status, because this
# BusyBox's rmmod exits 0 even when the unload failed.
rmmod qa_irq
! lsmod | grep -q '^qa_irq'
check $? "qa_irq.ko unloads while interrupts are arriving"
dmesg | grep -E 'qa_irq: hard=' | tail -1 | sed 's/.*qa_irq: /        /'

# --- reloading does not reset the counter --------------------------------------------------------
before=$(grep -c qa_irq /proc/interrupts)
[ "$before" = "0" ]
check $? "the /proc/interrupts line is gone once the handler is freed"

# --- the threaded handler ------------------------------------------------------------------------
insmod ./qa_irq.ko period_ns=1000000 threaded=1 2>/dev/null
check $? "qa_irq.ko loads with a threaded handler"
if lsmod | grep -q '^qa_irq'; then
    # A threaded handler runs in a kernel thread, which is schedulable and has a name.
    ps | grep -q '[i]rq/.*qa_irq'
    check $? "a kernel thread exists for the threaded handler"
    ps | grep '[i]rq/.*qa_irq' | sed 's/^/        /'

    m0=$(count); sleep 1; m1=$(count)
    [ "$((m1 - m0))" -gt 100 ]
    check $? "the threaded handler is also servicing interrupts ($((m1 - m0)) in one second)"

    rmmod qa_irq
    dmesg | grep -E 'qa_irq: hard=' | tail -1 | sed 's/.*qa_irq: /        /'
fi

echo "L08: $failures failure(s)"
exit $failures
