#!/usr/bin/env bash
# bin/session-reload-skills.sh
# SessionStart hook (CC-NATIVE-WINS.3 + DISCIPLINE-HARDENING.5) — POSIX twin of the .ps1.
# Emits reloadSkills=true AND, if an auto-authored handoff exists, an additionalContext
# pointer to the freshest one so a cold start resumes from it. Cannot block; ALWAYS exits 0.
cat >/dev/null 2>&1   # drain stdin

hd="$(pwd)/docs/handoffs"
latest=""
if [ -d "$hd" ]; then
  for f in $(ls -t "$hd"/*.md 2>/dev/null); do
    case "$(basename "$f")" in precompact-backstop.md) continue ;; esac
    latest="$f"; break
  done
fi

if [ -n "$latest" ]; then
  rel="docs/handoffs/$(basename "$latest")"
  when=$(date -r "$latest" '+%Y-%m-%d %H:%M' 2>/dev/null || echo recent)
  ctx="Freshest handoff: $rel (written $when). If resuming, read it first — it has the active IMPL, phase, latest LOGBOOK entry, and uncommitted diff."
  # Escape for JSON (backslash, double-quote).
  esc=$(printf '%s' "$ctx" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"reloadSkills\":true,\"additionalContext\":\"$esc\"}}"
else
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","reloadSkills":true}}'
fi
exit 0
