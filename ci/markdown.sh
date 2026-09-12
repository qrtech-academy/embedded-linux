#!/usr/bin/env bash
#
# Check the Markdown house rules this course relies on.
#
# One author writing ten lectures over months drifts, and the drift is invisible until two
# lectures sitting next to each other look like they came from different books. Each rule here
# exists because it is either load-bearing for a reader or impossible to spot by eye:
#
#   1. Alt text. The figures are the material, not decoration; a reader on a slow connection or
#      a screen reader gets nothing from "![](./images/vtc.png)". machine-learning writes empty
#      alt text throughout and digital-design-vhdl writes real alt text by hand. This makes the
#      newer habit a rule.
#   2. Line length. Prose is hard-wrapped at 100 columns so a diff shows which sentence changed
#      rather than which paragraph. Tables, fenced code and unbreakable tokens are exempt.
#   3. Trailing whitespace. Invisible, and two of them are a Markdown line break, so a stray
#      pair silently changes rendering.
#   4. En dashes in headings. GitHub's anchor rules strip them, so "## A.1 - Foo" and
#      "## A.1 – Foo" generate *different* anchors, and ci/links.sh would then reject a link
#      that looks correct. Hyphens everywhere.
#   5. Balanced $$. An odd count means one block was opened and never closed, which renders the
#      rest of the file as mathematics.
#   6. Emoji. The sibling courses have none.
#   7. Em dashes. The house punctuation is a spaced hyphen. An em dash and a hyphen are
#      indistinguishable in a diff and in most editor fonts, so mixing them is drift nobody sees
#      until the two styles end up in adjacent paragraphs.
#   8. Table symmetry. Markdown renders a ragged table and a padded one identically, so this rule
#      is purely for whoever reads the source: every row of a table lines up its pipes, which
#      makes a column scannable in the file and makes a one-cell edit a one-cell diff.
#
# Usage:
#   markdown.sh
set -euo pipefail
shopt -s nullglob globstar

# Navigate to the root directory.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Rules 2 and 8 measure a line in *characters*, which is what a reader sees. gawk's length() and
# substr() count characters in a UTF-8 locale; mawk's count bytes, and mawk is what /usr/bin/awk
# is on a stock Ubuntu. Every arrow, en dash and superscript in the appendices is two or three
# bytes, so under mawk a 98-character line reports as 108 and a table with a superscript in it
# reports as ragged. That is the worst kind of check: green for whoever wrote the rule and red
# for the next person, on the platform the README tells them to use.
AWK="$(command -v gawk || true)"
if [ -z "$AWK" ]; then
    echo "error: gawk not found on PATH. The line-length and table rules count characters, and" >&2
    echo "       mawk counts bytes, so they are wrong without it. Install it with" >&2
    echo "       'sudo apt install gawk'." >&2
    exit 2
fi

failures=0
checked=0

# Report one violation and count it.
fail() {
    echo "$1" >&2
    failures=$((failures + 1))
}

