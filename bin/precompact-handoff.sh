#!/usr/bin/env bash
# bin/precompact-handoff.sh
# PreCompact hook (CC-NATIVE-WINS.1 + DISCIPLINE-HARDENING.5) — POSIX twin of the .ps1.
# (a) snapshot the transcript to a gitignored backstop AND (b) auto-author a topic-keyed
# docs/handoffs/<FEATURE>.md from on-disk state (active IMPL + phase + LOGBOOK tail + diff)
# so the next session resumes without the operator remembering /handoff. Deterministic
# snapshot, not an LLM-compressed artifact. ALWAYS exits 0; never blocks compaction.
input=$(cat 2>/dev/null)

field() { printf '%s' "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 | sed 's/.*:[[:space:]]*"//;s/"$//'; }
tp=$(field transcript_path)
trigger=$(field trigger)
[ -z "$trigger" ] && trigger=unknown
cwd=$(pwd)

hd="$cwd/docs/handoffs"
mkdir -p "$hd" 2>/dev/null
stamp=$(date '+%Y-%m-%d %H:%M:%S')

# (a) Backstop snapshot (unchanged).
if [ -n "$tp" ] && [ -f "$tp" ]; then cp -f "$tp" "$hd/precompact-backstop.jsonl" 2>/dev/null; fi
cat > "$hd/precompact-backstop.md" 2>/dev/null <<EOF
# PreCompact backstop

> Auto-written by bin/precompact-handoff on context compaction. A deterministic safety
> net, NOT the smart /handoff artifact (a hook can't LLM-compress).

- when:       $stamp
- trigger:    $trigger compaction
- transcript: $tp
- snapshot:   docs/handoffs/precompact-backstop.jsonl (copy of the pre-compaction transcript)
EOF

# (b) Auto-author docs/handoffs/<FEATURE>.md from on-disk state.
feature=""; active_phase=""; impl_path=""
for f in $(ls -t docs/*-IMPL.md 2>/dev/null); do
  [ -f "$f" ] || continue
  line=$(grep -En '^- \[ \]' "$f" | head -n1 | sed 's/^[0-9]*://')
  [ -z "$line" ] && continue
  feature=$(basename "$f" | sed 's/-IMPL\.md$//')
  impl_path="$f"
  # Extract "PHASE.N.N — desc" (tolerate **bold** + em/hyphen dashes).
  active_phase=$(printf '%s' "$line" | sed -E 's/^- \[ \][[:space:]]*\*{0,2}([A-Z][A-Z0-9-]*\.[0-9]+(\.[0-9]+)?)\*{0,2}[[:space:]]*[—-]?[[:space:]]*(.*)$/\1 — \3/')
  break
done

if [ -n "$feature" ]; then
  log_tail=""
  if [ -f "$cwd/docs/LOGBOOK.md" ]; then
    start=$(grep -n '^## ' "$cwd/docs/LOGBOOK.md" | head -n1 | cut -d: -f1)
    [ -n "$start" ] && log_tail=$(sed -n "${start},$((start + 14))p" "$cwd/docs/LOGBOOK.md")
  fi
  git_stat=$(cd "$cwd" && git diff --stat HEAD 2>/dev/null)

  cat > "$hd/$feature.md" 2>/dev/null <<EOF
# Handoff — $feature

> Auto-authored by bin/precompact-handoff at $stamp (context compaction, $trigger).
> Deterministic snapshot of on-disk state — NOT an LLM-compressed /handoff. Re-run
> /handoff for a richer resume. Overwritten on each compaction (topic-keyed).

## Read first
1. $impl_path — the active tracker
2. docs/LOGBOOK.md — latest entry (excerpt below)
3. docs/CONTEXT.md — living state

## You are here
- Active phase: **$active_phase**
- IMPL: $impl_path

## Latest LOGBOOK entry
$log_tail

## Uncommitted work (git diff --stat HEAD)
\`\`\`
$git_stat
\`\`\`

## Resume prompt
Continue $feature from the first unchecked box ($active_phase). Read the IMPL + the
LOGBOOK excerpt above, verify the uncommitted diff, then proceed.
EOF
  echo "[precompact] context compacting ($trigger) - auto-authored docs/handoffs/$feature.md + backstop. Next session resumes from $active_phase." >&2
else
  echo "[precompact] context compacting ($trigger) - snapshot saved to docs/handoffs/precompact-backstop.*; run /handoff for a compressed resume." >&2
fi

exit 0
