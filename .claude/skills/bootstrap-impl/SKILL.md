---
name: bootstrap-impl
description: Scaffold a new FEATURE-IMPL.md from a one-line feature description by fanning out to parallel subagents — header drafter, clarify-question generator, auto-resolver, phase decomposer, optional codebase grounding. End-to-end automatic: drafts the IMPL, resolves Open Questions with reasoned defaults (operator can override later), updates CONTEXT.md / TODO.md / LOGBOOK.md, and commits. No mid-flow prompts. Per docs/DOCS-PROTOCOL.md Rule 12 + Rule 13 + Rule 14.
---

# bootstrap-impl

Parallel scaffolding for a new FEATURE-IMPL.md. The pattern is borrowed from "✨ New Spec with Agents" style IDE extensions — adapted to ghostdev's single-IMPL-file convention and the rest of this template's skill ecosystem.

## When this fires

- Operator runs `/bootstrap-impl <feature description>` (free-form description, e.g. `/bootstrap-impl Auth refresh-token rotation flow`).
- Optional flag: `/bootstrap-impl --ground <feature description>` adds the codebase grounding subagent.
- Optional flag: `/bootstrap-impl --root <path> <feature description>` writes under a non-default IMPL root (e.g. `subproject/docs/`). Default: `docs/` at workspace root.
- Optional flag: `/bootstrap-impl --no-commit <feature description>` skips the final commit (write + index updates only).
- Optional flag: `/bootstrap-impl --no-resolve <feature description>` leaves Open Questions un-resolved for the operator.
- Optional flag: `/bootstrap-impl --and-run <feature description>` chains into `/run-impl` after the scaffolding commit and drives the tracker under Rule 18. **Opt-in on purpose** — see Step 10.
- **Do NOT auto-fire.** New IMPL creation is an operator decision; this skill executes the scaffolding once that decision is made.

## Operating principle — automatic by default

This skill runs end-to-end without mid-flow prompts. Brute-force the work with strong-model subagents in parallel and stitch the result. Where ambiguity exists, pick a default with explicit rationale (Rule 13 allows defaults) and surface it in the IMPL so the operator can override during normal review. **Never** end with "next, run /clarify-impl …" — fold that step inline. The operator's review surface is the resulting commit + diff, not a chain of follow-up commands.

## Procedure

This skill is the **inverse** of `audit-impl`: instead of one subagent reading a finished IMPL, multiple subagents *write* sections of an IMPL in parallel and the main session stitches them together.

### Step 1 — Resolve the feature name

From the description, derive a SCREAMING-KEBAB feature name suitable for `{FEATURE}-IMPL.md`. Examples:

- "Auth refresh-token rotation" → `AUTH`
- "Payment retry with exponential backoff" → `PAYMENT-RETRY`
- "Checkout flow redesign" → `CHECKOUT-FLOW`

If ambiguous (multiple plausible names), **pick the most specific one** and note the alternative in the IMPL's `## Open Questions` block as a resolvable question. Do not stop to ask.

### Step 2 — Verify nothing collides

Glob `**/*-IMPL.md` (exclude `node_modules/`, `bin/`, `obj/`, `.git/`, `**/impl/`). If a file matching the resolved name exists:

- If active (under `docs/` or `*/docs/` root): **abort** with `IMPL already exists at <path> — did you mean /clarify-impl or /audit-impl?`
- If archived (under `**/impl/`): warn but proceed — the operator may be re-opening a closed feature with a fresh tracker.

### Step 3 — Read steering context

Read once into the main session, **before** dispatching subagents:

- `CLAUDE.md` (workspace root) — for project-wide conventions
- `docs/CONTEXT.md` — for the active sprint and milestone table
- The CLAUDE.md nearest the IMPL root (if `--root subproject/docs/`, also read `subproject/CLAUDE.md`)
- Any `docs/design/*.md` whose filename keyword-matches the feature description
- **Prior-art sweep (DOCS-PROTOCOL Rule 17).** Read `docs/CAPABILITIES.md` (if the project keeps one) and glob `docs/reference/` + `docs/impl/` filenames for anything the feature's keywords touch — catch a capability that **already shipped** before the IMPL asserts it's missing or first. Carry the result into the brief so the header drafter can emit the `> Prior-art sweep: <date>` line.

This context goes in each subagent's prompt as a brief — they don't re-read it.

### Step 4 — Fan out subagents (parallel, single message)

Dispatch in **one message with multiple `Agent` tool blocks** so they run concurrently. **Pass `model: "opus"` on every Agent call** — bootstrap is a one-shot up-front investment; brute-force the smartest model available. Lighter models are not appropriate here.

#### Subagent A — Header drafter (`subagent_type: Plan`, `model: "opus"`)

