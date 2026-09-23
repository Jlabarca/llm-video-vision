#!/usr/bin/env bash
# bin/init-guard.sh — POSIX parity port of init-guard.ps1.
# Block `claude /init` in a repo with an existing CLAUDE.md. Careless-only gate:
# blocks by default (no warn ladder). Exit: 0 allow, 2 block.
# Policy: docs/research/hooks-policy.md.
set -u

REPO_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_DIR="$REPO_ROOT/logs/hooks"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
log() { [ -d "$LOG_DIR" ] && printf '%s init-guard PreToolUse %s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$1" "$2" >>"$LOG_FILE" 2>/dev/null; return 0; }

# Command: GHOSTDEV_INITGUARD_CMD override (testing) or stdin JSON (.tool_input.command).
CMD="${GHOSTDEV_INITGUARD_CMD:-}"
if [ -z "$CMD" ]; then
  RAW="$(cat 2>/dev/null || true)"
  CMD="$(printf '%s' "$RAW" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//; s/"$//')"
fi
[ -z "$CMD" ] && exit 0

# Only act on an actual `claude … /init` invocation.
printf '%s' "$CMD" | grep -Eiq 'claude[^|;&]*[[:space:]]/init([[:space:]]|$)' || exit 0

if [ ! -f "$REPO_ROOT/CLAUDE.md" ]; then
  log allow 'claude /init but no CLAUDE.md present'
  exit 0
fi

printf '%s\n' "[init-guard] BLOCKED 'claude /init' — it overwrites the curated CLAUDE.md. To change project instructions, edit CLAUDE.md directly or use /remember. (Override: run where no CLAUDE.md exists, or remove this hook.)" >&2
log block 'claude /init over existing CLAUDE.md'
exit 2
