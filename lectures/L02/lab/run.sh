#!/bin/sh
#
# L02 on-target test: check the machine report you wrote.
#
# The deliverable for this lecture is a shell script, machine-report.sh, specified in L02's
# Appendix C.6. It prints one "key: value" line per fact, read out of /proc and /sys. This file
# runs it and checks both that every required key is present and that its value is plausible.
#
# "Plausible" rather than "correct" is deliberate. The uptime of the machine is not a number this
# test can know in advance, and a test that demanded an exact value would be a test of the
# harness rather than of your script. What it can check is that the value is a number, that it is
# in a range only a working answer could be in, and that keys which must agree with each other do.
#
# Run by /init when the kernel command line carries qa.test=L02.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L02: the command line, and the system underneath it"
cd /lab || exit 1

if [ ! -f machine-report.sh ]; then
    echo "  Not started: /lab/machine-report.sh does not exist."
    echo "  Write it as specified in L02 Appendix C.6, in lectures/L02/lab/."
    echo "L02: not started"
    exit 77
fi

chmod +x machine-report.sh 2>/dev/null

# Sampled before the report runs, not after, and the order is the whole point. This value is used
# below to tell a rate from the raw counter, and the counter only grows: read it afterwards and it
# has already passed whatever the report printed, so the comparison silently succeeds for a script
# that printed the counter. Getting this backwards is exactly the bug the check exists to find.
ctxt_before=$(awk '/^ctxt/ { print $2 }' /proc/stat)

./machine-report.sh > /tmp/report 2>/tmp/report-err
status=$?

check $status "machine-report.sh runs and exits 0"
if [ $status -ne 0 ]; then
    echo "        stderr was:"
    sed 's/^/        /' /tmp/report-err | head -5
    echo "L02: $failures failure(s)"
    exit $failures
fi

echo "        --- your report ---"
sed 's/^/        /' /tmp/report
echo "        -------------------"

# Every required key must be present exactly once. A report with a key twice is a report whose
# consumer gets whichever line it happens to read first.
for key in kernel cpus memtotal-kb uptime-s cmdline init chardev-majors ctxt-per-s; do
    count=$(grep -c "^$key:" /tmp/report)
    [ "$count" = "1" ]
    check $? "reports '$key' exactly once (found $count)"
done

value() { sed -n "s/^$1: *//p" /tmp/report | head -1; }

# --- plausibility -------------------------------------------------------------------------------

# The kernel this course pins. Checked against /proc/version rather than against a constant here,
# so the test still passes if the pin in ci/versions.sh moves.
expected_kernel=$(sed 's/^Linux version \([^ ]*\).*/\1/' /proc/version)
[ "$(value kernel)" = "$expected_kernel" ]
check $? "kernel matches /proc/version ($expected_kernel)"

# QEMU was given -smp 2, and /proc/cpuinfo is where that becomes visible.
expected_cpus=$(grep -c '^processor' /proc/cpuinfo)
[ "$(value cpus)" = "$expected_cpus" ]
check $? "cpus matches /proc/cpuinfo ($expected_cpus)"

expected_mem=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
[ "$(value memtotal-kb)" = "$expected_mem" ]
check $? "memtotal-kb matches /proc/meminfo ($expected_mem)"

# Uptime is a moving target, so this checks it is a number and that it is smaller than the
# machine has been up by the time we look, rather than checking a value.
up=$(value uptime-s)
case "$up" in
    ''|*[!0-9.]*) check 1 "uptime-s is a number (got '$up')" ;;
    *)            check 0 "uptime-s is a number" ;;
esac

# The command line is exact and the test can afford to be strict about it.
[ "$(value cmdline)" = "$(cat /proc/cmdline)" ]
check $? "cmdline matches /proc/cmdline"

[ "$(value init)" = "$(cat /proc/1/comm)" ]
check $? "init matches the comm of PID 1 ($(cat /proc/1/comm))"

# /proc/devices has a "Character devices:" section and a "Block devices:" one; counting the whole
# file is the plausible wrong answer, and the number below is only the first section.
expected_majors=$(sed -n '/^Character devices:/,/^$/p' /proc/devices | grep -c '^ *[0-9]')
[ "$(value chardev-majors)" = "$expected_majors" ]
check $? "chardev-majors counts only character devices ($expected_majors)"

# The rate is the interesting one. It cannot be checked against a known value, but a working
# answer is a non-negative number, and an idle target sits well under ten thousand a second.
# Zero is the tell-tale of the mistake this exercise is about: sampling /proc/stat once.
rate=$(value ctxt-per-s)
case "$rate" in
    ''|*[!0-9.]*) check 1 "ctxt-per-s is a number (got '$rate')" ;;
    0|0.0|0.00)   check 1 "ctxt-per-s is not zero (a zero rate means you sampled /proc/stat once)" ;;
    *)            check 0 "ctxt-per-s is a plausible non-zero number ($rate)" ;;
esac

# And it must be a rate rather than the raw counter. The counter since boot is the integral of the
# rate, so it exceeds the current rate for any machine that has been up longer than a second; a
# reported value at or above the counter is therefore the counter itself. Compared against the
# sample taken before the report ran, for the reason given where that sample is taken.
awk -v r="$rate" -v c="$ctxt_before" 'BEGIN { exit !(r + 0 < c + 0) }'
check $? "ctxt-per-s is a rate, not the raw counter (counter was $ctxt_before before your run)"

echo "L02: $failures failure(s)"
exit $failures
