---
name: triage-sessions
description: Fleet-wide triage of recent Claude Code sessions via the methrep sessions surface. Fetches GET /sessions v2 (six-state heuristic taxonomy awaiting-input/operator-action/live/done/superseded/idle with verbatim stateEvidence, matchedThreadId join, structured supersededBy, GET /sessions/{id}/prompt verbatim tail extraction), applies judgment to classify each real session (DONE / HANDED-OFF / AWAITING-CONFIRM / OPERATOR-ACTION / LIVE-THREAD / STALE), and emits paste-ready continuation prompts in a fixed format. Read-only. Use when session tabs pile up, after a multi-session shipping window, or before deciding what to resume vs restart. Works from ANY repo root — the surface is fleet-wide.
---

# triage-sessions

Answers "which of my Claude Code sessions still owe me something, and how do I continue each one?" — consuming the methrep sessions surface instead of scanning transcripts by hand. The mechanical half (enumeration, parsing, noise filter, thread join, supersession cross-checks, six-state heuristic classification) is server-side; this skill supplies the judgment half. Most sessions never need this skill — the cockpit's Threads lanes at `/x/ghostdev` render the same rows as cards; this is the LLM escalation tier for ambiguous cases.

## When this fires

- User runs `/triage-sessions` (default window: 7 days) or `/triage-sessions N` (N days).
- Never auto-fires.

## Procedure

Read-only end to end. Never edit, commit, or deploy from this skill.

### Step 1 — Fetch the surface

```
GET http://localhost:5202/sessions?days=<N>
```

(`curl -fsS "http://localhost:5202/sessions?days=7"`.) Envelope: `{ sessions, scannedAt, windowDays, filteredCount }` — `filteredCount` is server-dropped automation noise; report it, never re-derive it.

Optional filters compose as AND: `?workspace=<ID>` scopes to one workspace by its registry ID (the `id` from `GET /workspaces` — wsId-scoped, unlike `?root=` which takes a raw repo path), and `?state=<state>` filters by mechanical state. Unknown workspace IDs return an empty list, not an error.

Each row carries: `id`, `projectSlug`, `repoRoot`, `state` (`awaiting-input|operator-action|live|done|superseded|idle` — HEURISTIC unless `proven`), `stateEvidence` (verbatim why), `proven` (true only for a producer-declared state), `lastSpeaker`, `startedAt`, `lastActiveAt`, `messageCount`, `sizeBytes`, capped `firstUserMessage`/`lastUserMessage`/`lastAssistantMessage`, `generatedPrompt`, `matchedThreadId` (cockpit-thread join), `topicSlug`, structured `supersededBy` (`{kind: handoff|impl|session, path|id}`), `transcriptRef`.

**If methrep is down** (connection refused / non-200): report that plainly and stop — the fleet-HQ fallback (`digest.ps1` under the d:/ware root skill) is the only offline path; do not reimplement the harvest here.

### Step 2 — Trust the server's mechanical states

- `matchedThreadId` non-null — **skip** (cockpit-owned: the session enriches its thread's card in the Threads lanes; re-surfacing it here double-notifies). Count for the summary only.
- `superseded` — **skip**; the structured `supersededBy` says exactly by what. Count only.
- `proven: true` — trust the declared state outright (a Stop-hook producer wrote it). Classify mechanically.
- `done` — usually safe to classify DONE from `stateEvidence` + `lastAssistantMessage`; spot-check the excerpt before listing under "safe to close".
- `awaiting-input` / `operator-action` / `live` / `idle` (heuristic) — these need YOUR judgment (Step 3).

### Step 3 — Judge each heuristic session

Read the capped excerpts + `stateEvidence` first; when they're not enough, fetch the transcript tail via `GET /session/{id}` (the `transcriptRef`). Classify into exactly one:

| State | Signal |
|---|---|
| DONE | committed/shipped/verified, completed report |
| HANDED-OFF | handoff/resume prompt exists; artifact supersedes the session |
| AWAITING-CONFIRM | assistant presented a plan/patch/question and stopped for "go" |
| OPERATOR-ACTION | blocked on something only the operator can do — name the exact commands |
| LIVE-THREAD | genuine mid-conversation, context still valuable |
| STALE | superseded (beyond what the server already caught) |

Cross-check before trusting a transcript: `git log --since=<lastActiveAt>` in the session's `repoRoot` (the server deliberately does NOT shell git — this is the judgment tier's job) — commits touching the same feature mean a parallel session advanced it.

### Step 4 — Build continuations

For each AWAITING-CONFIRM / OPERATOR-ACTION / LIVE-THREAD / unpasted-HANDED-OFF:

- `generatedPrompt: true` ⇒ fetch `GET /sessions/{id}/prompt` — the server extracts the fenced ```text block VERBATIM (never paraphrase; it tail-reads >5MB transcripts safely). 404 ⇒ extract from `GET /session/{id}` yourself, still verbatim.
- Resume is better (cheap pending answer <~1 day old, or context too expensive to rebuild) ⇒ `claude --resume <id>` + a short kick-off answering the pending question.
- OPERATOR-ACTION ⇒ exact shell commands first, then the resume + report-back kick-off.
- State the session ROOT (its `repoRoot`) and concurrency warnings (same-repo writers serialize).

## Output format (exactly this)

### A. Fleet summary
One line: N sessions in window, N noise filtered (server), N matched/superseded skipped, N per judged state.

### B. Triage table
`| Repo | Session (8-char) | Last active | Msgs | State | One-line topic | Evidence |` — actionable first. Evidence = the server's `stateEvidence` or your override reason.

### C. Safe to close
One bullet per DONE/STALE/superseded/matched: `id — topic — why safe` (for superseded, quote the `supersededBy` artifact).

### D. Continuations
Per actionable session, numbered by priority (quick unblocks first):

```
## N. <TOPIC> — <state> (<repoRoot>)
**Why it needs you:** one sentence.
**Operator pre-steps:** commands, or "none".
**How:** `claude --resume <full-uuid>` OR "fresh session at <root>".
**Paste this:**
<verbatim prompt / kick-off>
**Concurrency:** conflicts, or "safe".
```

### E. Recommended execution order
One line, `∥` marking safe parallels.

## Rules

- Every claim traces to a `/sessions` row, a transcript excerpt, or a git check — never invent.
- Matched (`matchedThreadId`) sessions belong to the cockpit inbox — never re-surface them here.
- A `proven` state is an artifact, not a guess — don't second-guess it without new evidence.
- Total output ≤ 2000 words excluding verbatim prompts in D.
