#!/usr/bin/env pwsh
# bin/audit-logbook.ps1
# Stop hook.
# Warns to stderr if the session changed code/docs but didn't append to LOGBOOK.md.
# Always exits 0 (Stop hooks can't block; only warn).

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
        Add-Content -Path $logFile -Value "$stamp audit-logbook Stop $Status $Message" -ErrorAction SilentlyContinue
    }
}

Push-Location $RepoRoot
try {
    $statusOutput = git status --porcelain 2>$null
    if (-not $statusOutput) {
        Write-HookLog 'noop' 'clean working tree'
        exit 0
    }

    $changedPaths = @()
    foreach ($line in ($statusOutput -split "`n")) {
        if ($line.Length -ge 4) {
            $path = $line.Substring(3).Trim()
            if ($path) { $changedPaths += $path }
        }
    }

    if ($changedPaths.Count -eq 0) {
        Write-HookLog 'noop' 'no changed paths'
        exit 0
    }

    $logbookTouched = $changedPaths | Where-Object {
        $_ -match 'LOGBOOK\.md$'
    }

    $otherTouched = $changedPaths | Where-Object {
        $_ -notmatch 'LOGBOOK\.md$' -and $_ -notmatch '^\.claude/logs/' -and $_ -notmatch '\.lock$'
    }

    if ($otherTouched -and -not $logbookTouched) {
        $count = ($otherTouched | Measure-Object).Count
        $sample = ($otherTouched | Select-Object -First 3) -join ', '
        $msg = "[hook] $count file(s) changed, no LOGBOOK entry. Consider /logbook-append. Sample: $sample"
        [Console]::Error.WriteLine($msg)
        Write-HookLog 'warn' "no-logbook count=$count"
    } else {
        Write-HookLog 'noop' "logbook-touched=$([bool]$logbookTouched) other-touched=$([bool]$otherTouched)"
    }

    exit 0
}
finally {
    Pop-Location
}
