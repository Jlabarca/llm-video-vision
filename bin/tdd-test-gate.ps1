#!/usr/bin/env pwsh
# bin/tdd-test-gate.ps1
# PreToolUse hook (Edit|Write matcher) — TDD back-pressure (Pocock /tdd).
# Warns/blocks a Write|Edit to an IMPLEMENTATION file when no new test symbol was
# added in the session diff. Warn-mode by default; block on GHOSTDEV_HOOK_BLOCK=1
# Exit: 0 allow, 1 warn (stderr, tool proceeds), 2 block (tool refused).
# Contract: bin/fixtures/tdd-gate/README.md. Policy: docs/research/hooks-policy.md.

param(
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
)

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $RepoRoot 'logs/hooks'
$today = Get-Date -Format 'yyyy-MM-dd'
$logFile = Join-Path $logDir "$today.log"
function Write-HookLog {
    param([string]$Status, [string]$Message)
    if (Test-Path $logDir) {
        $stamp = (Get-Date).ToString('o')
        Add-Content -Path $logFile -Value "$stamp tdd-test-gate PreToolUse $Status $Message" -ErrorAction SilentlyContinue
    }
}

# 1. Target path: stdin JSON (.tool_input.file_path) or GHOSTDEV_TDD_TARGET override.
#    Also capture session_id for graduated enforcement (step 6).
$target = $env:GHOSTDEV_TDD_TARGET
$sessionId = $env:GHOSTDEV_SESSION_ID
if (-not $target) {
    try {
        $raw = [Console]::In.ReadToEnd()
        if ($raw) {
            $j = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            $target = $j.tool_input.file_path
            if (-not $sessionId -and $j.session_id) { $sessionId = $j.session_id }
        }
    } catch { }
}
if (-not $sessionId) { $sessionId = 'nosession' }
if (-not $target) { Write-HookLog 'noop' 'no target path'; exit 0 }

# 2. Impl-path classification: code ext AND not a test path.
$norm = ($target -replace '\\', '/')
$ext = ([System.IO.Path]::GetExtension($norm)).ToLower()
$codeExts = @('.cs', '.ts', '.tsx', '.js', '.jsx', '.py')
$isTestPath = ($norm -match '(?i)(^|/)(tests?|__tests__)/') -or `
              ($norm -match '(?i)\.(test|spec)\.') -or `
              ($norm -match '(?i)(^|/)test_') -or `
              ($norm -match '(?i)_test\.')
if (($codeExts -notcontains $ext) -or $isTestPath) {
    Write-HookLog 'noop' "non-impl: $target"; exit 0
}

# 3. Active-IMPL gate (OQ1 proxy). Skipped in test mode (explicit diff file).
$blockModeImpl = $false
if (-not $env:GHOSTDEV_TDD_DIFF_FILE) {
    $activeImpl = $null
    foreach ($d in @('docs')) {
        $p = Join-Path $RepoRoot $d
        if (-not (Test-Path $p)) { continue }
        foreach ($f in Get-ChildItem -Path $p -Filter '*-IMPL.md' -ErrorAction SilentlyContinue) {
            $c = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($c -match '(?m)^- \[ \]') {
                $activeImpl = $f.Name
                if ($c -match '(?m)^>\s*block-mode:\s*true\s*$') { $blockModeImpl = $true }
                break
            }
        }
        if ($activeImpl) { break }
    }
    if (-not $activeImpl) { Write-HookLog 'noop' 'no active IMPL phase'; exit 0 }
}

# 4. Session diff: explicit file (tests) or git diff since base (HEAD, or GHOSTDEV_TDD_BASE_REF).
$diff = ''
if ($env:GHOSTDEV_TDD_DIFF_FILE -and (Test-Path $env:GHOSTDEV_TDD_DIFF_FILE)) {
    $diff = Get-Content $env:GHOSTDEV_TDD_DIFF_FILE -Raw
}
else {
    $base = $env:GHOSTDEV_TDD_BASE_REF; if (-not $base) { $base = 'HEAD' }
    try {
        Push-Location $RepoRoot
        $diff = ((& git diff $base 2>$null) -join "`n") + "`n" + ((& git diff --cached 2>$null) -join "`n")
    }
    catch { } finally { Pop-Location }
}

# 5. New test symbol on an added (+) line?
$testSym = '(\bit\(|\bdescribe\(|\btest\(|\[Test\]|\[Fact\]|\bdef test_)'
$hasTest = $false
foreach ($ln in ($diff -split "`n")) {
    if ($ln.StartsWith('+') -and -not $ln.StartsWith('+++')) {
        if ($ln -match $testSym) { $hasTest = $true; break }
    }
}
if ($hasTest) { Write-HookLog 'allow' "$target (test symbol present)"; exit 0 }

# 6. Violation — warn (1) or block (2).
#    Explicit env / block-mode blocks immediately. Otherwise, graduated enforcement
#    (opt-in: GHOSTDEV_GRADUATED=1) warns the first violation this SESSION and blocks
#    repeats — the warn-fatigue fix (§6.4) without surprising on the first hit.
$repeat = $false
if (($env:GHOSTDEV_GRADUATED -eq '1') -and -not $explicitBlock) {
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    $countFile = Join-Path $logDir ("tdd-violations-" + ($sessionId -replace '[^A-Za-z0-9_.-]', '_') + '.count')
    $n = 0
    if (Test-Path $countFile) { $n = [int]((Get-Content $countFile -Raw -ErrorAction SilentlyContinue).Trim()) }
    $n++
    Set-Content -Path $countFile -Value $n -ErrorAction SilentlyContinue
    if ($n -ge 2) { $repeat = $true }
}
$shouldBlock = $explicitBlock -or $repeat
$base = "[tdd-gate] $target - no new test symbol in the session diff. Test-first not satisfied: add a failing test (Red), then the implementation (Green)."
if ($shouldBlock) {
    $why = if ($repeat -and -not $explicitBlock) { ' [BLOCK: repeat violation this session]' } else { ' [BLOCK]' }
    [Console]::Error.WriteLine("$base$why")
    Write-HookLog 'block' "$target"
    exit 2
}
else {
    [Console]::Error.WriteLine("$base [warn]")
    Write-HookLog 'warn' "$target"
    exit 1
}