```text
Draft the header sections of a FEATURE-IMPL.md per docs/DOCS-PROTOCOL.md Rule 12.

Feature: <description>
Resolved name: <FEATURE>
Steering context (verbatim from main session):
<CLAUDE.md excerpts + relevant CONTEXT.md milestone row + any design/ doc matches>

Produce these sections, in order, ≤500 words total:
- Title block (`# <Feature> — Implementation Tracker` + the standard 4-line preamble)
- ## AI Continuation Prompt (≤120 words — what files a fresh session must read first)
- ## Architecture (key design decisions; cite reference/ docs by path; include one mermaid diagram only if the architecture is non-trivial)
- ## Current State ({today's date}) — write "Plan-only — no code yet."
- ## Known Bugs — empty list with "_(none yet)_"
- ## What Needs Testing — placeholder list keyed off the phases (subagent C will name them)

Do NOT invent files that don't exist. If a path is uncertain, write `<TBD>` so the operator notices.
```

#### Subagent B — Clarify question generator (`subagent_type: general-purpose`, `model: "opus"`)

```text
Generate ≤3 Spec Kit-style clarifying questions for this feature, per docs/DOCS-PROTOCOL.md Rule 13.

Feature: <description>
Steering context: <same brief as A>

Target ambiguity in:
- Scope (what's IN vs OUT of this IMPL)
- Decision gaps (an asserted choice with no named alternative)
- Source-audit gaps (a cited doc/file that may not exist — use Glob to verify)
- Test gates (claimed observable behavior that isn't reachable from the IMPL's surface)
- Dependency assumptions (this feature presumes another shipped behavior)

Output the exact markdown block per Rule 13:

## Open Questions

> Spec Kit-style clarify step. ≤3 items. Mark resolved or accept default with rationale before P1 starts.

1. **Q:** {question}
   **Resolution:** ___
2. ...

If the feature is unambiguous, output: "## Open Questions\n\n_No clarifications needed — feature surface is unambiguous._"
```

#### Subagent C — Phase decomposer (`subagent_type: Plan`, `model: "opus"`)

```text
Decompose this feature into 3–6 phases, each one mergeable as a single PR.

Feature: <description>
Steering context: <same brief as A>

For each phase produce:
- Phase ID: `<FEATURE>.<N>` (e.g., AUTH.1, AUTH.2, ...)
- One-line description
- 2–6 checkbox items with sub-IDs (e.g., AUTH.1.1, AUTH.1.2)
- Model column hint: "Sonnet" if it's wiring/execution following existing patterns; "Opus" if it requires novel architecture

Output two markdown blocks per Rule 12:

## Implementation Status

| Phase | State | Model | Description |
|---|---|---|---|
| <FEATURE>.1 | [ ] not started | Sonnet | ... |
| <FEATURE>.2 | [ ] not started | Opus | ... |
...

## Checklist

### Phase 1 — <name>
- [ ] <FEATURE>.1.1 ...
- [ ] <FEATURE>.1.2 ...

### Phase 2 — <name>
...

Phases must compose: phase N's checklist outputs become phase N+1's preconditions. P1 should always be the smallest shippable slice — bias toward something testable in <1 day.
```

#### Subagent D — Codebase grounding (ONLY if `--ground` flag passed; `subagent_type: Explore`, `model: "opus"`)

```text
Read-only scan: identify existing code in this repo relevant to <feature description>.

Steering context: <same brief>

Approach:
- Grep for likely keywords (feature name tokens, domain nouns)
- Glob for files matching obvious patterns (e.g., `**/*Auth*`, `**/*session*`)
- Skim the top 3–5 hits

Report ≤200 words:
- Existing related code (file:line cites)
- Existing reference/ docs that overlap
- Patterns already used in this area (DI registration shape, naming, test layout)
- "Reuse vs replace" candidates — what existing piece could this feature extend instead of greenfield?

Do NOT propose design — just enumerate what's already there. Output goes into the Architecture section as an "Existing surface" subsection so subagent A can reference it… but A has already started. Ground findings get *appended* by the main session in Step 5.
```

### Step 5 — Auto-resolve Open Questions (second dispatch, unless `--no-resolve`)

Once A/B/C (and D if requested) return, immediately dispatch **Subagent E** — auto-resolver. This is a second parallel burst (single message, single Agent call; can fan out further if many questions). Keep this in-flow — **do not stop and ask the operator**.

#### Subagent E — Auto-resolver (`subagent_type: general-purpose`, `model: "opus"`)

```text
Resolve each Open Question for FEATURE-IMPL.md per docs/DOCS-PROTOCOL.md Rule 13. Rule 13 explicitly allows "accept default with rationale" — do exactly that.

Feature: <description>
Steering context: <same brief as A>
Phase plan (from subagent C): <C's output, verbatim>
Existing surface (if --ground): <D's output, verbatim>

Open Questions to resolve (from subagent B):
<B's output, verbatim>

For each question, output:

**Q:** <question>
**Resolution:** <chosen default in one or two sentences>
**Rationale:** <why this default — cite Rule, file path, or steering-context line>
**Override hint:** <one-line description of when the operator should flip this>

Pick the **least-surprising** default — match patterns already in the codebase, prefer the simpler scope, prefer reusing existing infrastructure over greenfield. Never pick a default that requires new infrastructure unless the feature description explicitly demands it. If a question is genuinely 50/50 and the wrong answer would be expensive to reverse, output **Resolution: DEFERRED — operator must answer** with a one-line explanation; this is the only escape hatch.
```

### Step 6 — Stitch and write

Once E returns:

1. Concatenate in this order: A (title + header) → B's question block, **with each `Resolution: ___` line replaced by E's resolution + a `> Rationale:` blockquote + a `> Override: …` blockquote** → C (Implementation Status + Checklist) → A again (Key Files Reference + Architecture Notes — empty stubs).
2. If `--ground` ran: append D's findings as a `### Existing surface` subsection inside Architecture, **before** Current State.
3. Resolve `<TBD>` markers — main session does a final read-through and fills them in from the steering context. Anything still ambiguous becomes an extra Open Question with an auto-resolution attached.
4. Write the assembled markdown to `<root>/<FEATURE>-IMPL.md` (default root: `docs/`).

### Step 7 — Update index docs (bookkeeping, Rule 14-exempt)

Rule 14 (architect mode) exempts bookkeeping per the source-content carve-out. The following are bookkeeping and should be applied automatically:

1. **`<root-of-impl>/../CONTEXT.md`** — add (or update) the milestone row referencing the new IMPL. Insert under the active-sprint section with state "in-flight" and today's date.
2. **`<root-of-impl>/../TODO.md`** — append a phase-1 checklist mirror (just P1's checkboxes; full list lives in the IMPL).
3. **`<root-of-impl>/../LOGBOOK.md`** — append a four-section entry dated today (`### YYYY-MM-DD — bootstrap <FEATURE>`):
   - **Accomplished:** "Bootstrapped <FEATURE>-IMPL.md via /bootstrap-impl — N phases, M open questions auto-resolved."
   - **Decisions:** one bullet per non-trivial auto-resolution from E.
   - **Blockers:** any DEFERRED questions from E, or "none".
   - **Next:** "P1.1 — <first-checkbox-text>"
4. **README.md (if one exists at IMPL root and indexes IMPLs)** — add a one-line entry.

Use Glob to confirm CONTEXT.md / TODO.md / LOGBOOK.md exist at the chosen IMPL root before editing. If they don't, skip silently — not every sub-root has the full set, and bootstrapping is not the time to create them.

### Step 8 — Commit (unless `--no-commit`)

Per DOCS-PROTOCOL.md Rule 15, bootstrapping introduces a feature surface (the IMPL artifact). Use `feat(<feature-slug>):` — **not** `docs(...)`. The CONTEXT/TODO/LOGBOOK updates piggyback on the same commit (they're bookkeeping for the same introduction event); they don't change the commit type.

`<feature-slug>` is the resolved `<FEATURE>` name lowercased and trimmed (`AUTH` → `auth`, `PAYMENT-RETRY` → `payment-retry`).

```pwsh
git add <root>/<FEATURE>-IMPL.md <root>/../CONTEXT.md <root>/../TODO.md <root>/../LOGBOOK.md <root>/../README.md
git commit -m @'
feat(<feature-slug>): bootstrap <FEATURE>-IMPL via /bootstrap-impl

- N phases, M open questions auto-resolved (Rule 13 default-with-rationale)
- CONTEXT.md / TODO.md / LOGBOOK.md updated (bookkeeping, Rule 14-exempt)
- Operator should review the auto-resolved Open Questions and flip any wrong defaults before P1 starts
'@
```

Subsequent commits during the feature's lifecycle follow the same Rule 15 taxonomy: `polish(<feature-slug>): …` for tweaks, `fix(<feature-slug>): …` for bugfixes, `feat(<feature-slug>): …` only for genuinely new sub-surfaces, `docs(<feature-slug>): …` for IMPL-doc-only edits (checkbox flips after a phase ships, etc.).

Use `git add` with only the files this skill touched (do not blanket-add). If the commit's pre-commit hook fails, **do not amend** — fix and recommit.

### Step 9 — Report

Single terse message:

```text
Wrote docs/<FEATURE>-IMPL.md, updated CONTEXT/TODO/LOGBOOK, committed <sha>.
N phases · M open questions auto-resolved (K deferred for operator) · J <TBD> remaining.

Auto-resolved defaults to review:
- Q1: <one-line resolution>
- Q2: <one-line resolution>

Next phase: <FEATURE>.1.1 — <first checkbox>. Run /run-impl <FEATURE> when ready.
```

Do **not** suggest running `/clarify-impl` — its work is folded in. Do **not** suggest `/qa-pass` until the operator has actually started phase 1.

### Step 10 — Chain into execution (ONLY with `--and-run`)

Without the flag, Step 9 is the final report and this skill is done.

With `--and-run`: re-read [`../run-impl/SKILL.md`](../run-impl/SKILL.md) and execute it inline in default mode against `<FEATURE>`, passing through `--no-commit` and `--no-promote` if they were given here. From that point Rule 18 governs: the run drives every phase through promotion and stops only for a stop-set member.

**Why this is opt-in here and default in `/run-impl`.** Rule 18 exists so that a run in progress does not stop for no reason. It does not follow that *starting* one should be implicit. `/bootstrap-impl` takes a one-line feature description and, chained, would turn it into committed and promoted code — that is a command a person should type deliberately. `/run-impl` is already that deliberate act; bootstrap is not.

## Constraints

- **Parallel dispatch is mandatory** when ≥2 subagents fire. Sequential subagent calls defeat the purpose. Single message, multiple `Agent` tool blocks.
- **Always pass `model: "opus"`** to every Agent call this skill spawns. Bootstrap is a one-shot up-front investment; brute-force the smartest model.
- **Subagent context isolation is the load-bearing primitive** — same as `audit-impl`. The main session must not duplicate the work the subagents do; it stitches and reports only.
- **Don't fabricate file paths.** Subagent A's prompt explicitly forbids this. If you don't know a path, write `<TBD>` — auto-resolver (E) treats `<TBD>` like an Open Question.
- **Don't chain unless asked.** By default this skill creates a tracker, not a shipped feature. `--and-run` is the opt-in, and even then `/promote-impl` remains the only path to `impl/` + `reference/`.
- **Never promote from inference.** Rule 19 puts the DECIDE with a person: promotion follows either a direct `/promote-impl`, or a default-mode run that person started. It never follows from this skill concluding a tracker "looks done".
- **Don't run when an IMPL collision is detected.** Step 2 abort is non-negotiable — silent overwrites destroy in-progress work.
- **`--ground` is opt-in, not default.** Reasoning: greenfield IMPLs benefit from grounding; pure design-doc IMPLs (e.g., new architecture proposals) over-constrain on existing code if you ground them. The 30s wall-clock cost is cheap; the risk of over-constraint is real. Operator chooses.
- **No mid-flow prompts.** Pick defaults, surface them in the IMPL, commit. The operator's review surface is the commit diff, not a chain of `/clarify-impl` follow-ups.

## Tool allowlist (advisory, when supported)

Main session: `Read, Glob, Grep, Write, Edit, Bash(git add:*), Bash(git commit:*), Agent`. Subagents inherit their `subagent_type` defaults (Plan / general-purpose / Explore are all read-only by configuration except for the eventual `Write` / `Edit` / `git` steps done by the main session in Steps 6–8).

## Why this exists

Two failure modes this skill targets:

1. **Cold-start drag.** Drafting a new IMPL from scratch in a single session takes 30–60 min before any real design work begins, because the same context window is being used for header boilerplate, phase decomposition, and ambiguity-hunting simultaneously. Each task contaminates the others.
2. **Skipped clarify ceremony.** Even with `clarify-impl` available, operators tend to skip it when the IMPL is freshly drafted — the questions feel premature. Generating the Open Questions block as part of the *initial* draft makes it part of the artifact, not an opt-in step.

## Agent execution

Project-level skills under `.claude/skills/` aren't exposed via the Skill tool surface as of 2026-05. When an agent session encounters `/bootstrap-impl …`, it reads this SKILL.md and executes the procedure inline: Read steering context, dispatch subagents in a single parallel `Agent` call burst, stitch, write, report. No Skill-tool dispatch.

Companion skills:

- `/clarify-impl <FEATURE>` — only when the operator wants to re-open Open Questions on an already-bootstrapped IMPL. Bootstrap folds clarify in by default.
- `/audit-impl <FEATURE>` — drift check once code starts landing.
- `/qa-pass` — end-of-phase audit when a phase flips to complete.
- `/run-impl <FEATURE>` — execute the phases this skill scaffolded.
- `/promote-impl <FEATURE>` — Rule 12 promotion when all phases ship.
