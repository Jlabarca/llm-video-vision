#!/usr/bin/env bash
# bin/state-prime.sh
# UserPromptSubmit hook.
# Reads the user prompt from stdin; if it mentions a phase ID like AUTH.4.2,
# emits a one-line reminder on stdout pointing at the matching IMPL.
# Always exits 0.

set -e

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_DIR="$REPO_ROOT/.claude/logs/hooks"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/$TODAY.log"

log_hook() {
    local status="$1"
    local msg="$2"
    if [ -d "$LOG_DIR" ]; then
        echo "$(date -Iseconds) state-prime UserPromptSubmit $status $msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Read prompt from stdin
if [ -t 0 ]; then
    log_hook noop "no stdin"
    exit 0
fi

PROMPT=$(cat)
if [ -z "$PROMPT" ]; then
    log_hook noop "empty prompt"
    exit 0
fi

# Design-prompt trigger: a design/research/bootstrap prompt carries no phase ID, so it would
# otherwise fall straight through to the no-match exit. Inject a pointer to the shipped-capability
# index (docs/CAPABILITIES.md) so the session verifies negative / sole-existence claims before
# writing them. Runs BEFORE the phase-ID block (and does not exit). Tune the regex from logs.
if echo "$PROMPT" | grep -qiE '\b(redesign|design doc|research doc|bootstrap-impl|architecture|prior.?art)\b'; then
    # GDC.1.5 — existence guard: never advertise an index that isn't on disk.
    echo ""
    if [ -f "$REPO_ROOT/docs/CAPABILITIES.md" ]; then
        echo "> Reminder: shipped-capability index at [docs/CAPABILITIES.md](docs/CAPABILITIES.md) - verify any 'X has no Y' / 'only N producers' claim against it before writing (DOCS-PROTOCOL Rule 17)."
        log_hook inject "design-prompt -> CAPABILITIES.md pointer"
    else
        echo "> Reminder: shipped-capability index not seeded yet - create docs/CAPABILITIES.md via /promote-impl (create-with-header) or copy the template seed, then verify any 'X has no Y' claim against it (DOCS-PROTOCOL Rule 17)."
        log_hook inject "design-prompt -> CAPABILITIES.md missing hint"
    fi
    # GDC.4.1 — fleet scope: sibling repos' capability indexes, from
    # GHOSTDEV_EXTRA_CAPABILITY_ROOTS (semicolon-separated roots; statusline precedent).
    if [ -n "${GHOSTDEV_EXTRA_CAPABILITY_ROOTS:-}" ]; then
        found=""
        OLD_IFS="$IFS"; IFS=';'
        for r in $GHOSTDEV_EXTRA_CAPABILITY_ROOTS; do
            r=$(echo "$r" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s|/$||')
            [ -n "$r" ] || continue
            if [ -f "$r/docs/CAPABILITIES.md" ]; then
                if [ -n "$found" ]; then found="$found, $r/docs/CAPABILITIES.md"; else found="$r/docs/CAPABILITIES.md"; fi
            fi
        done
        IFS="$OLD_IFS"
        if [ -n "$found" ]; then
            echo "> Fleet capability indexes: $found"
            log_hook inject "design-prompt -> fleet capability roots"
        fi
    fi
fi

# Match phase ID pattern
PHASE_MATCH=$(echo "$PROMPT" | grep -oE '\b[A-Z][A-Z0-9-]{1,30}\.[0-9]+(\.[0-9]+)?\b' | head -n 1)
if [ -z "$PHASE_MATCH" ]; then
    log_hook noop "no phase ID in prompt"
    exit 0
fi

PREFIX=$(echo "$PHASE_MATCH" | sed -E 's/\.[0-9]+(\.[0-9]+)?$//')

# Find matching IMPL in docs/
IMPL_DIR="$REPO_ROOT/docs"
if [ ! -d "$IMPL_DIR" ]; then
    log_hook noop "no docs/ directory"
    exit 0
fi

MATCHED_IMPL=""
for impl in "$IMPL_DIR"/*-IMPL.md; do
    [ -f "$impl" ] || continue
    base=$(basename "$impl" .md)
    stem="${base%-IMPL}"
    # Match: stem == prefix, stem starts with prefix, or prefix starts with stem's first 4 chars
    stem_prefix="${stem:0:4}"
    if [ "$stem" = "$PREFIX" ] || [[ "$stem" == "$PREFIX"* ]] || [[ "$PREFIX" == "$stem_prefix"* ]]; then
        MATCHED_IMPL=$(basename "$impl")
        break
    fi
done

if [ -z "$MATCHED_IMPL" ]; then
    # Fallback — any IMPL whose name contains the prefix as a token
    for impl in "$IMPL_DIR"/*-IMPL.md; do
        [ -f "$impl" ] || continue
        name=$(basename "$impl")
        if echo "$name" | grep -qE "(^|[-_])${PREFIX}([-_]|\.|\$)"; then
            MATCHED_IMPL="$name"
            break
        fi
    done
fi

if [ -n "$MATCHED_IMPL" ]; then
    echo ""
    echo "> Reminder: phase \"$PHASE_MATCH\" is tracked in [docs/$MATCHED_IMPL](docs/$MATCHED_IMPL)."
    log_hook inject "phase=$PHASE_MATCH impl=$MATCHED_IMPL"
else
    log_hook noop "phase=$PHASE_MATCH no-impl-match"
fi

exit 0
