#!/usr/bin/env bash
#
# Run the golden programs and diff their output against what is committed.
#
# This is the repository's own regression test, and it exists because of a rule this course
# holds itself to: every number quoted in an appendix is produced by running something, not
# typed in by an author. A number nobody can regenerate is a number nobody notices has gone
# stale, and an appendix full of those is an appendix that is quietly wrong.
#
# A golden file is lectures/LNN/appendix/golden/<name>.golden beside the script that produces
# it, lectures/LNN/appendix/golden/<name>.sh. The script runs on the host and prints to stdout.
# Anything whose output is a property of the machine it ran on belongs in "make measure"
# territory and is not golden; see L12, which measures latency and commits no number for it.
#
# Usage:
#   check.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

checked=0
failed=0

while IFS= read -r script; do
    golden="${script%.sh}.golden"
    name="${script#"$QA_ROOT/"}"

    if [ ! -f "$golden" ]; then
        echo "$name: SKIPPED (no committed .golden beside it)"
        continue
    fi

    checked=$((checked + 1))

    # Both sides through the same command substitution. $(...) strips trailing newlines, and
    # comparing a captured string against a file that ends in one fails on the newline alone.
    actual="$(bash "$script" 2>&1)"
    expected="$(cat "$golden")"

    if [ "$actual" = "$expected" ]; then
        echo "$name: OK"
    else
        echo "$name: DIFFERS" >&2
        diff <(echo "$expected") <(echo "$actual") | head -40 >&2
        failed=$((failed + 1))
    fi
done < <(find "$QA_ROOT/lectures" -path '*/appendix/golden/*.sh' | sort)

if [ "$checked" -eq 0 ]; then
    echo "SKIPPED: no golden programs committed yet."
    exit 0
fi

echo
echo "Check: $checked golden program(s), $failed differing."
[ "$failed" -eq 0 ]
