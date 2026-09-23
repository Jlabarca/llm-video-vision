#!/usr/bin/env pwsh
# bin/check-impl-phase.ps1
# PreToolUse hook (Edit|Write matcher).
# Warn-mode by default: prints active IMPL phase ID to stderr, exits 0.
# Block-mode (env GHOSTDEV_HOOK_BLOCK=1 OR per-IMPL "block-mode: true" header flag):
#   exits 2 if active phase is found and edit appears off-target.
# Rules 22/23: four warn-only tracker-edit checks (evidence suffix, truncation, swallowed
#   code, foreign lock). They never block and never change the exit code.

param(
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
)

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $RepoRoot '.claude/logs/hooks'
$today = Get-Date -Format 'yyyy-MM-dd'
$logFile = Join-Path $logDir "$today.log"

function Write-HookLog {
    param([string]$Status, [string]$Message)
    if (Test-Path $logDir) {
        $stamp = (Get-Date).ToString('o')
        Add-Content -Path $logFile -Value "$stamp check-impl-phase PreToolUse $Status $Message" -ErrorAction SilentlyContinue
    }
}

# ── Tracker-edit checks (DOCS-PROTOCOL Rules 22 + 23). WARN ONLY — none of these blocks. ──
# Reads the PreToolUse stdin payload once. Four checks, one stderr line each:
#   (a) Rule 22 amendment — SWALLOWED CODE. A writer that eats newlines collapses a whole block
#       onto one line beginning with `//` or `#`, commenting every statement out. It COMPILES
#       (a comment always does), so no build gate can see it; the only witness is a test that
#       quietly stops running. This is why Rule 22 clause 2 is necessary and not sufficient.
#   (b) Rule 22 clause 1 — a `- [x]` line landing with no `— evidence:` / `by the operator` suffix.
#   (c) Rule 22 — a Write that would shrink a tracker to almost nothing (a tick script that
#       crashes mid-write truncates the file it was ticking).
#   (d) Rule 23 — the tracker's sibling `.<stem>.lock` is fresh (<2h) and held by another session,
#       and the edit touches a structural section (a checkbox line, a `### Phase` heading, a
#       status-table row). Append-only sections pass silently, per Rule 23's exception.
# False positives are logged as 'warn' so an adopter can count them before arming anything.
$__raw = $null
try { if (-not [Console]::IsInputRedirected) { $__raw = $null } else { $__raw = [Console]::In.ReadToEnd() } } catch { }
if ($__raw) {
    $__j = $null
    try { $__j = $__raw | ConvertFrom-Json -ErrorAction Stop } catch { }
    $__fp = $null
    if ($__j -and $__j.tool_input) { $__fp = $__j.tool_input.file_path }
    $__new = $null
    if ($__j -and $__j.tool_input) {
        if ($__j.tool_input.PSObject.Properties['content'])        { $__new = [string]$__j.tool_input.content }
        elseif ($__j.tool_input.PSObject.Properties['new_string']) { $__new = [string]$__j.tool_input.new_string }
    }
    # (a) swallowed code — any language, so this one is NOT scoped to trackers
    if ($__new -and $__fp -notmatch '\.(md|txt|json|ya?ml)$') {
        $__swallowed = @($__new -split "`r?`n" | Where-Object {
            $_.Length -gt 300 -and $_ -match '^\s*(//|#)' -and $_ -match ';\s' })
        if ($__swallowed.Count -gt 0) {
            [Console]::Error.WriteLine("[hook] Rule 22: $($__swallowed.Count) comment line(s) over 300 chars carrying statements in $([IO.Path]::GetFileName($__fp)) -- a newline-eating writer collapses a block behind its own comment marker and every statement in it is silently commented out. This compiles; only a run catches it.")
            Write-HookLog 'warn' "rule22-swallowed $([IO.Path]::GetFileName($__fp)) $($__swallowed.Count)"
        }
    }
    if ($__fp -and $__fp -match '-IMPL\.md$') {
        $__stem = [IO.Path]::GetFileNameWithoutExtension($__fp)
        # (b) evidence
        if ($__new) {
            $__bare = @($__new -split "`r?`n" | Where-Object { $_ -match '^\s*- \[x\]' -and $_ -notmatch '(evidence:|by the operator)' })
            if ($__bare.Count -gt 0) {
                [Console]::Error.WriteLine("[hook] Rule 22: $($__bare.Count) box(es) ticked with no '-- evidence:' suffix in $__stem.md -- a tick without evidence in the same commit is a claim, not a record")
                Write-HookLog 'warn' "rule22-evidence $__stem $($__bare.Count)"
            }
        }
        # (c) truncation
        if ($__j.tool_name -eq 'Write' -and $null -ne $__new -and (Test-Path $__fp)) {
            $__was = (Get-Item $__fp).Length
            if ($__was -gt 1000 -and $__new.Length -lt 200) {
                [Console]::Error.WriteLine("[hook] Rule 22: this Write would shrink $__stem.md from $__was bytes to $($__new.Length) -- a truncated tracker ticks nothing; check the writer's encoding")
                Write-HookLog 'warn' "rule22-truncate $__stem $__was->$($__new.Length)"
            }
        }
        # (d) foreign lock
        $__lock = Join-Path (Split-Path $__fp) ('.' + $__stem + '.lock')
        if ((Test-Path $__lock) -and $__new -and ($__new -match '(?m)^\s*- \[|^### Phase|^\| ')) {
            $__lt = Get-Content $__lock -Raw -ErrorAction SilentlyContinue
            $__sid = if ($__lt -match '(?m)^session:\s*(\S+)') { $matches[1] } else { 'unknown' }
            $__st  = if ($__lt -match '(?m)^started:\s*(\S+)') { $matches[1] } else { $null }
            $__fresh = $false
            if ($__st) { try { $__fresh = ((Get-Date).ToUniversalTime() - ([DateTime]::Parse($__st).ToUniversalTime())).TotalHours -lt 2 } catch { } }
            if ($__fresh -and $__sid -ne $env:CLAUDE_CODE_SESSION_ID) {
                [Console]::Error.WriteLine("[hook] Rule 23: $__stem.md is held by session $__sid (lock started $__st) -- one writer per tracker; append-only sections (a BUG entry, a dated Current State note) are fine, a checklist/phase/status edit is not")
                Write-HookLog 'warn' "rule23-lock $__stem $__sid"
            }
        }
    }
}

