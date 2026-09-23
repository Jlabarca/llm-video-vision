#!/usr/bin/env bash
# bin/tdd-test-gate.sh — POSIX parity port of tdd-test-gate.ps1.
# Same exit contract: 0 allow, 1 warn (stderr, tool proceeds), 2 block (tool refused).
# Contract: bin/fixtures/tdd-gate/README.md. Policy: docs/research/hooks-policy.md.
set -u

REPO_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_DIR="$REPO_ROOT/logs/hooks"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
log() { [ -d "$LOG_DIR" ] && printf '%s tdd-test-gate PreToolUse %s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$1" "$2" >>"$LOG_FILE" 2>/dev/null; return 0; }

# 1. Target path: GHOSTDEV_TDD_TARGET or stdin JSON (.tool_input.file_path).
#    Also capture session_id for graduated enforcement (step 6).
TARGET="${GHOSTDEV_TDD_TARGET:-}"
SESSION_ID="${GHOSTDEV_SESSION_ID:-}"
if [ -z "$TARGET" ]; then
  RAW="$(cat 2>/dev/null || true)"
  TARGET="$(printf '%s' "$RAW" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"$//')"
  [ -z "$SESSION_ID" ] && SESSION_ID="$(printf '%s' "$RAW" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"//; s/"$//')"
fi
[ -z "$SESSION_ID" ] && SESSION_ID='nosession'
[ -z "$TARGET" ] && { log noop 'no target path'; exit 0; }

# 2. Impl-path classification: code ext AND not a test path.
NORM="$(printf '%s' "$TARGET" | tr '\\' '/')"
case "$NORM" in
  *.cs|*.ts|*.tsx|*.js|*.jsx|*.py) IS_CODE=1 ;;
  *) IS_CODE=0 ;;
esac
IS_TEST=0
printf '%s' "$NORM" | grep -Eiq '(^|/)(tests?|__tests__)/|\.(test|spec)\.|(^|/)test_|_test\.' && IS_TEST=1
if [ "$IS_CODE" -ne 1 ] || [ "$IS_TEST" -eq 1 ]; then log noop "non-impl: $TARGET"; exit 0; fi

# 3. Active-IMPL gate (OQ1 proxy). Skipped in test mode (explicit diff file).
BLOCK_IMPL=0
if [ -z "${GHOSTDEV_TDD_DIFF_FILE:-}" ]; then
  ACTIVE=""
  for d in docs; do
    [ -d "$REPO_ROOT/$d" ] || continue
    for f in "$REPO_ROOT/$d"/*-IMPL.md; do
      [ -f "$f" ] || continue
      if grep -Eq '^- \[ \]' "$f"; then
        ACTIVE="$f"
        grep -Eq '^>[[:space:]]*block-mode:[[:space:]]*true[[:space:]]*$' "$f" && BLOCK_IMPL=1
        break
      fi
    done
    [ -n "$ACTIVE" ] && break
  done
  [ -z "$ACTIVE" ] && { log noop 'no active IMPL phase'; exit 0; }
fi

# 4. Session diff: explicit file (tests) or git diff since base (HEAD, or GHOSTDEV_TDD_BASE_REF).
if [ -n "${GHOSTDEV_TDD_DIFF_FILE:-}" ] && [ -f "${GHOSTDEV_TDD_DIFF_FILE}" ]; then
  DIFF="$(cat "$GHOSTDEV_TDD_DIFF_FILE")"
else
  BASE="${GHOSTDEV_TDD_BASE_REF:-HEAD}"
  DIFF="$(cd "$REPO_ROOT" && { git diff "$BASE" 2>/dev/null; git diff --cached 2>/dev/null; })"
fi

# 5. New test symbol on an added (+) line?
HAS_TEST=0
printf '%s\n' "$DIFF" | grep -E '^\+' | grep -Ev '^\+\+\+' | grep -Eq '(\bit\(|\bdescribe\(|\btest\(|\[Test\]|\[Fact\]|\bdef test_)' && HAS_TEST=1
if [ "$HAS_TEST" -eq 1 ]; then log allow "$TARGET (test symbol present)"; exit 0; fi

# 6. Violation — warn (1) or block (2). Explicit env/block-mode blocks immediately;
#    graduated enforcement (opt-in: GHOSTDEV_GRADUATED=1) warns the first violation this
#    SESSION and blocks repeats (§6.4 warn-fatigue fix).
MSG="[tdd-gate] $TARGET - no new test symbol in the session diff. Test-first not satisfied: add a failing test (Red), then the implementation (Green)."
EXPLICIT=0
REPEAT=0
if [ "${GHOSTDEV_GRADUATED:-}" = "1" ] && [ "$EXPLICIT" -eq 0 ]; then
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  SAFE_SID="$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_.-' '_')"
  COUNT_FILE="$LOG_DIR/tdd-violations-$SAFE_SID.count"
  N=0; [ -f "$COUNT_FILE" ] && N="$(tr -dc '0-9' < "$COUNT_FILE" 2>/dev/null || echo 0)"; [ -z "$N" ] && N=0
  N=$((N + 1)); printf '%s' "$N" > "$COUNT_FILE" 2>/dev/null || true
  [ "$N" -ge 2 ] && REPEAT=1
fi
if [ "$EXPLICIT" -eq 1 ]; then
  printf '%s [BLOCK]\n' "$MSG" >&2; log block "$TARGET"; exit 2
elif [ "$REPEAT" -eq 1 ]; then
  printf '%s [BLOCK: repeat violation this session]\n' "$MSG" >&2; log block "$TARGET"; exit 2
else
  printf '%s [warn]\n' "$MSG" >&2; log warn "$TARGET"; exit 1
fi
