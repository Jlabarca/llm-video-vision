#!/usr/bin/env bash
# bin/statusline.sh
# Custom statusLine command (POSIX bash port of statusline.ps1).
# Outputs a single line: `phase: AUTH.2.1` (or empty if no active IMPL phase).
# Reads JSON input from stdin per Claude Code statusLine contract; ignored.
# Picks the most-recently-touched *-IMPL.md with an open checkbox.

set -e

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Drain stdin (Claude Code sends a JSON blob; we don't use it)
if [ ! -t 0 ]; then
    cat > /dev/null 2>&1 || true
fi

if [ ! -d "$REPO_ROOT" ]; then
    exit 0
fi

# Build the find expression: skip excluded dirs, then *-IMPL.md files
# Out-of-tree IMPLs via $GHOSTDEV_EXTRA_IMPL_ROOTS (semicolon-separated;
# GHOST_HARNESS_*/MAREMOTO_METHOD_* honored as legacy fallbacks)
ROOTS=("$REPO_ROOT")
EXTRA_ROOTS="${GHOSTDEV_EXTRA_IMPL_ROOTS:-${GHOST_HARNESS_EXTRA_IMPL_ROOTS:-${MAREMOTO_METHOD_EXTRA_IMPL_ROOTS:-}}}"
if [ -n "$EXTRA_ROOTS" ]; then
    IFS=';' read -ra EXTRA <<< "$EXTRA_ROOTS"
    for extra in "${EXTRA[@]}"; do
        extra="${extra#"${extra%%[![:space:]]*}"}"
        extra="${extra%"${extra##*[![:space:]]}"}"
        if [ -n "$extra" ] && [ -d "$extra" ]; then
            ROOTS+=("$extra")
        fi
    done
fi

# Collect candidate IMPL files with their mtimes
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

for root in "${ROOTS[@]}"; do
    find "$root" \
        \( -path '*/node_modules' -o -path '*/bin' -o -path '*/obj' -o -path '*/.git' -o -path '*/.idea' -o -path '*/impl/planned' \) -prune -o \
        -type f -name '*-IMPL.md' -print 2>/dev/null | while read -r f; do
        mtime=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null)
        if [ -n "$mtime" ]; then
            echo "$mtime|$f" >> "$TMPFILE"
        fi
    done
done

if [ ! -s "$TMPFILE" ]; then
    exit 0
fi

# Sort by mtime desc; for each, look for first unchecked checkbox with phase-ID grammar
sort -t'|' -k1 -n -r "$TMPFILE" | while IFS='|' read -r mtime file; do
    phase=$(grep -m 1 -E '^- \[ \] \*?\*?[A-Z][A-Z0-9-]*\.[0-9]+(\.[0-9]+)?\*?\*?' "$file" 2>/dev/null | \
            sed -E 's/^- \[ \] \*?\*?([A-Z][A-Z0-9-]*\.[0-9]+(\.[0-9]+)?)\*?\*?.*/\1/' | head -n 1)
    if [ -n "$phase" ]; then
        echo "phase: $phase"
        exit 0
    fi
done

exit 0
