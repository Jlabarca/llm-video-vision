#!/usr/bin/env pwsh
# bin/branch-reaper.ps1 -- list every agent branch with its PROOF CLASS, and optionally reap the
# classes whose proof is a graph fact. The PowerShell twin of branch-reaper.sh; same flags, same
# exit codes, same stdout shape.
# DOCS-PROTOCOL Rule 21.
#
# WHY A CLASS AND NOT "merged?". An agent run's work is often applied to the integration branch
# with `git apply` of a captured diff, so the branch's SHAs NEVER become ancestors of it. A
# reaper that tests only `merge-base --is-ancestor` therefore keeps every applied run forever,
# and the branch list grows without bound.
#
#   A  merged/empty  -- zero commits ahead of the integration branch. `git branch -d` is safe by
#                       construction (git itself refuses otherwise). REAPED under -Reap, unless
#                       the branch is YOUNGER than -Days or a worktree is registered on it.
#   C  applied       -- ahead > 0 but every commit is patch-equivalent on the integration branch
#                       (`git cherry` prints only `-`). REPORTED, never reaped.
#   U  unmerged      -- commits the integration branch does not have. NEVER reaped.
#   W  in-use        -- a worktree is registered on it. Skipped whatever else is true.
#
# INTEGRATION BRANCH (Rule 21): `develop`/`development` iff it exists and is not behind the
# default branch; else `main`, else `master`. A dead develop is reported once and ignored.

[CmdletBinding()]
param(
    [switch]$Reap,
    [int]$Days = 7,
    [switch]$Count,
    [string]$Repo,
    [string]$Prefix
)

$ErrorActionPreference = 'Stop'
if (-not $Repo) {
    $Repo = $env:GHOSTDEV_BRANCH_REAPER_REPO
    if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot/..").Path }
}
if (-not $Prefix) {
    $Prefix = $env:GHOSTDEV_AGENT_BRANCH_PREFIX
    if (-not $Prefix) { $Prefix = 'ghostdev/' }
}

function g { git -C $Repo @args }

# -- integration branch (Rule 21) ---------------------------------------------------
$default = $null
foreach ($c in @('main', 'master')) {
    g show-ref --verify --quiet "refs/heads/$c" 2>$null
    if ($LASTEXITCODE -eq 0) { $default = $c; break }
}
if (-not $default) {
    [Console]::Error.WriteLine("branch-reaper: no main/master in $Repo")
    exit 2
}
$integration = $default
$staleNote = ''
foreach ($c in @('develop', 'development')) {
    g show-ref --verify --quiet "refs/heads/$c" 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $behind = (g rev-list --count "$c..$default" 2>$null)
    if (-not $behind) { $behind = '0' }
    if ($behind -eq '0') {
        $integration = $c
    } else {
        $last = g log -1 --format=%cs $c
        $staleNote = "stale $c`: $behind behind $default, last commit $last -- delete or revive"
    }
}

# -- worktrees: branch -> in use ---------------------------------------------------
$inUse = @()
foreach ($line in (g worktree list --porcelain 2>$null)) {
    if ($line -match '^branch\s+refs/heads/(.+)$') { $inUse += $matches[1] }
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$cutoff = $now - ($Days * 86400)

$rows = @()
$reapable = 0
foreach ($b in (g for-each-ref --sort=committerdate --format='%(refname:short)' "refs/heads/$Prefix")) {
    if (-not $b) { continue }
    $ageS = [int64](g log -1 --format=%ct $b)
    $ageD = [int](($now - $ageS) / 86400)
    $ahead = (g rev-list --count "$integration..$b")
    if ($inUse -contains $b) {
        $cls = 'W'
    } elseif ($ahead -eq '0') {
        if ($ageS -gt $cutoff) { $cls = 'A-young' } else { $cls = 'A'; $reapable++ }
    } else {
        $cherry = @(g cherry $integration $b | Where-Object { $_ -notmatch '^-' })
        if ($cherry.Count -gt 0) { $cls = 'U' } else { $cls = 'C' }
    }
    $rows += [pscustomobject]@{ Class = $cls; Ahead = $ahead; Age = $ageD; Branch = $b }
}

if ($Count) { Write-Output $reapable; exit 0 }

$mode = if ($Reap) { 'REAP' } else { 'REPORT' }
Write-Output "branch-reaper: repo=$Repo integration=$integration prefix=$Prefix older-than=${Days}d mode=$mode"
if ($staleNote) { Write-Output "  $staleNote" }
Write-Output ('  {0,-8} {1,6} {2,5}  {3}' -f 'CLASS', 'AHEAD', 'AGE', 'BRANCH')
foreach ($r in $rows) {
    Write-Output ('  {0,-8} {1,6} {2,4}d  {3}' -f $r.Class, $r.Ahead, $r.Age, $r.Branch)
}
Write-Output "  total=$($rows.Count)  reapable(A, >${Days}d)=$reapable"

if ($Reap) {
    foreach ($r in $rows) {
        if ($r.Class -ne 'A') { continue }
        g branch -d $r.Branch 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Output "    reaped: $($r.Branch)" }
        else { Write-Output "    REFUSED by git -d (kept): $($r.Branch)" }
    }
} elseif ($reapable -ne 0) {
    Write-Output "branch-reaper: report only. Re-run with -Reap to delete class A (git branch -d, never -D)."
}
exit 0
