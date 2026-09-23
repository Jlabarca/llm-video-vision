<#
.SYNOPSIS
  ghostdev init -- one-command first-time methodology install into a target project.

.DESCRIPTION
  The degit-adopter twin of `ware methodology-install` (no ware, no Python needed).
  Seeds the methodology tree SKIP-EXISTING (an existing file is NEVER overwritten),
  copies .claude/settings.example.json -> .claude/settings.json when absent, warns if
  the target's .gitignore swallows root bin/ (suggests '!/bin/'), and stamps the
  .ghostdev/version.json adopter marker.

  Template source = this script's parent directory (template root). Two ways to run:
    - from a GhostDev checkout:  pwsh template/bin/ghostdev-init.ps1 -Target <project> -Execute
    - post-degit, in-place:      pwsh bin/ghostdev-init.ps1 -Execute
      (source == target, so seeding reports all-skipped; settings/gitignore/marker still apply)

  DRY-RUN by default; nothing is written without -Execute. Safe to re-run (marker
  preserves the original `adopted` date). ASCII output.

.PARAMETER Target
  Project root to install into. Default: the template root itself (post-degit in-place).

.PARAMETER Execute
  Apply the install. Without it, print the plan only.

.PARAMETER Version
  Methodology version string for the marker. Default: `git describe --tags --always`
  of the template's repo when git is available, else "degit-unknown".

.PARAMETER GhostDevRepo
  Path to a GhostDev checkout; when it carries tools/ghostdev-mark.ps1 the real marker
  writer is delegated to (env fallback: GHOSTDEV_HOME). Otherwise a minimal schema-v1
  marker is written inline.

.PARAMETER Quiet
  Suppress per-file seed lines (summary lines still print).
#>
[CmdletBinding()]
param(
    [string]$Target,
    [switch]$Execute,
    [string]$Version,
    [string]$GhostDevRepo,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path

if (-not $Target) { $Target = $templateRoot }
if (-not (Test-Path $Target)) {
    Write-Error "target not found: $Target"
    exit 1
}
$Target = (Resolve-Path $Target).Path

$mode = if ($Execute) { 'execute' } else { 'dry-run' }
Write-Host "ghostdev-init: $mode target=$Target"

# ---- seed (skip-existing; never overwrite) ------------------------------------------------
$seeded = 0; $skipped = 0
$files = Get-ChildItem -Path $templateRoot -Recurse -File -Force | Sort-Object FullName
foreach ($f in $files) {
    $rel = $f.FullName.Substring($templateRoot.Length).TrimStart('\', '/')
    $out = Join-Path $Target $rel
    if (Test-Path $out) {
        $skipped++
        if (-not $Quiet) { Write-Host "  ~ skip    $rel (exists)" }
        continue
    }
    $seeded++
    if ($Execute) {
        $dir = Split-Path -Parent $out
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -Path $f.FullName -Destination $out
    }
    if (-not $Quiet) { Write-Host "  + seeded  $rel" }
}
Write-Host "seed:    $seeded seeded, $skipped skipped"

# ---- settings: example -> settings.json iff absent ----------------------------------------
$exampleT = Join-Path $Target '.claude/settings.example.json'
$exampleS = Join-Path $templateRoot '.claude/settings.example.json'
$example = if (Test-Path $exampleT) { $exampleT } elseif (Test-Path $exampleS) { $exampleS } else { $null }
$settingsDst = Join-Path $Target '.claude/settings.json'
if (-not $example) {
    $settingsOutcome = 'no-example'
} elseif (Test-Path $settingsDst) {
    $settingsOutcome = 'already-present'
} else {
    $settingsOutcome = 'copied'
    if ($Execute) {
        $dir = Split-Path -Parent $settingsDst
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -Path $example -Destination $settingsDst
    }
}
Write-Host "settings: $settingsOutcome"

# ---- gitignore guard: does root bin/ get swallowed? ----------------------------------------
$giPath = Join-Path $Target '.gitignore'
$giLine = 'gitignore: ok'
if (Test-Path $giPath) {
    $lastSwallow = $null; $lastNegate = $null; $n = 0
    foreach ($raw in (Get-Content -Path $giPath)) {
        $n++
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $norm = $line.TrimStart('!').Trim('/').ToLowerInvariant()
        if ($norm -ne 'bin') { continue }
        if ($line.StartsWith('!')) { $lastNegate = $n } else { $lastSwallow = $n }
    }
    if ($lastSwallow -and (-not $lastNegate -or $lastNegate -lt $lastSwallow)) {
        $giLine = "gitignore: WARN bin/ swallowed (line $lastSwallow) - add '!/bin/' to $giPath"
    }
}
Write-Host $giLine

# ---- marker: delegate to ghostdev-mark.ps1 when available, else inline schema-v1 -----------
if (-not $GhostDevRepo -and $env:GHOSTDEV_HOME) { $GhostDevRepo = $env:GHOSTDEV_HOME }
$markTool = $null
foreach ($cand in @(
        $(if ($GhostDevRepo) { Join-Path $GhostDevRepo 'tools/ghostdev-mark.ps1' }),
        (Join-Path $templateRoot '../tools/ghostdev-mark.ps1'))) {
    if ($cand -and (Test-Path $cand)) { $markTool = (Resolve-Path $cand).Path; break }
}

if (-not $Version) {
    $Version = 'degit-unknown'
    try {
        $d = (& git -C $templateRoot describe --tags --always 2>$null)
        if ($LASTEXITCODE -eq 0 -and $d) { $Version = $d.Trim() }
    } catch { }
}

$markerVerb = if ($Execute) { 'written' } else { 'would-write' }
if ($Execute) {
    if ($markTool) {
        & pwsh -NoProfile -File $markTool -Target $Target -Quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Error "ghostdev-mark failed (exit $LASTEXITCODE)"
            exit 1
        }
    } else {
        $markerDir = Join-Path $Target '.ghostdev'
        $markerPath = Join-Path $markerDir 'version.json'
        $today = (Get-Date).ToString('yyyy-MM-dd')
        $adopted = $today
        if (Test-Path $markerPath) {
            try {
                $existing = Get-Content -Raw -Path $markerPath | ConvertFrom-Json
                if ($existing.adopted) { $adopted = [string]$existing.adopted }
            } catch { }
        }
        $marker = [ordered]@{
            schema      = 1
            methodology = $Version
            source      = "waremoto/ghostdev@degit"
            adopted     = $adopted
            updated     = $today
            components  = [ordered]@{ rules = 0; skills = 0; hooks = 0; statusline = $false }
            surface     = @('docs/DOCS-PROTOCOL.md', '.claude/skills/', '.claude/settings.example.json', 'bin/')
        }
        if (-not (Test-Path $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
        ($marker | ConvertTo-Json -Depth 5) + "`n" | Set-Content -Path $markerPath -Encoding ascii -NoNewline
    }
}
Write-Host "marker:  $markerVerb .ghostdev/version.json [$Version]"

if ($Execute) {
    Write-Host 'done'
} else {
    Write-Host 'done (dry-run - re-run with -Execute to apply)'
}
exit 0