# Find active IMPL — first unchecked checkbox in any docs/*-IMPL.md
$implFiles = Get-ChildItem -Path (Join-Path $RepoRoot 'docs') -Filter '*-IMPL.md' -ErrorAction SilentlyContinue
if (-not $implFiles) {
    Write-HookLog 'noop' 'no IMPL files found'
    exit 0
}

$activePhase = $null
$activeImpl = $null
$activeBlockMode = $false
$activeDescription = ''

foreach ($impl in $implFiles | Sort-Object LastWriteTime -Descending) {
    $content = Get-Content $impl.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    # Check for per-IMPL block-mode flag
    $blockMode = $content -match '(?m)^>\s*block-mode:\s*true\s*$'

    # Find first unchecked checkbox with a phase ID like AUTH.4.2 or OAUTH-FLOW.1.1
    if ($content -match '(?m)^- \[ \]\s+\*?\*?([A-Z][A-Z0-9-]*\.\d+(?:\.\d+)?)\*?\*?\s+[—\-]\s+(.+)$') {
        $activePhase = $matches[1]
        $activeDescription = $matches[2].Trim()
        $activeImpl = $impl.Name
        $activeBlockMode = $blockMode
        break
    }
}

if (-not $activePhase) {
    Write-HookLog 'noop' 'all IMPL phases checked'
    exit 0
}

$line = "[hook] phase: $activePhase ($activeImpl) - $activeDescription"

# Decide warn vs block
# GHOSTDEV-RENAME.2: GHOSTDEV_HOOK_BLOCK is the current name; GHOST_HARNESS_* + MAREMOTO_METHOD_* are honored as legacy fallbacks.
$blockGlobal = ($env:GHOSTDEV_HOOK_BLOCK ?? $env:GHOST_HARNESS_HOOK_BLOCK ?? $env:MAREMOTO_METHOD_HOOK_BLOCK) -eq '1'
$shouldBlock = $blockGlobal -or $activeBlockMode

if ($shouldBlock) {
    [Console]::Error.WriteLine("$line [BLOCK MODE]")
    Write-HookLog 'block' "$activePhase ($activeImpl)"
    exit 2
} else {
    [Console]::Error.WriteLine($line)
    Write-HookLog 'warn' "$activePhase ($activeImpl)"
    exit 0
}
