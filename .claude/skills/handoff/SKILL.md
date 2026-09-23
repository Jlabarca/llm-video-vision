---
name: handoff
description: Compress the current session into a disposable, cold-start resume file under docs/handoffs/{FEATURE}.md, then print the exact prompt to paste into a fresh session. Use when a session is getting long (context past the smart zone, ~120k tokens) or before deliberately /clear-ing, so the next session resumes from a tight artifact instead of re-deriving state. Topic-keyed (one file per IMPL, overwritten on re-handoff), gitignored, ephemeral. Manual invocation only — never auto-fires.
---

# handoff

Pocock's "compress, then exit" pattern. A long session degrades past the smart zone (~120k tokens); auto-compaction is lossy and `/clear` throws away the trail. `/handoff` writes the session's working set into a small, cold-start-optimized markdown file so a **fresh** session resumes at full fidelity from a few hundred tokens instead of crawling back through a bloated context.

This is the *ephemeral* twin of LOGBOOK.md. LOGBOOK is the durable, append-only audit trail (Rule 14); a handoff is disposable scratch — topic-keyed, overwritten on every re-handoff, gitignored. LOGBOOK answers "what happened"; a handoff answers "what do I do next, right now."

## When this fires

- Operator runs `/handoff [FEATURE]` — typically when context is heavy or just before `/clear`.
- `FEATURE` optional. If omitted, infer the topic: the most-recently-touched `*-IMPL.md` with an open `- [ ]` checkbox (most recent `Updated:` line wins). If still ambiguous, ask once.
- **Manual only.** Never auto-fire — the operator decides when to compress and exit.

## Procedure

### Step 1 — Resolve the topic key

Derive `<FEATURE>` (the IMPL slug). If passed, match it case-insensitively against `**/*-IMPL.md` filename stems (exclude `node_modules/`, `bin/`, `obj/`, `.git/`, `**/impl/`). If omitted, pick the in-progress IMPL with the newest `Updated:` line. The handoff file is `docs/handoffs/<FEATURE>.md` (relative to repo root) — **one file per topic**, overwritten if it exists.

### Step 2 — Gather the working set (read-only)

Pull, cheaply:

1. **Diff scope** — `git diff --stat` since the session base (last commit, or the run's start SHA if known) — the files this session touched.
2. **Recent commits** — `git log --oneline -8` — what already landed.
3. **IMPL state** — the target IMPL's `## Current State` paragraph + the **first unchecked** checkbox (the cursor).
4. **LOGBOOK tail** — the last 1–2 `### YYYY-MM-DD` entries (what's already durably recorded — do NOT duplicate it into the handoff; reference it).
5. **In-flight decisions** — anything decided this session that is **not yet** in the LOGBOOK (the highest-value content; a fresh session can't recover it any other way).

### Step 3 — Write the handoff file

Overwrite `docs/handoffs/<FEATURE>.md` with this fixed shape (cold-start optimized — read-order first, cursor second, then context):

```markdown
# Handoff — <FEATURE>  (<today's date>, ephemeral)

## Read first (in order)
1. docs/<FEATURE>-IMPL.md — `## Current State` + first unchecked box
2. <any reference/design doc the work depends on>
3. this file

## You are here
- Phase: <PHASE_ID> — <one line>
- Next action: <the single next checkbox/command, verbatim>
- Branch: <branch> @ <HEAD short sha>

## In flight (NOT yet in LOGBOOK)
- <decision/finding made this session that the next session must not re-derive>

## Files touched this session
<git diff --stat output, trimmed>

## Resume prompt  ← paste this into a fresh session
\`\`\`
Resume <FEATURE>. Read docs/<FEATURE>-IMPL.md (Current State + first unchecked box)
and docs/handoffs/<FEATURE>.md. We are at <PHASE_ID>; next: <next action>.
<one-line what's in flight>. Continue.
\`\`\`
```

Keep the whole file under ~1 screen. A handoff that needs scrolling has failed its purpose — push detail into the IMPL/LOGBOOK and link it.

### Step 4 — Print + stop

Emit two things to the operator: the file path written, and the **resume prompt block** rendered inline (so they can copy it without opening the file). Do **not** commit (it's gitignored scratch). Do **not** `/clear` for them — that's their call. Done.

## Constraints

- **Ephemeral + gitignored.** `docs/handoffs/*` is gitignored except `.gitkeep` + `README.md`. Never `git add` a handoff.
- **Topic-keyed, overwritten.** One file per IMPL slug. Re-running `/handoff` on the same feature replaces it — no `-2`, no timestamps in the name.
- **Pure skill, no hook.** Nothing enforces or auto-fires this. (A PreCompact-hook backstop that *suggests* `/handoff` when context nears the compaction threshold is a possible follow-up — not part of this skill.)
- **Don't duplicate the LOGBOOK.** Reference the last entry; only capture what isn't already durable. The "In flight" section is the point.
- **No commit, no promotion, no code edits.** This skill only reads and writes the one scratch file.

## Agent execution

Project-level skills under `.claude/skills/` aren't always exposed via the Skill tool surface. When a session encounters `/handoff …`, it reads this SKILL.md and executes inline: resolve topic → gather working set (git + IMPL + LOGBOOK tail) → overwrite `docs/handoffs/<FEATURE>.md` → print the resume prompt. No Skill-tool dispatch, no commit.

## Companion skills

- `/logbook-append` — the durable counterpart; run it for the audit trail, `/handoff` for the live resume.
- `/run-impl <FEATURE>` — the fresh session pastes the resume prompt, then drives from the first unchecked box.
- `/audit-impl <FEATURE>` — if the handoff is stale (>7 days), prefer a fresh drift audit over trusting it.
