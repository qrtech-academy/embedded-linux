#!/usr/bin/env bash
#
# Regenerate every figure into lectures/*/appendix/images.
#
# The PNGs are committed, and CI diffs them after regenerating, so a figure whose source
# changed but whose PNG did not is a failed build rather than a lecture illustrated with last
# month's numbers.
#
# Usage:
#   diagrams.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [ ! -f "$QA_ROOT/diagrams/build.py" ]; then
    qa_skip "no diagrams/build.py yet."
fi

venv="$QA_ROOT/.venv"
if [ ! -d "$venv" ]; then
    echo "Creating $venv."
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet --upgrade pip
    "$venv/bin/pip" install --quiet --requirement "$QA_ROOT/diagrams/requirements.txt"
fi

"$venv/bin/python" "$QA_ROOT/diagrams/build.py" "$@"
