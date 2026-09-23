#!/usr/bin/env bash
# bin/audit-logbook.sh
# Stop hook.
# Warns to stderr if the session changed code/docs but didn't append to LOGBOOK.md.
# Always exits 0 (Stop hooks can't block; only warn).

set -e

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_DIR="$REPO_ROOT/.claude/logs/hooks"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/$TODAY.log"

log_hook() {
    local status="$1"
    local msg="$2"
    if [ -d "$LOG_DIR" ]; then
        echo "$(date -Iseconds) audit-logbook Stop $status $msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

cd "$REPO_ROOT"

STATUS_OUTPUT=$(git status --porcelain 2>/dev/null || true)
if [ -z "$STATUS_OUTPUT" ]; then
    log_hook noop "clean working tree"
    exit 0
fi

# Extract paths (skip the XY status chars + space)
CHANGED_PATHS=$(echo "$STATUS_OUTPUT" | awk '{$1=""; sub(/^ /, ""); print}')

if [ -z "$CHANGED_PATHS" ]; then
    log_hook noop "no changed paths"
    exit 0
fi

LOGBOOK_TOUCHED=$(echo "$CHANGED_PATHS" | grep -E 'LOGBOOK\.md$' || true)
OTHER_TOUCHED=$(echo "$CHANGED_PATHS" | grep -vE 'LOGBOOK\.md$|^\.claude/logs/|\.lock$' || true)

if [ -n "$OTHER_TOUCHED" ] && [ -z "$LOGBOOK_TOUCHED" ]; then
    COUNT=$(echo "$OTHER_TOUCHED" | wc -l | tr -d ' ')
    SAMPLE=$(echo "$OTHER_TOUCHED" | head -n 3 | tr '\n' ', ' | sed 's/, $//')
    echo "[hook] $COUNT file(s) changed, no LOGBOOK entry. Consider /logbook-append. Sample: $SAMPLE" >&2
    log_hook warn "no-logbook count=$COUNT"
else
    LB_FLAG=$([ -n "$LOGBOOK_TOUCHED" ] && echo true || echo false)
    OT_FLAG=$([ -n "$OTHER_TOUCHED" ] && echo true || echo false)
    log_hook noop "logbook-touched=$LB_FLAG other-touched=$OT_FLAG"
fi

exit 0
