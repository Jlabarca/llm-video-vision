---
name: run-impl
description: Drive an existing FEATURE-IMPL.md through to completion automatically — one phase, several, or all of them. Handles ongoing/paused IMPLs (resumes from the first unchecked box). Same automatic-by-default principle as /bootstrap-impl, applied to execution. Per-phase plan-mode + commit + LOGBOOK + qa-pass, with a session-safety lock to prevent two operators colliding on the same IMPL. Manual invocation only — never auto-fires.
---

# run-impl

The execution counterpart to `/bootstrap-impl`. Bootstrap turns "I want a feature" into a populated IMPL doc; run-impl turns "the IMPL doc exists" into "the feature shipped." Both share the same operating principle: brute-force the work in flow, surface decisions as commits the operator reviews afterward.

## When this fires

- Operator runs `/run-impl <FEATURE>` — drive the IMPL until the next blocker or until promotion gates pass.
- Optional flags:
  - `/run-impl --one-phase <FEATURE>` — execute exactly one phase, then stop.
  - `/run-impl --phase <PHASE_ID> <FEATURE>` — execute the named phase (e.g. `AUTH.3`), even if earlier phases have unchecked boxes (operator override; surfaces a warning).
  - `/run-impl --no-commit <FEATURE>` — execute + edit but never commit. For sandbox runs.
  - `/run-impl --force <FEATURE>` — bypass the session lock and clean-tree checks. Use after a crashed run.
  - `/run-impl --no-promote <FEATURE>` — stop at the promotion gate instead of chaining into `/promote-impl` (Rule 19). Use when you want to read the reference doc before it moves.
- **Manual only.** Never auto-fire. Driving an IMPL is a high-blast-radius decision; the operator owns the call.

## Pre-flight (all must pass before any work)

1. **Target IMPL exists.** Glob `**/*-IMPL.md` (exclude `node_modules/`, `bin/`, `obj/`, `.git/`, `**/impl/`). Match `<FEATURE>` case-insensitively against the filename stem. If multiple plausible matches, prefer the one with the most-recent `Updated:` line and report the choice. If none, abort.
2. **Session lock check.** Look for `<root>/.<FEATURE>-IMPL.lock` (sibling to the IMPL).
   - If absent: proceed (will create on entry).
   - If present, `started:` is < 2h ago and `session:` is not this session: **abort** with `another session (<session>) holds <FEATURE> (started <timestamp>, branch <branch>, head <sha>). One writer per tracker (Rule 23). Use --force to override.`
   - If present and stale (>2h) or `head:` no longer matches `git rev-parse HEAD`: warn ("stale lock from <timestamp>; proceeding"), overwrite the lock.
3. **Open Questions resolved.** Per Rule 13, every `**Resolution:**` line under `## Open Questions` must be filled. Treat literal `___` or empty as unresolved → abort with "resolve Open Questions first (Rule 13). See `/clarify-impl <FEATURE>`."
   - **Exception:** `**Resolution: DEFERRED**` is allowed but **blocks any phase that depends on the deferred question**. If the IMPL's phase-table description mentions "blocked on" or "blocked on research", skip those phases and resume after them only if the operator passed `--phase` to target one explicitly.
4. **Clean working tree.** Live shell: `` !`git status --porcelain` ``. If non-empty, abort with `working tree has uncommitted changes; commit or stash first`. (`--force` bypasses; do not bypass silently.)
5. **`<TBD>` markers gated by phase.** Scan the IMPL for `<TBD>` strings. If any sit inside the **Key Files Reference** rows for files touched by the next phase to run, abort with the list. `<TBD>` for later phases is fine.
6. **On the integration branch (Rule 21).** Resolve it: `develop`/`development` if it exists **and** `git rev-list --count <develop>..<default>` is `0`, else the default branch (`main`, else `master`). If a `develop` exists but sits behind, print once — `stale develop: N behind <default>, last commit <date>` — and ignore it. If `HEAD` is not on the resolved branch, abort naming both: this skill does not switch branches.

If any pre-flight fails, emit the failure and exit. Do not partial-run.

## Procedure

### Step 1 — Write the session lock

Write `<root>/.<FEATURE>-IMPL.lock` with:

```text
started: <ISO-8601 UTC>
session: <this session's id, if the harness exposes one; else `unknown`>
branch: <current git branch>
head: <git rev-parse HEAD>
flags: <flags this run was invoked with>
```

