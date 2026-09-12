#!/bin/sh
#
# L04 on-target test: load the modules you wrote, and prove the licence boundary is real.
#
# Run by /init when the kernel command line carries qa.test=L04.
#
# Every unload is checked by looking at whether the module is still there, and deliberately not by
# looking at rmmod's exit status. This target's BusyBox is built with CONFIG_MODPROBE_SMALL, whose
# rmmod returns 0 even when delete_module() failed and the module is still loaded, so a test
# written the obvious way gets the same answer on a kernel that refused and on a kernel that did
# not. Assert on the state, not on the tool.

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "  ok    $2"
    else
        echo "  FAIL  $2"
        failures=$((failures + 1))
    fi
}

echo "L04: kernel modules"
cd /lab || exit 1

# --- qa_hello: the smallest module that does anything ------------------------------------------
if [ -f qa_hello.ko ]; then
    insmod ./qa_hello.ko 2>/tmp/err
    check $? "qa_hello.ko loads"

    lsmod | grep -q '^qa_hello'
    check $? "qa_hello appears in lsmod"

    dmesg | tail -20 | grep -q 'qa_hello'
    check $? "qa_hello printed something to the kernel log"

    # A module's parameters, if it has any, appear here without the module doing anything.
    [ -d /sys/module/qa_hello ]
    check $? "qa_hello has a directory under /sys/module"

    rmmod qa_hello
    ! lsmod | grep -q '^qa_hello'
    check $? "qa_hello.ko unloads"

    dmesg | tail -5 | grep -q 'qa_hello'
    check $? "qa_hello printed something on the way out"
else
    echo "  skip  qa_hello.ko not built"
fi

# --- qa_export and qa_user: one module using another's symbol ----------------------------------
if [ -f qa_export.ko ] && [ -f qa_user.ko ]; then
    # Loading the user first must fail: its symbol is not there yet. This is the check that
    # proves the dependency is real rather than assumed.
    insmod ./qa_user.ko 2>/dev/null
    [ $? -ne 0 ]
    check $? "qa_user.ko refuses to load before qa_export.ko"

    insmod ./qa_export.ko
    check $? "qa_export.ko loads"

    insmod ./qa_user.ko
    check $? "qa_user.ko loads once its dependency is present"

    # Unloading in the wrong order must fail too: the kernel counts users, and qa_user holds a
    # reference on qa_export for as long as it is loaded. Asserted on the state, as above.
    rmmod qa_export 2>/dev/null
    lsmod | grep -q '^qa_export'
    check $? "qa_export.ko is still loaded: the kernel refused to remove a module in use"

    grep -q 'qa_user' /sys/module/qa_export/holders/* 2>/dev/null \
        || [ -e /sys/module/qa_export/holders/qa_user ]
    check $? "qa_user appears in qa_export's holders directory"

    rmmod qa_user
    rmmod qa_export
    ! lsmod | grep -qE '^(qa_user|qa_export)'
    check $? "both unload in the right order"
else
    echo "  skip  qa_export.ko and qa_user.ko not both built"
fi

echo "L04: $failures failure(s)"
exit $failures
