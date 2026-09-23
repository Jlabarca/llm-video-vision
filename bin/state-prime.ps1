#!/usr/bin/env pwsh
# bin/state-prime.ps1
# UserPromptSubmit hook.
# Reads the user prompt from stdin; if it mentions a phase ID like AUTH.4.2 or OAUTH-FLOW.1.1,
# emits a one-line "> Reminder: see docs/{IMPL}.md" hint on stdout (which Claude Code appends to the prompt).
# Always exits 0.

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
        Add-Content -Path $logFile -Value "$stamp state-prime UserPromptSubmit $Status $Message" -ErrorAction SilentlyContinue
    }
}

# Read prompt from stdin
$prompt = ''
if (-not [Console]::IsInputRedirected) {
    Write-HookLog 'noop' 'no stdin'
    exit 0
}
try {
    $prompt = [Console]::In.ReadToEnd()
} catch {
    Write-HookLog 'error' "stdin read failed: $($_.Exception.Message)"
    exit 0
}

if (-not $prompt) {
    Write-HookLog 'noop' 'empty prompt'
    exit 0
}

# Design-prompt trigger: a design/research/bootstrap prompt carries no phase ID, so it would
# otherwise fall straight through to the no-match exit. Inject a pointer to the shipped-capability
# index (docs/CAPABILITIES.md) so the session verifies negative / sole-existence claims before
# writing them. Runs BEFORE the phase-ID block (and does not exit). Tune the regex from logs.
$designRegex = '(?i)\b(redesign|design doc|research doc|bootstrap-impl|architecture|prior.?art)\b'
if ([System.Text.RegularExpressions.Regex]::IsMatch($prompt, $designRegex)) {
    # GDC.1.5 — existence guard: never advertise an index that isn't on disk.
    $capIndex = Join-Path $RepoRoot 'docs/CAPABILITIES.md'
    Write-Output ""
    if (Test-Path $capIndex) {
        Write-Output "> Reminder: shipped-capability index at [docs/CAPABILITIES.md](docs/CAPABILITIES.md) - verify any 'X has no Y' / 'only N producers' claim against it before writing (DOCS-PROTOCOL Rule 17)."
        Write-HookLog 'inject' 'design-prompt -> CAPABILITIES.md pointer'
    } else {
        Write-Output "> Reminder: shipped-capability index not seeded yet - create docs/CAPABILITIES.md via /promote-impl (create-with-header) or copy the template seed, then verify any 'X has no Y' claim against it (DOCS-PROTOCOL Rule 17)."
        Write-HookLog 'inject' 'design-prompt -> CAPABILITIES.md missing hint'
    }
    # GDC.4.1 — fleet scope: sibling repos' capability indexes, from
    # GHOSTDEV_EXTRA_CAPABILITY_ROOTS (semicolon-separated roots; statusline precedent).
    # Forward-slash string concat (not Join-Path) so ps1/sh output stays byte-identical.
    $extraRoots = $env:GHOSTDEV_EXTRA_CAPABILITY_ROOTS
    if ($extraRoots) {
        $found = @()
        foreach ($r in ($extraRoots -split ';')) {
            $r = $r.Trim().TrimEnd('/')
            if (-not $r) { continue }
            if (Test-Path "$r/docs/CAPABILITIES.md") { $found += "$r/docs/CAPABILITIES.md" }
        }
        if ($found.Count -gt 0) {
            Write-Output ("> Fleet capability indexes: {0}" -f ($found -join ', '))
            Write-HookLog 'inject' 'design-prompt -> fleet capability roots'
        }
    }
}

# Match phase ID pattern: WORD.N or WORD.N.N (e.g., AUTH.4.2, OAUTH-FLOW.1.1)
$phaseRegex = '\b([A-Z][A-Z0-9-]{1,30})\.\d+(?:\.\d+)?\b'
$matchInfo = [System.Text.RegularExpressions.Regex]::Match($prompt, $phaseRegex)
if (-not $matchInfo.Success) {
    Write-HookLog 'noop' 'no phase ID in prompt'
    exit 0
}

$prefix = $matchInfo.Groups[1].Value

$implDir = Join-Path $RepoRoot 'docs'
$candidates = Get-ChildItem -Path $implDir -Filter '*-IMPL.md' -ErrorAction SilentlyContinue

# Strategy: AUTH → AUTH-IMPL.md; OAUTH-FLOW → OAUTH-FLOW-IMPL.md or OAUTH-FLOW-MIGRATION-IMPL.md
$matchedImpl = $null
foreach ($impl in $candidates) {
    $base = [IO.Path]::GetFileNameWithoutExtension($impl.Name)
    $stem = $base -replace '-IMPL$', ''
    if ($stem -eq $prefix -or $stem.StartsWith($prefix) -or $prefix.StartsWith($stem.Substring(0, [Math]::Min($stem.Length, 4)))) {
        $matchedImpl = $impl.Name
        break
    }
}

if (-not $matchedImpl) {
    foreach ($impl in $candidates) {
        if ($impl.Name -match "(^|[-_])$prefix([-_]|\.|$)") {
            $matchedImpl = $impl.Name
            break
        }
    }
}

if ($matchedImpl) {
    Write-Output ""
    Write-Output "> Reminder: phase `"$($matchInfo.Value)`" is tracked in [docs/$matchedImpl](docs/$matchedImpl)."
    Write-HookLog 'inject' "phase=$($matchInfo.Value) impl=$matchedImpl"
} else {
    Write-HookLog 'noop' "phase=$($matchInfo.Value) no-impl-match"
}

exit 0