The lock is bookkeeping (Rule 14-exempt). It is `.gitignore`-friendly — `*-IMPL.lock` pattern; add to `.gitignore` once on first run if not present.

### Step 2 — Identify the target phase set

- Default (no flag): all phases from the **first unchecked** phase forward, stopping at the first DEFERRED-blocked phase or the end.
- `--one-phase`: only the first unchecked phase.
- `--phase PHASE_ID`: only the named phase (warn if earlier phases have unchecked boxes).

A "phase" is delimited by `### Phase N — <name>` headings under `## Checklist`.

### Step 3 — Per-phase execution loop

For each target phase, in order:

#### 3a. Count source-content files (Rule 14 gate)

Inspect the phase's checklist text for file references. If the phase will touch **2+ source-content files**, Rule 14 requires Plan mode:

1. Dispatch a `Plan`-subagent with the phase checklist + Key Files Reference rows + Architecture section as context. Ask for a concrete plan naming every file to be touched and why.
2. Append the plan into the IMPL under `## Plan — <PHASE_ID>` (or update existing).
3. Commit the plan as a separate `docs(<feature-slug>):` commit so the operator's review surface is a small diff. The operator can then read the next commit (execution) against the planned scope.
4. Proceed to execution.

If the phase is **single-source-content** or **pure docs** (per the Rule 14 source-content carve-out — IMPL checkbox flips, Updated-line bumps, CONTEXT/TODO/LOGBOOK/README bookkeeping don't count toward the threshold), post a one-line waiver into `## Plan — <PHASE_ID>` per Rule 14 and skip the Plan-subagent dispatch.

#### 3b. Execute checkboxes one at a time

For each unchecked box in the phase, in order:

0. **Stop at a `human:` box (Rule 18, stop set ii).** If the box carries a `human:` marker, halt the run **here** — do not skip past it, because later boxes may depend on it. Surface the box and its stated reason. A ticked `human:` box is a person's record; never tick one yourself.
1. Read the checkbox text. Resolve any `<TBD>` markers in the referenced files first (Glob/Grep to locate; if unresolvable, halt the phase and surface the box as a blocker).
2. Apply the change. Default to `Edit` over `Write` (existing-file edits send only the diff).
3. After the edit, run **the cheapest verification available** that the codebase supports. Detect the project's language(s) from extensions in the touched files:
   - **C# / .NET** (`*.cs`, `*.csproj`): `dotnet build` of **every project whose files this box touched, test projects included** (Rule 22, clause 2).
   - **TypeScript / JavaScript** (`*.ts`, `*.tsx`, `*.js`): `pnpm tsc --noEmit` or `tsc --noEmit` in the touched workspace.
   - **Python** (`*.py`): `python -m py_compile <file>` then any `pytest -k <relevant>` if tests exist.
   - **Go** (`*.go`): `go build ./...` in the touched module.
   - **Rust** (`*.rs`): `cargo check -p <crate>`.
   - **Pure-docs phase**: no build step; skip.
   - **Unknown language**: skip verification with a warning logged in the LOGBOOK entry.
4. If verification fails, attempt **one** auto-fix pass. If still failing, halt the phase and surface the error verbatim.
5. Flip the checkbox `[ ]` → `[x]` **and append its evidence on the same line** (Rule 22, clause 1): `— evidence: <test name | command → exit 0 | path>`. A box you cannot evidence stays `[ ]`.
6. **Commit the box (Rule 20)** when it changed a source-content file: `git add` only that box's files plus the IMPL, and use `<type>(<feature-slug>): <BOX-ID> — <what changed>`, type per Rule 15. A box with no diff carries its evidence on the line and rides the next commit. Skipped entirely under `--no-commit`.

#### 3c. End-of-phase QA

Invoke the `/qa-pass` procedure inline (re-read its SKILL.md, run the punch-list checks). **A non-empty punch list does NOT halt the run** (Rule 18): collect each item into a session-level accumulator keyed by phase, append it to the LOGBOOK entry's **Blockers** section, and surface the whole list once in the Step 6 report. The operator reviews it after the run and decides what to address. Only a hard blocker from `## Stopping conditions` halts.

Record qa-pass's verdict on the phase's status row (Rule 22, clause 3): **Shipped** when every source box is committed, every touched project built including its tests, and every box carries evidence — otherwise **Executed, unverified**. A phase that is not Shipped keeps `[~]` rather than `[x]`.

#### 3d. Bookkeeping (Rule 14-exempt)

1. Bump the IMPL's `> Updated: YYYY-MM-DD` line to today.
2. Flip the phase row in the `## Implementation Status` table from `[ ] not started` (or `[~] in progress`) to `[x] complete`.
3. Append a four-section LOGBOOK entry per `docs/LOGBOOK.md` conventions:
   - **Accomplished:** "Phase `<PHASE_ID>` shipped via /run-impl — N checkboxes, files touched."
   - **Decisions:** any non-trivial choice made during execution.
   - **Blockers:** "none" or anything that surfaced.
   - **Next:** the first checkbox of the next phase, or "Promotion gates" if this was the last phase.
4. Update CONTEXT.md milestone row if applicable (e.g. `state: in-flight → state: phase-N-shipped`).

#### 3e. Commit (unless `--no-commit`)

Source boxes were already committed in 3b.6. This commit is the phase's **bookkeeping** (Rule 20): `docs(<feature-slug>): close <PHASE_ID> — <one line>`, carrying the status row, the `Updated:` line, the LOGBOOK entry and any CONTEXT edit.

Two cases collapse this back into a single commit for the whole phase, and both must say so in the body: a phase whose boxes all edit **one** file (the diff genuinely is the evidence for all of them), and a change whose parts must land together or the tree is red — an interface plus its implementors. Type it per Rule 15 from the phase's primary output and name every box id.

Use `git add` with only the files this phase touched. Do **not** blanket-add.

If the pre-commit hook fails: **fix and recommit, do not amend**.

### Step 4 — Promotion gate (only if all phases now complete)

After the last phase ships, check whether `/promote-impl` pre-conditions hold:

- All checklist items checked.
- No open `Known Bugs` (resolved entries with `~~strikethrough~~` are fine).
- `docs/reference/<feature-slug>.md` exists.
- Tests-green confirmation OR `tests-deferred:` flag in IMPL header.

If they all hold: **chain into `/promote-impl <FEATURE>`** — re-read its SKILL.md and execute it inline — unless `--no-promote` or `--no-commit` was passed. This is Rule 19: applying is mechanical and the *decision* was made when a person invoked this run. The promotion is one commit, so `git revert` undoes it.

Under `--no-promote`, surface `Promotion gates green — run /promote-impl <FEATURE> when ready.` and stop. That is a Rule 18 stop: the operator deliberately withheld the decision.

If gates fail: surface the punch list. Common gap: `reference/<slug>.md` doesn't exist yet → suggest a follow-up `/run-impl` with a "Phase N+1: write reference doc" added to the IMPL, OR a manual draft.

### Step 5 — Release the lock

Delete `<root>/.<FEATURE>-IMPL.lock`. Always — even on halt-and-surface paths. If the conversation crashes before this runs, the next session sees a stale lock (>2h or HEAD-moved) and overwrites it.

### Step 6 — Report

Single terse message, mirroring `/qa-pass` style:

```text
/run-impl AUTH

Started: AUTH.3 (refresh-token rotation)
Shipped: AUTH.3 (4/4 checkboxes, 5 files, commit a3f9c12)
Shipped: AUTH.4 (4/4 checkboxes, 7 files, commit 8b2d44e)
Halted at: AUTH.5.2 — TokenStore path resolution failed (file not at expected location; <TBD>)

Phases complete: 3, 4
Phases remaining: 5 (2 of 4 boxes done), 6
Promotion gates: not yet — phases 5, 6 remain

Next: resolve <TBD> in Key Files Reference row 11 (TokenStore.ext path), then re-run /run-impl AUTH
```

## Stopping conditions

This is the **stop set** (Rule 18). These are the *only* things that stop a default-mode run, and each halt names the clause it invoked in the Step 6 report. Finishing a phase is not one of them; neither is a green promotion gate.

- **A `human:` box is next.** Halt **at** the box, never past it.
- **DEFERRED-blocked phase.** Skip-with-note in default mode; abort with explanation if user passed `--phase` targeting it.
- **`<TBD>` blocking the current checkbox.** Halt, surface the row.
- **Verification failed after one retry** — build, typecheck, or a declared behavioural tier. Halt, surface the error.
- **Pre-commit hook failure that auto-fix cannot resolve.** Halt, surface the hook output.
- **Another writer holds the tracker** (Rule 23) — a fresh lock from a different session, or an agent runner armed against it where the project has one.
- **More than 6 phases queued in a single run.** Refuse — that's a sign the IMPL needs to be split. Operator can `--phase` through them one by one.
- **Operator interrupt (Ctrl+C / send a new message).** Conversation-level; not in skill control, but the lock-cleanup step (Step 5) won't run, so the next session sees a stale lock and recovers.

**Not a stopping condition:** a non-empty qa-pass punch list. It is collected and reported at the end. The goal of a default run is to reach promotion; advisory QA items are the operator's post-run review surface, not a brake.

## Constraints

- **Manual invocation only.** Never auto-fire from observing the user mention an IMPL. The skill commits code; that's not an inference-time decision.
- **Session lock is non-negotiable** except via `--force`. Two parallel `/run-impl` runs on the same IMPL will corrupt commit history and confuse the LOGBOOK.
- **Rule 14 is non-negotiable.** Multi-source-content phases get a Plan-mode commit before execution, every time. The plan commit is the operator's review surface for the upcoming execution.
- **Default mode runs THROUGH promotion (Rule 18).** Without `--one-phase`, `--phase` or `--no-promote`, the run ends in a promotion commit or a stop-set halt — nothing else. A finished phase, a per-box commit and a non-empty qa-pass punch list are all *not* stopping points.
- **Per-box commits for source boxes, per-phase for bookkeeping (Rule 20).** A phase is the smallest *mergeable* unit (Rule 12); a box is the smallest *evidenced* unit (Rule 22). `git log --grep '<BOX-ID>'` must find the change that box claims.
- **"Shipped" is earned (Rule 22).** The report says Shipped only for a phase with commits, a green build including its tests, and evidence on every box; otherwise **Executed, unverified**. A `--no-commit` run never says Shipped.
- **Never amend.** Pre-commit hook failures get a fresh commit.
- **No `<feature-slug>` shorthand.** Always derive: `<FEATURE>` lowercased, hyphens preserved (`AUTH` → `auth`, `PAYMENT-RETRY` → `payment-retry`).

## Tool allowlist (advisory)

Main session: `Read, Glob, Grep, Edit, Write, Bash(git add:*), Bash(git commit:*), Bash(git status:*), Bash(git rev-parse:*), Bash(dotnet build:*), Bash(pnpm tsc:*), Bash(tsc:*), Bash(pytest:*), Bash(python -m py_compile:*), Bash(go build:*), Bash(cargo check:*), Agent (Plan subagent for Rule 14)`.

Never used by this skill: `Bash(git push:*)` (shipping is out of scope; operator decides when to push), `Bash(git reset:*)` / `Bash(git checkout -- :*)` (destructive; halts surface errors instead).

## Why this exists

Three failure modes this skill targets:

1. **Cold-restart drag on paused IMPLs.** Picking up a 3-week-old IMPL costs 20+ min re-reading the header, finding the next box, recalling the conventions. `/run-impl` collapses that into a single command — the skill re-reads the IMPL fresh and starts from the first unchecked box.
2. **Forgotten Rule 14 plan mode.** Multi-file phases routinely skip plan mode under time pressure. Bundling plan mode into the per-phase loop makes the ceremony free.
3. **Drift between IMPL state and git state.** Operators flip checkboxes without committing, or commit without flipping checkboxes. Per-phase commits + automatic `Updated:` bump + automatic LOGBOOK append keep the three in lock-step.

The pattern is the same as `/bootstrap-impl`'s "automatic by default" principle — bootstrap automated the *birth* of an IMPL; run-impl automates the *life* of one. Promotion (`/promote-impl`) stays manual on purpose: it's irreversible (file moves into `impl/`), and the operator should look at the diff before pulling that trigger.

## Companion skills

- `/bootstrap-impl <FEATURE-DESCRIPTION>` — creates the IMPL this skill drives.
- `/clarify-impl <FEATURE>` — re-opens Open Questions if a deferred one becomes pressing mid-run.
- `/audit-impl <FEATURE>` — drift check; useful between phases on long-cooked IMPLs.
- `/qa-pass [PHASE_ID]` — folded into Step 3c; can also be run independently.
- `/promote-impl <FEATURE>` — the manual final step after run-impl reports "Promotion gates green."

## Agent execution

Project-level skills under `.claude/skills/` aren't exposed via the Skill tool surface as of 2026-05. When an agent session encounters `/run-impl …`, it reads this SKILL.md and executes the procedure inline: pre-flight checks, write the lock, iterate phases (plan → execute → qa-pass → bookkeeping → commit), release the lock, report. No Skill-tool dispatch.
