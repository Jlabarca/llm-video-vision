#!/usr/bin/env bash
# bin/tdd-require-red.sh — POSIX parity port of tdd-require-red.ps1.
# GHOSTDEV_TDD_REQUIRE_RED: run ONE test target and assert it met an expected outcome.
# Opt-in; invoked by /run-impl at the PHASE BOUNDARY (OQ2), never per-Edit.
#
# Usage: tdd-require-red.sh --target <testfile> [--expect red|green] [--print-runner] [--repo <root>]
# Exit: 0 expectation met · 1 cannot run/detect (warn) · 2 expectation NOT met (block).
set -u

TARGET=""; EXPECT="green"; PRINT_RUNNER=0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --expect) EXPECT="$2"; shift 2 ;;
    --print-runner) PRINT_RUNNER=1; shift ;;
    --repo) REPO_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -z "$TARGET" ] && { echo "[require-red] --target required" >&2; exit 1; }

NORM="$(printf '%s' "$TARGET" | tr '\\' '/')"
BASE="$(basename "$NORM")"
STEM="${BASE%.*}"   # strip one extension (parity with ps1 GetFileNameWithoutExtension)
case "$NORM" in
  *.py)
    RUNNER="python -m pytest -q $TARGET" ;;
  *.ts|*.tsx|*.js|*.jsx)
    RUNNER="npx --no-install vitest run $TARGET" ;;
  *.cs)
    RUNNER="dotnet test --nologo --filter $STEM" ;;
  *)
    echo "[require-red] no runner for '$TARGET' — only .py .ts .tsx .js .jsx .cs" >&2
    exit 1 ;;
esac
if [ "$PRINT_RUNNER" -eq 1 ]; then printf '%s\n' "$RUNNER"; exit 0; fi

( cd "$REPO_ROOT" && eval "$RUNNER" >/dev/null 2>&1 )
if [ $? -eq 0 ]; then PASSED=1; else PASSED=0; fi

WANT=0; [ "$EXPECT" = "green" ] && WANT=1   # green => want pass
if [ "$PASSED" -eq "$WANT" ]; then
  STATE=$([ "$PASSED" -eq 1 ] && echo GREEN || echo RED)
  echo "[require-red] OK — '$TARGET' is $STATE as expected ($EXPECT)" >&2
  exit 0
fi
STATE=$([ "$PASSED" -eq 1 ] && echo GREEN || echo RED)
if [ "$EXPECT" = "red" ]; then HINT="A test that never fails pins nothing (empty-test bypass)."; else HINT="Implementation does not make the test pass."; fi
echo "[require-red] FAIL — '$TARGET' is $STATE; expected $EXPECT. $HINT" >&2
exit 2
