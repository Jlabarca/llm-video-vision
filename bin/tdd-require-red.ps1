#!/usr/bin/env pwsh
# bin/tdd-require-red.ps1
# GHOSTDEV_TDD_REQUIRE_RED (DISCIPLINE-HARDENING.3.1) — run ONE test target and assert
# it met an expected outcome. Opt-in (default off); invoked by /run-impl at the PHASE
# BOUNDARY, never in the per-Edit PreToolUse path (OQ2 — protects the hot keystroke loop).
# Closes the empty-`it('x',()=>{})` bypass: a symbol that never runs can't be Red.
#
# Usage: tdd-require-red.ps1 -Target <testfile> [-Expect red|green] [-PrintRunner]
#   -Expect red   : the test MUST fail   (the Red step) — exit 0 iff it failed
#   -Expect green : the test MUST pass   (the Green step) — exit 0 iff it passed
#   -PrintRunner  : print the detected runner command and exit 0 (no execution; testing)
# Exit: 0 expectation met · 1 cannot run/detect (warn) · 2 expectation NOT met (block).
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [ValidateSet('red', 'green')][string]$Expect = 'green',
    [switch]$PrintRunner,
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
)
$ErrorActionPreference = 'Stop'

# Detect the runner from the target's extension. Returns @(exe, args...) or $null.
$norm = ($Target -replace '\\', '/')
$ext = ([System.IO.Path]::GetExtension($norm)).ToLower()
$runner = switch ($ext) {
    '.py' { @('python', '-m', 'pytest', '-q', $Target) }
    { $_ -in '.ts', '.tsx', '.js', '.jsx' } { @('npx', '--no-install', 'vitest', 'run', $Target) }
    '.cs' { @('dotnet', 'test', '--nologo', '--filter', [System.IO.Path]::GetFileNameWithoutExtension($norm)) }
    default { $null }
}
if (-not $runner) {
    [Console]::Error.WriteLine("[require-red] no runner for '$Target' (.py/.ts/.tsx/.js/.jsx/.cs only) — cannot enforce")
    exit 1
}
if ($PrintRunner) { Write-Output ($runner -join ' '); exit 0 }

Push-Location $RepoRoot
try {
    & $runner[0] @($runner[1..($runner.Count - 1)]) *> $null
    $passed = ($LASTEXITCODE -eq 0)
}
catch {
    [Console]::Error.WriteLine("[require-red] runner failed to launch: $($_.Exception.Message)")
    Pop-Location; exit 1
}
Pop-Location

$want = ($Expect -eq 'green')   # green => want pass
if ($passed -eq $want) {
    [Console]::Error.WriteLine("[require-red] OK — '$Target' is $(if($passed){'GREEN'}else{'RED'}) as expected ($Expect)")
    exit 0
}
[Console]::Error.WriteLine("[require-red] FAIL — '$Target' is $(if($passed){'GREEN'}else{'RED'}); expected $Expect. " +
    $(if ($Expect -eq 'red') { 'A test that never fails pins nothing (empty-test bypass).' } else { 'Implementation does not make the test pass.' }))
exit 2
