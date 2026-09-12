#!/usr/bin/env bash
#
# Build every lecture lab module that has been written.
#
# "That has been written" is the whole design of this script. The repository ships each lab's
# Kbuild file, its KUnit suite and its test script, and never the module itself; the reader
# writes that. So an unwritten lab is the normal state of most of this repository for most of
# the course, and it has to be reported as a skip that names what is missing, not as a failure
# and not as a silent success.
#
# Usage:
#   build.sh          Build every lecture's lab.
#   build.sh L06      Build one.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
qa_need_container "$0" "$@"

################################################################################
# Cross-compile a lecture's userspace test programs, if it has any.
#
# They live in lab/user/ rather than beside the module, and the directory matters: the lab's
# Kbuild builds every .c in lab/ as a module, so a userspace program sitting next to the driver
# would be compiled as a kernel module and fail in a way that reads like the driver is broken.
# One directory down is out of that wildcard's reach.
#
# Static linking, because the target's userland is one statically linked BusyBox and there is no
# libc on it for a dynamic binary to find. This is L01's toolchain material arriving with
# consequences.
# Globals:
#   QA_CROSS_COMPILE
# Arguments:
#   $1  Lecture name, for messages.
#   $2  Absolute path to the lab directory.
################################################################################
qa_build_user_programs() {
    local lecture="$1"
    local lab="$2"
    local dir="$lab/user"
    local source name status=0

    [ -d "$dir" ] || return 0

    for source in "$dir"/*.c; do
        [ -e "$source" ] || continue
        name="$(basename "$source" .c)"
        echo "$lecture: building user/$name"
        if ! "${QA_CROSS_COMPILE}gcc" -static -O2 -Wall -Wextra \
                -o "$dir/$name" "$source"; then
            echo "$lecture: FAILED building user/$name" >&2
            status=1
        fi
    done

    return "$status"
}

qa_need_kernel

output="$(qa_kernel_output)"
built=0
skipped=0
failed=0

for lecture in $(qa_lectures "${1:-}"); do
    lab="$QA_ROOT/lectures/$lecture/lab"

    if [ ! -f "$lab/Kbuild" ] && [ ! -f "$lab/Makefile" ]; then
        echo "$lecture: SKIPPED (no lab in this lecture)"
        skipped=$((skipped + 1))
        continue
    fi

    # A lab directory with nothing but the files this repo ships is a lab nobody has started.
    # Counting .c files is how that is detected, and the message names the appendix that says
    # what to write, because a reader seeing this is usually looking for exactly that.
    sources=$(find "$lab" -maxdepth 1 -name '*.c' -not -name '*_kunit.c' | wc -l)
    if [ "$sources" -eq 0 ]; then
        echo "$lecture: SKIPPED (no module written yet in lectures/$lecture/lab)"
        skipped=$((skipped + 1))
        continue
    fi

    # Switching kernels means the objects in the lab directory were built against a different
    # one. Kbuild does not notice: the sources have not changed, so it leaves the .ko alone, and
    # the stale module then fails to load with "invalid module format" from vermagic. L12 builds
    # for two kernels in one sitting, so this is not a corner case there.
    stamp="$lab/.qa-built-against"
    if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$output" ]; then
        if [ -f "$stamp" ]; then
            echo "$lecture: kernel changed since the last build, cleaning first"
        fi
        make --directory "$output" M="$lab" ARCH="$QA_ARCH" \
             CROSS_COMPILE="$QA_CROSS_COMPILE" clean >/dev/null 2>&1 || true
        printf '%s' "$output" > "$stamp"
    fi

    echo "$lecture: building $(basename "$lab")"
    if make --directory "$output" \
            M="$lab" \
            ARCH="$QA_ARCH" \
            CROSS_COMPILE="$QA_CROSS_COMPILE" \
            modules; then
        built=$((built + 1))
    else
        echo "$lecture: FAILED" >&2
        failed=$((failed + 1))
        continue
    fi

    qa_build_user_programs "$lecture" "$lab" || failed=$((failed + 1))
done

echo
echo "Build: $built built, $skipped skipped, $failed failed."
[ "$failed" -eq 0 ]