for file in **/*.md; do
    # The kernel tree, QEMU and the root filesystem under build/ are somebody else's house style.
    case "$file" in
        build/*|.venv/*) continue ;;
    esac

    checked=$((checked + 1))

    # 1. Every image has non-empty alt text. Matches "![" followed immediately by "]".
    while IFS= read -r line; do
        fail "$file:$line: image has empty alt text"
    done < <(grep -n '!\[\]' "$file" | cut -d: -f1)

    # 2. Lines over 100 columns, outside fenced code and outside tables. A line holding a single
    #    unbreakable token longer than the limit -- a URL, a long path -- cannot be wrapped and is
    #    exempt; the test is whether any whitespace exists past column 80 that a wrap could have
    #    used.
    #
    #    A line that is nothing but an image is exempt too, and has to be: rule 1 above demands
    #    real alt text, Markdown gives an image no line-continuation syntax, and a sentence of
    #    alt text plus a path is routinely more than 100 characters. Wrapping is there so a diff
    #    shows which sentence changed, and an image line is already one atom.
    #
    #    Display mathematics is exempt for the same reason. A $$...$$ block is one expression,
    #    and breaking it across lines to satisfy a column limit makes the source harder to read
    #    rather than easier -- there is no sentence boundary in an equation to break at.
    while IFS= read -r line; do
        fail "$file:$line: line over 100 columns"
    done < <("$AWK" '
        /^[[:space:]]*```/ { fence = !fence; next }
        fence              { next }
        /^[[:space:]]*\|/  { next }                     # table row
        /^!\[.*\]\(.*\)$/  { next }                     # a line that is only an image
        {
            # Count the $$ delimiters on this line without disturbing it. Two or more means a
            # complete one-line block; exactly one opens or closes a multi-line one.
            copy = $0
            delimiters = gsub(/\$\$/, "&", copy)
        }
        delimiters >= 2 { next }
        delimiters == 1 { math = !math; next }
        math            { next }
        length($0) > 100 {
            tail = substr($0, 81)
            if (tail ~ /[[:space:]]/) print NR
        }' "$file")

    # 3. Trailing whitespace, outside fenced code.
    #
    #    Inside a fence it is content, not formatting. The golden listings quoted from program
    #    output carry whatever column padding printf produced, and rewriting them to satisfy a
    #    whitespace rule would mean the appendix no longer shows what the program prints.
    #    ci/numbers.sh compares those listings with trailing space stripped from both sides, so
    #    nothing downstream depends on it either way.
    while IFS= read -r line; do
        fail "$file:$line: trailing whitespace"
    done < <("$AWK" '
        /^[[:space:]]*```/ { fence = !fence; next }
        !fence && /[[:space:]]$/ { print NR }' "$file")

    # 4. En dash in an ATX heading. Fenced lines are skipped so a comment in a listing does not
    #    read as a heading, the same way ci/links.sh skips them.
    while IFS= read -r line; do
        fail "$file:$line: en dash in heading; use a hyphen (it changes the anchor)"
    done < <("$AWK" '
        /^[[:space:]]*```/ { fence = !fence; next }
        !fence && /^#{1,6} / && /–/ { print NR }' "$file")

    # 5. Balanced $$ display-math delimiters. The "|| true" is load-bearing under pipefail: a
    #    file with no mathematics in it makes grep exit 1, which would otherwise end the run.
    dollars=$({ grep -o '\$\$' "$file" || true; } | wc -l)
    if [ $((dollars % 2)) -ne 0 ]; then
        fail "$file: odd number of \$\$ delimiters ($dollars); a math block is unclosed"
    fi

    # 6. Emoji. Deliberately narrow: the pictographic planes only, so arrows, checkmarks and the
    #    box-drawing characters the ```text diagrams are made of all stay legal.
    while IFS= read -r line; do
        fail "$file:$line: emoji"
    done < <(grep -nP '[\x{1F000}-\x{1FAFF}\x{FE0F}]' "$file" | cut -d: -f1)

    # 7. Em dashes, outside fenced code. Fences are exempt because a listing quoted from a program
    #    shows what that program prints, and this rule is about prose.
    while IFS= read -r line; do
        fail "$file:$line: em dash; use a spaced hyphen"
    done < <("$AWK" '
        /^[[:space:]]*```/ { fence = !fence; next }
        !fence && /—/ { print NR }' "$file")

    # 8. Table symmetry. A table block is a maximal run of lines beginning with a pipe; every row
    #    in one must put its pipes at the same columns, and every cell must be padded with one
    #    space on each side. Comparing the pipe positions is enough to prove the block is
    #    rectangular, and it is the whole of what "aligned" means.
    #
    #    Checking columns rather than byte offsets matters: gawk in a UTF-8 locale counts
    #    characters, which is what a reader sees, and that is why this script insists on gawk
    #    rather than taking whatever /usr/bin/awk happens to be. A table with a superscript in
    #    it shifts every pipe to its right under a byte-counting awk, and the
    #    row reports as ragged. No table in the course contains a double-width glyph, and one
    #    appearing would be a legitimate thing for this rule to complain about.
    while IFS= read -r line; do
        fail "$file:$line"
    done < <("$AWK" '
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }

        # Not a table row: the block, if any, ended cleanly.
        !/^[[:space:]]*\|/ { rows = 0; next }

        {
            # The signature of a row is where its pipes are, and whether each is spaced.
            signature = ""
            width = length($0)
            for (i = 1; i <= width; i++)
            {
                if (substr($0, i, 1) != "|") { continue }
                signature = signature i ","

                # A pipe wants a space on the inside of the cell on either side of it. The two
                # ends of the row have nothing outside them, so they are only checked inwards.
                if (i > 1 && substr($0, i - 1, 1) != " ")
                {
                    print NR ": table cell touches its closing pipe; pad it with a space"
                }
                if (i < width && substr($0, i + 1, 1) != " ")
                {
                    print NR ": table cell touches its opening pipe; pad it with a space"
                }
            }

            if (rows == 0) { reference = signature; first = NR }
            else if (signature != reference)
            {
                print NR ": table row is not aligned with the row at line " first
            }
            rows++
        }' "$file")
done

if [ "$failures" -gt 0 ]; then
    echo >&2
    echo "error: $failures problem(s) in $checked Markdown file(s)." >&2
    exit 1
fi

echo "Markdown check: $checked file(s) pass."
