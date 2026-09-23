#!/usr/bin/env pwsh
# bin/init-guard.ps1
# PreToolUse hook (Bash matcher) — block `claude /init` in a repo that already has a
# curated CLAUDE.md (running it overwrites the file). A CARELESS-ONLY gate, so it
# blocks by default (no warn ladder): there is no legitimate reason to /init over an
# existing CLAUDE.md. Exit: 0 allow, 2 block. Policy: docs/research/hooks-policy.md.
param(
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
)
$ErrorActionPreference = 'Stop'
$logDir = Join-Path $RepoRoot 'logs/hooks'
$logFile = Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd').log"
function Write-HookLog {
    param([string]$Status, [string]$Message)
    if (Test-Path $logDir) {
        Add-Content -Path $logFile -Value "$((Get-Date).ToString('o')) init-guard PreToolUse $Status $Message" -ErrorAction SilentlyContinue
    }
}

# Command: GHOSTDEV_INITGUARD_CMD override (testing) or stdin JSON (.tool_input.command).
$cmd = $env:GHOSTDEV_INITGUARD_CMD
if (-not $cmd) {
    try {
        $raw = [Console]::In.ReadToEnd()
        if ($raw) { $cmd = ($raw | ConvertFrom-Json -ErrorAction SilentlyContinue).tool_input.command }
    } catch { }
}
if (-not $cmd) { exit 0 }

# Only act on an actual `claude … /init` invocation (not e.g. a grep for the string).
if ($cmd -notmatch '(?i)\bclaude\b[^|;&`n]*\s/init(\s|$)') { exit 0 }

if (-not (Test-Path (Join-Path $RepoRoot 'CLAUDE.md'))) {
    Write-HookLog 'allow' 'claude /init but no CLAUDE.md present'
    exit 0
}

$msg = "[init-guard] BLOCKED ``claude /init`` — it overwrites the curated CLAUDE.md. " +
       "To change project instructions, edit CLAUDE.md directly or use /remember. " +
       "(Override: run where no CLAUDE.md exists, or remove this hook.)"
[Console]::Error.WriteLine($msg)
Write-HookLog 'block' 'claude /init over existing CLAUDE.md'
exit 2
