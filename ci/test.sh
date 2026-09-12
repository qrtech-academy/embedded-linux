#!/usr/bin/env bash
#
# Boot each lecture's lab in QEMU and report what its tests said.
#
# There is no host-side test framework here and there cannot be: the code under test is a kernel
# module, and a kernel module runs in a kernel. So the harness is the machine itself. Each
# lecture gets a copy of the base initramfs with its modules and its test script dropped into
# /lab, boots, runs /lab/run.sh as PID 1's only job, prints a marker, and powers off. The host
# reads the serial log.
#
# The markers are three, and the third is the one that matters:
#
#   QA-TEST-BEGIN LNN            the target got far enough to start
#   QA-TEST-END   LNN status=N   the script ran to completion and this is its exit status
#   (neither)                    the kernel panicked, hung, or never booted
#
# A harness that only looked for a pass string would call the third case a failure, which is
# right, and would call a timeout the same thing, which loses the distinction a reader needs.
# They are reported separately.
#
# Usage:
#   test.sh          Every lecture.
#   test.sh L05      One.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
qa_need_container "$0" "$@"

qa_need_qemu
qa_need_kernel
qa_need_rootfs

# Long enough for a slow machine under load, short enough that a hung target does not hold up a
# CI job for an hour. A lab that legitimately needs longer says so by setting QA_TIMEOUT.
timeout_s="${QA_TIMEOUT:-120}"

logs="$QA_BUILD/test-logs"
mkdir -p "$logs"

passed=0
failed=0
skipped=0
crashed=0

for lecture in $(qa_lectures "${1:-}"); do
    lab="$QA_ROOT/lectures/$lecture/lab"

    if [ ! -f "$lab/run.sh" ]; then
        echo "$lecture: SKIPPED (no lab/run.sh; this lecture has no on-target test)"
        skipped=$((skipped + 1))
        continue
    fi

    # Not every lab is a module. L01 to L03 build a system rather than a driver, and their
    # run.sh checks the machine it produced; from L04 on there is a module, and the lab says so
    # by shipping a Kbuild. Deciding from the Kbuild rather than from the lecture number means
    # this stays true if a lecture changes shape.
    if [ -f "$lab/Kbuild" ] || [ -f "$lab/Makefile" ]; then
        # Modules are the reader's to write. None built means the lab has not been started,
        # which is a skip; a module that fails to compile is a failure and ci/build.sh has
        # already said so.
        modules=$(find "$lab" -maxdepth 1 -name '*.ko' | wc -l)
        if [ "$modules" -eq 0 ]; then
            echo "$lecture: SKIPPED (no built module in lectures/$lecture/lab; run 'make build')"
            skipped=$((skipped + 1))
            continue
        fi
    fi

    root="$(qa_rootfs_dir)-test-$lecture"
    rm -rf "$root"
    cp --archive "$(qa_rootfs_dir)" "$root"

    mkdir -p "$root/lab"
    find "$lab" -maxdepth 1 -name '*.ko' -exec cp {} "$root/lab/" \;
    find "$lab" -maxdepth 1 -name '*.sh' -not -name 'run.sh' -exec cp {} "$root/lab/" \;

    # Userspace test programs, built by ci/build.sh into lab/user/. Copied flat into /lab so that
    # a lab's run.sh can invoke ./name without knowing where it came from. Only executables are
    # taken; the .c files stay on the host.
    if [ -d "$lab/user" ]; then
        find "$lab/user" -maxdepth 1 -type f -perm -u+x -exec cp {} "$root/lab/" \;
    fi
    cp "$lab/run.sh" "$root/lab/run.sh"
    chmod 755 "$root/lab/run.sh"

    ( cd "$root" && find . | cpio --create --format=newc --quiet --owner=+0:+0 ) \
        | gzip --best > "$root.cpio.gz"

    log="$logs/$lecture.log"
    append="console=ttyAMA0 rdinit=/init qa.test=$lecture"

    echo "$lecture: booting"

    # qa_qemu_args names the plain initramfs, so this boot points at the lecture's own archive
    # instead. Everything else about the command line is the same, deliberately: a lab that only
    # works under a different QEMU invocation than "make boot" is a lab nobody can debug by hand.
    set +e
    timeout --signal=KILL "$timeout_s" \
        "$(qa_qemu_binary)" \
        -machine virt -cpu cortex-a72 -smp "${QA_SMP:-2}" -m "${QA_MEM:-512}" \
        -nographic -no-reboot \
        -kernel "$(qa_kernel_image)" \
        -initrd "$root.cpio.gz" \
        -device "qa-dev,period-ns=${QA_PERIOD_NS:-1000000}" \
        -append "$append" \
        > "$log" 2>&1
    qemu_status=$?
    set -e

    if [ "$qemu_status" -eq 137 ]; then
        echo "$lecture: TIMEOUT after ${timeout_s}s. Serial log: $log"
        crashed=$((crashed + 1))
        continue
    fi

    if ! grep -q "QA-TEST-BEGIN $lecture" "$log"; then
        echo "$lecture: CRASHED before the test started. Serial log: $log"
        crashed=$((crashed + 1))
        continue
    fi

    # The status is on the QA-TEST-END line, and its absence means the script died partway.
    # "|| true" is load-bearing under pipefail: grep finding nothing is the case being handled.
    end=$({ grep "QA-TEST-END $lecture" "$log" || true; } | tail -1)
    if [ -z "$end" ]; then
        echo "$lecture: CRASHED partway through the test. Serial log: $log"
        crashed=$((crashed + 1))
        continue
    fi

    # A serial console ends every line with CR LF, so the captured status is "0\r" and not "0".
    # Comparing it against "0" then fails on a test that passed, which is the worst possible
    # direction for a harness to be wrong in. Strip the carriage return.
    status="${end##*status=}"
    status="${status%$'\r'}"

    # 77 means the lab reported that it has not been started, which is a skip and not a failure.
    # The number is the automake convention for exactly this, borrowed rather than invented so
    # that anyone who has seen it before recognises it. Module labs are detected as unstarted on
    # the host, by the absence of a .ko; a lab whose deliverable is a shell script can only be
    # detected on the target, which is why it needs a channel to say so.
    if [ "$status" = "77" ]; then
        echo "$lecture: SKIPPED (the lab reports it has not been started)"
        { grep -A 2 'QA-TEST-BEGIN' "$log" || true; } | sed 's/^/    /' | tr -d '\r' | head -3
        skipped=$((skipped + 1))
        continue
    fi
    if [ "$status" = "0" ]; then
        echo "$lecture: PASSED"
        passed=$((passed + 1))
    else
        echo "$lecture: FAILED (status=$status). Serial log: $log"
        failed=$((failed + 1))
    fi
done

echo
echo "Test: $passed passed, $failed failed, $crashed crashed, $skipped skipped."
[ "$failed" -eq 0 ] && [ "$crashed" -eq 0 ]
