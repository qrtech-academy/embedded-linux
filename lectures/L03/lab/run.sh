#!/bin/sh
#
# L03 on-target test: check the kernel report you wrote.
#
# The deliverable is kernel-report.sh, specified in L03's Appendix C.6: a script that says what
# the running kernel was configured with, using only what is visible at run time.
#
# The interesting part, and what run.sh is built around, is that it has to work in two different
# worlds. With CONFIG_IKCONFIG on, /proc/config.gz holds the exact configuration and every answer
# can be looked up. With it off, which is where the Cross-check leaves you, that file is gone and
# the same answers have to be inferred from other evidence. A script that only works in one of
# those is a script that will mislead you on somebody else's kernel, where the file is usually
# absent.
#
# So this test works out which world it is in, and checks the report against it either way.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L03: the kernel, its tree, and its configuration"
cd /lab || exit 1

if [ ! -f kernel-report.sh ]; then
    echo "  Not started: /lab/kernel-report.sh does not exist."
    echo "  Write it as specified in L03 Appendix C.6, in lectures/L03/lab/."
    echo "L03: not started"
    exit 77
fi

if [ -r /proc/config.gz ]; then
    world="config.gz"
else
    world="inferred"
fi
echo "        this kernel's configuration is available as: $world"

chmod +x kernel-report.sh 2>/dev/null
./kernel-report.sh > /tmp/report 2>/tmp/report-err
status=$?

check $status "kernel-report.sh runs and exits 0"
if [ $status -ne 0 ]; then
    echo "        stderr was:"
    sed 's/^/        /' /tmp/report-err | head -5
    echo "L03: $failures failure(s)"
    exit $failures
fi

echo "        --- your report ---"
sed 's/^/        /' /tmp/report
echo "        -------------------"

for key in version smp preempt hz modules filesystems char-majors config-source; do
    count=$(grep -c "^$key:" /tmp/report)
    [ "$count" = "1" ]
    check $? "reports '$key' exactly once (found $count)"
done

value() { sed -n "s/^$1: *//p" /tmp/report | head -1; }

# --- things that are true regardless of which world we are in ------------------------------------

[ "$(value version)" = "$(sed 's/^Linux version \([^ ]*\).*/\1/' /proc/version)" ]
check $? "version matches /proc/version"

# /proc/version carries the word SMP for an SMP build. This target is booted with -smp 2.
if grep -q ' SMP ' /proc/version; then expect_smp=yes; else expect_smp=no; fi
[ "$(value smp)" = "$expect_smp" ]
check $? "smp is '$expect_smp'"

# The preemption model is in /proc/version too, and the four spellings are distinct. PREEMPT_RT
# has to be tested before PREEMPT, because the string PREEMPT is a prefix of it; a script that
# tests in the other order calls an RT kernel a PREEMPT one, and L12 depends on telling them apart.
case "$(cat /proc/version)" in
    *PREEMPT_RT*)        expect_preempt=preempt_rt ;;
    *PREEMPT_DYNAMIC*)   expect_preempt=preempt_dynamic ;;
    *PREEMPT*)           expect_preempt=preempt ;;
    *)                   expect_preempt=none ;;
esac
[ "$(value preempt)" = "$expect_preempt" ]
check $? "preempt is '$expect_preempt'"

[ "$(value modules)" = "yes" ]
check $? "modules is 'yes' (this kernel has CONFIG_MODULES)"

expect_fs=$(grep -c . /proc/filesystems)
[ "$(value filesystems)" = "$expect_fs" ]
check $? "filesystems matches /proc/filesystems ($expect_fs)"

expect_majors=$(sed -n '/^Character devices:/,/^$/p' /proc/devices | grep -c '^ *[0-9]')
[ "$(value char-majors)" = "$expect_majors" ]
check $? "char-majors counts only character devices ($expect_majors)"

# --- the part that depends on the world ----------------------------------------------------------

[ "$(value config-source)" = "$world" ]
check $? "config-source correctly reports '$world'"

if [ "$world" = "config.gz" ]; then
    expect_hz=$(zcat /proc/config.gz | sed -n 's/^CONFIG_HZ=//p' | head -1)
    [ "$(value hz)" = "$expect_hz" ]
    check $? "hz matches CONFIG_HZ in /proc/config.gz ($expect_hz)"
else
    # With no config.gz there is no honest way to read CONFIG_HZ off a running kernel, and the
    # right answer is to say so rather than to guess. A report that prints a confident number it
    # cannot justify is worse than one that admits the gap.
    [ "$(value hz)" = "unknown" ]
    check $? "hz is 'unknown' when there is no config.gz to read it from"
fi

echo "L03: $failures failure(s)"
exit $failures
