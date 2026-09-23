#!/usr/bin/env pwsh
# bin/declare-session-state.ps1
# SessionEnd hook.
#
# Writes the producer-declared state sidecar `{transcript}.ghost-state.json`
# ({"state","evidence"}) next to the session transcript. The sessions surface
# reads it at harvest time and reports that state with `proven: true`, which the
# cockpit renders SOLID instead of the dashed heuristic ring.
#
# WHY SessionEnd AND NOT Stop: a Stop hook fires every time the assistant
# finishes a turn, and "the assistant stopped" does NOT prove "the operator owes
# a reply" — most turns end with work delivered and nothing owed. Declaring
# awaiting-input on every Stop would flood the needs-you lane with a confident
# lie. SessionEnd proves exactly one thing, and proves it completely: this
# session is closed, therefore it is not live. That is worth declaring, because
# the heuristic counts any session touched in the last 24h as live — a session
# the operator closed five minutes ago reads as live until the window expires.
#
# Declares `idle` by default. Whether the WORK finished is not knowable here, so
# `done` is deliberately never declared from SessionEnd. ALWAYS exits 0; never
# blocks teardown.
#
# -State lets another PROVEN producer reuse this writer (the pending-permission
# path, GHOSTDEV-SUBSTRATE.3.6). It is validated against the reader's vocabulary
# HERE, at write time: `DeriveState` discards an unknown token silently
# (SessionSignals.cs:173), so an out-of-set value would otherwise fail as a card
# that just stays hedged forever with nothing to grep. Refusing loudly at the
# writer is the difference between a bug and a mystery.
param(
    [string]$State = 'idle',
    [string]$Evidence = $null
)

# The reader's six-value vocabulary (SessionSignals.States). Keep in lockstep.
$Valid = @('awaiting-input', 'operator-action', 'live', 'done', 'superseded', 'idle')

$ErrorActionPreference = 'SilentlyContinue'

if ($Valid -notcontains $State) {
    [Console]::Error.WriteLine("declare-session-state: refusing to declare '$State' -- not one of: $($Valid -join ', ')")
    exit 0
}

$raw = ''
try { $raw = [Console]::In.ReadToEnd() } catch { }
$j = $null
try { $j = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $j = $null }

$tp = if ($j) { $j.transcript_path } else { $null }
$reason = if ($j -and $j.reason) { $j.reason } else { 'other' }

# No transcript path (or it vanished) → nothing to sit beside. Silent no-op.
if (-not $tp) { exit 0 }

$sidecar = [System.Text.RegularExpressions.Regex]::Replace($tp, '\.jsonl$', '') + '.ghost-state.json'
$stamp = (Get-Date).ToString('o')

$ev = if ($Evidence) { $Evidence } else {
    "session closed at $stamp (SessionEnd: $reason) - declared by bin/declare-session-state"
}

$payload = [ordered]@{
    state      = $State
    evidence   = $ev
    declaredBy = 'ghostdev/declare-session-state'
    declaredAt = $stamp
}

try {
    $payload | ConvertTo-Json -Depth 3 | Set-Content -Path $sidecar -Encoding utf8 -ErrorAction SilentlyContinue
} catch { }

exit 0
