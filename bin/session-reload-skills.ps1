#!/usr/bin/env pwsh
# bin/session-reload-skills.ps1
# SessionStart hook (CC-NATIVE-WINS.3). Tells Claude Code to re-scan .claude/skills/
# (and .claude/commands/) at session start so skills shipped since the last session
# load without a manual restart. Emits the documented SessionStart hookSpecificOutput
# JSON with reloadSkills=true. SessionStart cannot block; ALWAYS exits 0.
$ErrorActionPreference = 'SilentlyContinue'
try { [void][Console]::In.ReadToEnd() } catch { }   # drain stdin

$hookOut = @{
    hookEventName = 'SessionStart'
    reloadSkills  = $true
}

# DISCIPLINE-HARDENING.5 — surface the freshest auto-authored handoff so a cold start
# resumes from it (the auto-firing PreCompact handoff is useless if nobody loads it).
# Pointer only (not the body) to keep the injected context small; exclude the backstop.
$hd = Join-Path (Get-Location).Path 'docs/handoffs'
if (Test-Path $hd) {
    $latest = Get-ChildItem -Path $hd -Filter '*.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'precompact-backstop.md' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        $when = $latest.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        $hookOut.additionalContext = "Freshest handoff: docs/handoffs/$($latest.Name) (written $when). " +
            "If resuming, read it first — it has the active IMPL, phase, latest LOGBOOK entry, and uncommitted diff."
    }
}

$out = @{ hookSpecificOutput = $hookOut } | ConvertTo-Json -Compress
Write-Output $out
exit 0
