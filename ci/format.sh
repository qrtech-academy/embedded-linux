#!/usr/bin/env bash
#
# Format the C with clang-format and the Python with black, or check that they are formatted.
#
# What is checked is what this repository ships, and deliberately not what the reader writes.
# The lab directories are the reader's workspace; a lint job that failed because somebody's
# half-finished driver had a brace in the wrong place would be a lint job people learn to
# ignore. The KUnit suites in those directories are ours and are checked.
#
# Usage:
#   format.sh           Format in place.
#   format.sh --check   Fail if anything is unformatted.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

################################################################################
# Print every file this repository owns and formats, one per line.
# Globals:
#   QA_ROOT
# Arguments:
#   $1  Extension to list: "c" or "py".
################################################################################
owned_files() {
    case "$1" in
        c)
            find "$QA_ROOT/tools" -name '*.c' -o -name '*.h'
            # What the course ships inside a lab: the KUnit suites and the userspace testers.
            # Not the reader's own sources, which sit beside them and are theirs to format.
            find "$QA_ROOT/lectures" -name '*_kunit.c'
            find "$QA_ROOT/lectures" -path '*/lab/user/*.c'
            find "$QA_ROOT/lectures" -path '*/lab/*.h'
            ;;
        py)
            find "$QA_ROOT/diagrams" "$QA_ROOT/tools" -name '*.py' 2>/dev/null
            ;;
    esac
}

status=0

if ! command -v clang-format >/dev/null 2>&1; then
    echo "SKIPPED: clang-format not found; the C is not checked. Run 'make env', or install it."
else
    mapfile -t sources < <(owned_files c)
    if [ "${#sources[@]}" -eq 0 ]; then
        echo "C: nothing to format yet."
    elif [ "$check_only" -eq 1 ]; then
        if clang-format --dry-run --Werror "${sources[@]}" 2>&1; then
            echo "C: ${#sources[@]} file(s) formatted."
        else
            echo "error: run 'make format'." >&2
            status=1
        fi
    else
        clang-format -i "${sources[@]}"
        echo "C: ${#sources[@]} file(s) formatted."
    fi
fi

if ! command -v black >/dev/null 2>&1; then
    echo "SKIPPED: black not found; the Python is not checked. Run 'make env', or install it."
else
    mapfile -t sources < <(owned_files py)
    if [ "${#sources[@]}" -eq 0 ]; then
        echo "Python: nothing to format yet."
    elif [ "$check_only" -eq 1 ]; then
        if black --quiet --check --line-length 100 "${sources[@]}"; then
            echo "Python: ${#sources[@]} file(s) formatted."
        else
            echo "error: run 'make format'." >&2
            status=1
        fi
    else
        black --quiet --line-length 100 "${sources[@]}"
        echo "Python: ${#sources[@]} file(s) formatted."
    fi
fi

exit "$status"
