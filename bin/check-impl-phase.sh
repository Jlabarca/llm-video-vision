#!/usr/bin/env bash
# bin/check-impl-phase.sh
# PreToolUse hook (Edit|Write matcher).
# Warn-mode by default: prints active IMPL phase ID to stderr, exits 0.
# Block-mode (env GHOSTDEV_HOOK_BLOCK=1 OR per-IMPL "block-mode: true" flag): exit 2.
# Rules 22/23: four warn-only tracker-edit checks (evidence suffix, truncation, swallowed
#   code, foreign lock). They never block and never change the exit code.

set -e

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_DIR="$REPO_ROOT/.claude/logs/hooks"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/$TODAY.log"

log_hook() {
    local status="$1"
    local msg="$2"
    if [ -d "$LOG_DIR" ]; then
        echo "$(date -Iseconds) check-impl-phase PreToolUse $status $msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# ── Tracker-edit checks (DOCS-PROTOCOL Rules 22 + 23). WARN ONLY — none of these blocks. ──
# The POSIX twin of the block in check-impl-phase.ps1; the two must stay behaviourally identical.
#   (a) Rule 22 amendment — SWALLOWED CODE. A writer that eats newlines collapses a whole block
#       onto one line beginning with `//` or `#`, commenting every statement out. It COMPILES
#       (a comment always does), so no build gate can see it; the only witness is a test that
#       quietly stops running. This is why Rule 22 clause 2 is necessary and not sufficient.
#   (b) Rule 22 clause 1 — a `- [x]` line landing with no `— evidence:` / `by the operator` suffix.
#   (c) Rule 22 — a Write that would shrink a tracker to almost nothing.
#   (d) Rule 23 — the tracker's sibling `.<stem>.lock` is fresh (<2h) and held by another session,
#       and the edit touches a structural section. Append-only sections pass silently.
# Needs a JSON parser (python3 or jq). Without one the checks are UNAVAILABLE, and that says so
# on stderr rather than passing quietly — a check that fails silently reads as a check that passed.
__RAW=""
if [ ! -t 0 ]; then __RAW=$(cat 2>/dev/null || true); fi
if [ -n "$__RAW" ]; then
    __TMP="${TMPDIR:-/tmp}/ghostdev-hook-$$"
    __TOOL=""
    __FP=""
    __PARSED=0
    __PY=""
    if command -v python3 >/dev/null 2>&1; then __PY=python3
    elif command -v python >/dev/null 2>&1; then __PY=python
    fi
    if [ -n "$__PY" ]; then
        # The extractor goes to a file rather than `python -c`: some Windows python shims
        # (pyenv-win) mangle -c when invoked from a POSIX shell, and a mangled extractor
        # would disable all four checks silently.
        __PYF="$__TMP.py"
        cat > "$__PYF" <<'__GHOSTDEV_PY__'
import json, sys
d = json.load(sys.stdin)
ti = d.get("tool_input") or {}
c = ti.get("content")
if c is None:
    c = ti.get("new_string")
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write(c if isinstance(c, str) else "")
print(d.get("tool_name") or "")
print(ti.get("file_path") or "")
__GHOSTDEV_PY__
        if __META=$(printf '%s' "$__RAW" | "$__PY" "$__PYF" "$__TMP" 2>/dev/null); then
            __PARSED=1
            __TOOL=$(printf '%s\n' "$__META" | sed -n '1p' | tr -d '\r')
            __FP=$(printf '%s\n' "$__META" | sed -n '2p' | tr -d '\r')
        fi
        rm -f "$__PYF" 2>/dev/null || true
    elif command -v jq >/dev/null 2>&1; then
        __TOOL=$(printf '%s' "$__RAW" | jq -r '.tool_name // ""' 2>/dev/null || true)
        __FP=$(printf '%s' "$__RAW" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
        if printf '%s' "$__RAW" | jq -j '.tool_input.content // .tool_input.new_string // ""' > "$__TMP" 2>/dev/null; then __PARSED=1; fi
    else
        echo "[hook] Rules 22/23 tracker checks UNAVAILABLE: no python3 and no jq on PATH -- the evidence, truncation, swallowed-code and lock warnings are not running" >&2
        log_hook degraded "no json parser"
    fi

    if [ "$__PARSED" = "1" ] && [ -s "$__TMP" ]; then
        __BASE=$(basename "$__FP")
        # (a) swallowed code — any language, so this one is NOT scoped to trackers
        case "$__BASE" in
            *.md|*.txt|*.json|*.yaml|*.yml) ;;
            *)
                __SW=$(awk 'length($0) > 300 && /^[[:space:]]*(\/\/|#)/ && /;[[:space:]]/ { n++ } END { print n+0 }' "$__TMP")
                if [ "$__SW" -gt 0 ] 2>/dev/null; then
                    echo "[hook] Rule 22: $__SW comment line(s) over 300 chars carrying statements in $__BASE -- a newline-eating writer collapses a block behind its own comment marker and every statement in it is silently commented out. This compiles; only a run catches it." >&2
                    log_hook warn "rule22-swallowed $__BASE $__SW"
                fi
                ;;
        esac

        case "$__FP" in
            *-IMPL.md)
                __STEM=$(basename "$__FP" .md)
                # (b) evidence
                __BARE=$(awk '/^[[:space:]]*- \[x\]/ && !/evidence:/ && !/by the operator/ { n++ } END { print n+0 }' "$__TMP")
                if [ "$__BARE" -gt 0 ] 2>/dev/null; then
                    echo "[hook] Rule 22: $__BARE box(es) ticked with no '-- evidence:' suffix in $__STEM.md -- a tick without evidence in the same commit is a claim, not a record" >&2
                    log_hook warn "rule22-evidence $__STEM $__BARE"
                fi
                # (c) truncation
                if [ "$__TOOL" = "Write" ] && [ -f "$__FP" ]; then
                    __WAS=$(wc -c < "$__FP" | tr -d ' ')
                    __NOWLEN=$(wc -c < "$__TMP" | tr -d ' ')
                    if [ "$__WAS" -gt 1000 ] && [ "$__NOWLEN" -lt 200 ]; then
                        echo "[hook] Rule 22: this Write would shrink $__STEM.md from $__WAS bytes to $__NOWLEN -- a truncated tracker ticks nothing; check the writer's encoding" >&2
                        log_hook warn "rule22-truncate $__STEM $__WAS->$__NOWLEN"
                    fi
                fi
                # (d) foreign lock
                __LOCK="$(dirname "$__FP")/.$__STEM.lock"
                if [ -f "$__LOCK" ] && grep -qE '^[[:space:]]*- \[|^### Phase|^\| ' "$__TMP" 2>/dev/null; then
                    __SID=$(sed -n 's/^session:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$__LOCK" | head -1)
                    [ -n "$__SID" ] || __SID="unknown"
                    __ST=$(sed -n 's/^started:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$__LOCK" | head -1)
                    __EPOCH=""
                    if [ -n "$__ST" ]; then
                        __STC="${__ST%%.*}"; __STC="${__STC%Z}"
                        __EPOCH=$(date -d "$__ST" +%s 2>/dev/null \
                                  || date -u -j -f '%Y-%m-%dT%H:%M:%S' "$__STC" +%s 2>/dev/null \
                                  || echo "")
                    fi
                    if [ -n "$__EPOCH" ]; then
                        __AGE=$(( $(date -u +%s) - __EPOCH ))
                        if [ "$__AGE" -lt 7200 ] && [ "$__SID" != "${CLAUDE_CODE_SESSION_ID:-}" ]; then
                            echo "[hook] Rule 23: $__STEM.md is held by session $__SID (lock started $__ST) -- one writer per tracker; append-only sections (a BUG entry, a dated Current State note) are fine, a checklist/phase/status edit is not" >&2
                            log_hook warn "rule23-lock $__STEM $__SID"
                        fi
                    fi
                fi
                ;;
        esac
    fi
    rm -f "$__TMP" 2>/dev/null || true
fi

# Find IMPL files in docs/
if [ ! -d "$REPO_ROOT/docs" ]; then
    log_hook noop "no docs/ directory"
    exit 0
fi

# Sort IMPL files by mtime desc
IMPL_LIST=$(find "$REPO_ROOT/docs" -maxdepth 1 -type f -name '*-IMPL.md' 2>/dev/null | \
            while read -r f; do
                mtime=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null)
                echo "$mtime|$f"
            done | sort -t'|' -k1 -n -r | cut -d'|' -f2)

if [ -z "$IMPL_LIST" ]; then
    log_hook noop "no IMPL files found"
    exit 0
fi

ACTIVE_PHASE=""
ACTIVE_IMPL=""
ACTIVE_DESC=""
ACTIVE_BLOCK_MODE=0

while IFS= read -r impl; do
    # Check for per-IMPL block-mode flag
    BLOCK_MODE=0
    if grep -qE '^>\s*block-mode:\s*true\s*$' "$impl" 2>/dev/null; then
        BLOCK_MODE=1
    fi

    # First unchecked checkbox with phase ID
    LINE=$(grep -m 1 -E '^- \[ \] \*?\*?[A-Z][A-Z0-9-]*\.[0-9]+(\.[0-9]+)?\*?\*?\s+[—-]\s+' "$impl" 2>/dev/null || true)
    if [ -n "$LINE" ]; then
        ACTIVE_PHASE=$(echo "$LINE" | sed -E 's/^- \[ \] \*?\*?([A-Z][A-Z0-9-]*\.[0-9]+(\.[0-9]+)?)\*?\*?.*/\1/')
        ACTIVE_DESC=$(echo "$LINE" | sed -E 's/^- \[ \] \*?\*?[A-Z][A-Z0-9-]*\.[0-9]+(\.[0-9]+)?\*?\*?\s+[—-]\s+(.*)$/\2/')
        ACTIVE_IMPL=$(basename "$impl")
        ACTIVE_BLOCK_MODE=$BLOCK_MODE
        break
    fi
done <<< "$IMPL_LIST"

if [ -z "$ACTIVE_PHASE" ]; then
    log_hook noop "all IMPL phases checked"
    exit 0
fi

LINE="[hook] phase: $ACTIVE_PHASE ($ACTIVE_IMPL) - $ACTIVE_DESC"

# Decide warn vs block
SHOULD_BLOCK=0
# GHOSTDEV-RENAME.2: GHOSTDEV_HOOK_BLOCK current; GHOST_HARNESS_*/MAREMOTO_METHOD_* legacy fallbacks.
HOOK_BLOCK="${GHOSTDEV_HOOK_BLOCK:-${GHOST_HARNESS_HOOK_BLOCK:-${MAREMOTO_METHOD_HOOK_BLOCK:-0}}}"
if [ "$HOOK_BLOCK" = "1" ] || [ "$ACTIVE_BLOCK_MODE" = "1" ]; then
    SHOULD_BLOCK=1
fi

if [ "$SHOULD_BLOCK" = "1" ]; then
    echo "$LINE [BLOCK MODE]" >&2
    log_hook block "$ACTIVE_PHASE ($ACTIVE_IMPL)"
    exit 2
else
    echo "$LINE" >&2
    log_hook warn "$ACTIVE_PHASE ($ACTIVE_IMPL)"
    exit 0
fi
