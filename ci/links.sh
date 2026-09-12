#!/usr/bin/env bash
#
# Check that every relative Markdown link resolves: the file exists, and where the link
# carries a #fragment, some heading in that file generates the matching anchor.
#
# The course is a web of cross-references between lecture READMEs, appendices and exercise
# directories, so renaming one file silently breaks links in three others.
#
# External http(s) links are not fetched: this runs offline and should not go stale because
# somebody else's site is down.
#
# Usage:
#   links.sh
set -euo pipefail
shopt -s nullglob globstar

# Navigate to the root directory.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# GitHub's anchor rules: lowercase, strip anything that is not a word character, a space or a
# hyphen, then turn spaces into hyphens.
anchor_of() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9 _-]//g' -e 's/ /-/g'
}

checked=0
broken=0

# Markdown files, and the C that documents itself in Markdown. The shipped lab headers and KUnit
# suites carry [text](path) links in their doc comments, pointing a reader at the appendix that
# specifies them, and scanning only *.md would leave those unchecked. A link is a link wherever
# it lives.
#
# build/ holds the kernel tree, QEMU and the root filesystem: hundreds of thousands of somebody
# else's Markdown files, none of it authored here.
for file in **/*.md **/*.c **/*.h; do
    case "$file" in
        build/*|.venv/*) continue ;;
    esac

    # Links are relative to the file that contains them, not to the repo root.
    dir="$(dirname "$file")"

    # Pull the target out of every inline [text](target) link.
    while IFS= read -r target; do
        # Skip external links, mailto:, and bare in-page fragments.
        #
        # The whitespace arm is what makes scanning C safe: an array of designated initialisers,
        # "[FOO] = (struct bar){ ... }", can match the same "](...)" shape as an inline link. No
        # Markdown link target can contain a bare space -- one that needs a space has to be
        # angle-bracketed or percent-encoded -- so anything with whitespace in it is not a link.
        case "$target" in
            http://*|https://*|mailto:*|\#*|'') continue ;;
            *[[:space:]]*) continue ;;
        esac

        # Split "path#fragment". With no "#", the second expansion returns the whole string,
        # which is how a fragment-less link is told apart from one with an empty fragment.
        path="${target%%\#*}"
        fragment="${target#*\#}"
        [ "$fragment" = "$target" ] && fragment=""

        checked=$((checked + 1))

        # A relative link that leaves the repository resolves only on a machine where the other
        # course happens to sit next door. CI clones this repository on its own, so such a link is
        # broken there however green it looks here, which is exactly the promise "make lint mirrors
        # CI" is supposed to keep. Name a sibling course by its URL instead.
        case "$(realpath -m --relative-to=. "$dir/$path")" in
            ../*)
                echo "ESCAPES $file -> $target (leaves the repository; use an absolute URL)" >&2
                broken=$((broken + 1))
                continue
                ;;
        esac

        resolved="$dir/$path"
        if [ ! -e "$resolved" ]; then
            echo "BROKEN $file -> $target (no such file: $resolved)" >&2
            broken=$((broken + 1))
            continue
        fi

        # Where the link names a heading, check that some heading generates that anchor.
        if [ -n "$fragment" ] && [ -f "$resolved" ]; then
            found=0
            while IFS= read -r heading; do
                if [ "$(anchor_of "$heading")" = "$fragment" ]; then
                    found=1
                    break
                fi
            # Every ATX heading in the target file, with its leading #s stripped. Lines inside a
            # fenced code block are skipped: a shell or YAML comment there starts with a # too,
            # and counting it as a heading would let a broken anchor resolve against a listing.
            done < <(awk '/^[[:space:]]*```/ { fence = !fence; next }
                          !fence && /^#{1,6} / { sub(/^#{1,6} +/, ""); print }' "$resolved")
            if [ "$found" -eq 0 ]; then
                echo "BROKEN $file -> $target (no heading matching #$fragment)" >&2
                broken=$((broken + 1))
            fi
        fi
    # Every inline link target in the file: match "](...)", then strip the delimiters. Reference
    # -style links are not used in this course, so the inline form is the whole of it. In a C doc
    # comment the same syntax appears inside a "*"-prefixed line, which changes nothing: the
    # match is on the link itself.
    done < <(grep -oE '\]\([^)]+\)' "$file" | sed -e 's/^](//' -e 's/)$//')
done

if [ "$broken" -gt 0 ]; then
    echo >&2
    echo "error: $broken broken link(s) out of $checked checked." >&2
    exit 1
fi

echo "Link check: $checked relative link(s) resolve."
