#!/usr/bin/env bash
# branch-reaper.sh -- list every agent branch with its PROOF CLASS, and optionally reap the
# classes whose proof is a graph fact.
# DOCS-PROTOCOL Rule 21.
#
# WHY A CLASS AND NOT "merged?". An agent run's work is often applied to the integration branch
# with `git apply` of a captured diff, so the branch's SHAs NEVER become ancestors of it. A
# reaper that tests only `merge-base --is-ancestor` therefore keeps every applied run forever,
# and the branch list grows without bound.
#
#   A  merged/empty  -- zero commits ahead of the integration branch. `git branch -d` is safe by
#                       construction (git itself refuses otherwise). REAPED under --reap, unless
#                       the branch is YOUNGER than --days (a run in flight has 0 ahead before
#                       its first commit) or a worktree is registered on it.
#   C  applied       -- ahead > 0 but every commit is patch-equivalent on the integration branch
#                       (`git cherry` prints only `-`). REPORTED, never reaped: patch-id
#                       equivalence is a heuristic, so a person decides.
#   U  unmerged      -- commits the integration branch does not have. NEVER reaped.
#   W  in-use        -- a worktree is registered on it. Skipped whatever else is true.
#
# INTEGRATION BRANCH (Rule 21): `develop`/`development` iff it exists and is not behind the
# default branch; else `main`, else `master`. A dead develop is reported once and ignored.
#
# Usage:
#   bash bin/branch-reaper.sh                     # report (default)
#   bash bin/branch-reaper.sh --reap              # delete class A older than --days
#   bash bin/branch-reaper.sh --days 3 --reap
#   bash bin/branch-reaper.sh --prefix agent/     # a different agent-branch prefix
#   bash bin/branch-reaper.sh --count             # ONE number: reapable class-A count
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${GHOSTDEV_BRANCH_REAPER_REPO:-$(dirname "$SCRIPT_DIR")}"
DAYS=7
REAP=0
COUNT_ONLY=0
PREFIX="${GHOSTDEV_AGENT_BRANCH_PREFIX:-ghostdev/}"

while [ $# -gt 0 ]; do
  case "$1" in
    --reap)     REAP=1; shift ;;
    --days)     DAYS="$2"; shift 2 ;;
    --days=*)   DAYS="${1#*=}"; shift ;;
    --count)    COUNT_ONLY=1; shift ;;
    --repo)     REPO_ROOT="$2"; shift 2 ;;
    --prefix)   PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    -h|--help)  grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "branch-reaper: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

g() { git -C "$REPO_ROOT" "$@"; }

# -- integration branch (Rule 21) ---------------------------------------------------
default_branch=""
for c in main master; do g show-ref --verify --quiet "refs/heads/$c" && { default_branch="$c"; break; }; done
[ -n "$default_branch" ] || { echo "branch-reaper: no main/master in $REPO_ROOT" >&2; exit 2; }
integration="$default_branch"
stale_note=""
for c in develop development; do
  if g show-ref --verify --quiet "refs/heads/$c"; then
    behind="$(g rev-list --count "$c..$default_branch" 2>/dev/null || echo 0)"
    if [ "$behind" = "0" ]; then integration="$c"
    else stale_note="stale $c: $behind behind $default_branch, last commit $(g log -1 --format=%cs "$c") -- delete or revive"; fi
  fi
done

# -- worktrees: branch -> in use ---------------------------------------------------
in_use="$(g worktree list --porcelain 2>/dev/null | awk '/^branch /{sub("refs/heads/","",$2); print $2}')"

now="$(date -u +%s)"
cutoff=$(( now - DAYS*86400 ))

rows=()
n_reapable=0
while IFS= read -r b; do
  [ -n "$b" ] || continue
  age_s="$(g log -1 --format=%ct "$b")"
  age_d=$(( (now - age_s) / 86400 ))
  ahead="$(g rev-list --count "$integration..$b")"
  cls=""
  if printf '%s\n' "$in_use" | grep -qx "$b"; then
    cls="W"
  elif [ "$ahead" = "0" ]; then
    if [ "$age_s" -gt "$cutoff" ]; then cls="A-young"; else cls="A"; n_reapable=$((n_reapable+1)); fi
  else
    if g cherry "$integration" "$b" | grep -qv '^-'; then cls="U"; else cls="C"; fi
  fi
  rows+=("$cls|$ahead|$age_d|$b")
done < <(g for-each-ref --sort=committerdate --format='%(refname:short)' "refs/heads/$PREFIX")

if [ "$COUNT_ONLY" = 1 ]; then echo "$n_reapable"; exit 0; fi

echo "branch-reaper: repo=$REPO_ROOT integration=$integration prefix=$PREFIX older-than=${DAYS}d mode=$([ "$REAP" = 1 ] && echo REAP || echo REPORT)"
[ -z "$stale_note" ] || echo "  $stale_note"
printf '  %-8s %6s %5s  %s\n' CLASS AHEAD AGE BRANCH
for r in ${rows[@]+"${rows[@]}"}; do
  IFS='|' read -r cls ahead age b <<<"$r"
  printf '  %-8s %6s %4sd  %s\n' "$cls" "$ahead" "$age" "$b"
done
echo "  total=${#rows[@]}  reapable(A, >${DAYS}d)=$n_reapable"

if [ "$REAP" = 1 ]; then
  for r in ${rows[@]+"${rows[@]}"}; do
    IFS='|' read -r cls ahead age b <<<"$r"
    [ "$cls" = "A" ] || continue
    if g branch -d "$b" >/dev/null 2>&1; then echo "    reaped: $b"; else echo "    REFUSED by git -d (kept): $b"; fi
  done
else
  [ "$n_reapable" = 0 ] || echo "branch-reaper: report only. Re-run with --reap to delete class A (git branch -d, never -D)."
fi
exit 0
