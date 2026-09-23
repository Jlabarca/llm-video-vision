---
name: hygiene-impl
description: Repo-wide docs-hygiene sweep. Identifies IMPLs ready for promotion, runs the two DOCS-PROTOCOL validation tasks (reference-doc drift + folder hygiene), and surfaces drift across stale IMPLs via parallel audit-impl subagents. Read-only — produces a prioritized punch list; the operator runs /promote-impl, /audit-impl, or doc edits afterward. Use this every 2-4 days, after a major shipping window, or before generating an IMPL coordination report.
---

# hygiene-impl

End-to-end docs-hygiene sweep. Aggregates `/audit-impl` + the two protocol validation tasks + a promotion-candidate scan into one report. Read-only — no edits, no promotions. The operator decides what to act on.

## When this fires

- User runs `/hygiene-impl` (no args) — sweeps the whole `docs/` tree + child-repo IMPL roots.
- User runs `/hygiene-impl FEATURE` — narrower sweep focused on one IMPL + its surrounding hygiene context.
- Recommended cadence: every 2–4 days, after a major shipping window, or as the pre-flight before generating an IMPL coordination report.

## Procedure

This skill is **read-only** and orchestrates other read-only skills + tasks. Three phases run mostly in parallel; the report aggregates at the end.

### Step 0 — Inventory

1. `Glob 'docs/*-IMPL.md'` → active root IMPLs.
2. `Glob 'docs/impl/*-IMPL.md'` → promoted IMPLs (for cross-reference checks).
3. If the project has child repos with their own `docs/`, glob those too (per `GHOSTDEV_EXTRA_IMPL_ROOTS` env var convention if set; otherwise infer from recent reports under `docs/report/`).

### Step 1 — Promotion-candidate scan

For each active IMPL, read just the header + Implementation Status table + Known Bugs section, then classify:

| Signal | What it means |
|---|---|
| All `[ ]` checklist items resolved (no open `[ ]`) | Promotion-eligible on checklist gate |
| `Known Bugs` empty OR all entries `~~strikethrough~~` | Bug gate clear |
| `docs/reference/{feature}.md` exists | Reference-doc gate satisfied |
| Header has `tests-deferred:` flag OR test suite green | Test gate satisfied or explicitly waived |
| `Updated:` date >7 days old | **Audit recommended before promotion** |

An IMPL passing all four gates is a **promotion candidate** — list it under "Promote ready" in the report. An IMPL passing 3/4 with the missing piece being the reference doc is "Draft reference doc, then promote." Any other state is reported under its respective gap.

### Step 2 — Drift audit (parallel subagents)

For each IMPL stale >7 days OR flagged as promotion candidate, dispatch a `Plan` subagent in parallel (one per IMPL). Each subagent runs the same brief as `/audit-impl` would:

```
Read docs/{FEATURE}-IMPL.md fully.

For each file in its "Key Files Reference" table:
- Verify the file exists at the cited path
- If line numbers are cited, verify the line still contains the cited symbol
- Note files that have changed materially since the IMPL's Updated: date

For each unchecked checkbox in the IMPL:
- Grep the codebase for the phase ID in commit messages
- If found in commits but unchecked → drift item

For each cited research/reference doc:
- Verify the doc exists at the cited path

Report a punch list under 200 words:
- Drift items (concrete: "X claims Y but Z")
- Stale references (links that 404 inside the repo)
- Apparent inconsistencies between checklist and git history
- Tests claimed but not present in tests/ folders

Do not propose fixes. Do not edit. Just report.
```

Cap each subagent's output at ~200 words (tighter than `/audit-impl`'s 300 to keep the aggregate report scannable). If >8 IMPLs need auditing, sample the 8 stalest — full coverage is what `/audit-impl FEATURE` is for.

### Step 3 — Protocol validation (parallel)

Dispatch two more `Explore` subagents (or one `Explore` subagent doing both in sequence) running the exact validation tasks from `docs/DOCS-PROTOCOL.md` § Validation Tasks. **Use `Explore`, not `general-purpose`** — these tasks are strictly read-only ("Do not propose fixes. Do not edit. Just report."), so the cheaper read-only agent (skips CLAUDE.md, search-optimized) is the right fit:

**Task A — Validate Reference Docs:**

```
Read docs/DOCS-PROTOCOL.md and docs/README.md.
For each file in docs/reference/:
  1. Flag if "Updated:" date is older than 30 days
  2. Verify file paths and code snippets still exist in the codebase
  3. Check for status tracking (TODO lists, milestone %) — these belong in CONTEXT.md
  4. Check for mermaid diagrams and code snippets — flag reference docs that have neither
  5. Check <!-- CURRENT --> / <!-- IMPROVEMENT --> tags are present and correct

Output a table:
| File | Last Updated | Stale Paths | Status Leak | Has Diagrams | Has Code | Action |
```

**Task B — Validate Docs Hygiene:**

```
Read docs/DOCS-PROTOCOL.md, then audit the full docs/ folder:
  1. Root files: verify ALL CAPS only (flag lowercase .md at root)
  2. README.md: verify every non-archive .md is listed (flag orphans)
  2b. README.md "Archived IMPL Trackers": every impl/ row must have a real docs/impl/ file behind it
      (write-ordering rule, GDC.5.5 - a row written ahead of its promotion misleads the Rule 17 sweep)
  3. research/: flag docs that describe already-implemented features (→ reference/ or archive/)
  4. archive/: scan for files still referenced by non-archive docs (stale links)
  5. CONTEXT.md: verify "Current Sprint" items have matching TODO.md entries
  6. TODO.md: verify no completed sprint sections older than 2 sprints
  7. BACKLOG.md: flag items marked done without strikethrough, or items now in TODO.md
  8. reference/: flag files with TODO lists, milestone %, or progress tracking (Rule 4 violation)

Output a report with violations grouped by rule number and suggested fixes.
```

### Step 4 — Aggregate the report

Produce the punch list inline (do **not** write a file — this skill is ephemeral; if the operator wants persistence, they ask for an IMPL coordination report). Output shape below.

## Output shape

```
## Hygiene sweep — YYYY-MM-DD

### Promote ready (N)
- FEATURE-A — all gates clear; reference/feature-a.md drafted YYYY-MM-DD. Run /promote-impl FEATURE-A.
- FEATURE-B — gates clear, but Updated: 14 days old; recommend /audit-impl FEATURE-B first.

### Almost-promotable (N)
- FEATURE-C — checklist + bug gates clear; missing docs/reference/feature-c.md.
- FEATURE-D — checklist clear; 1 open Known Bug (BUG.2 — root-cause unclear).

### Drift items from audits (N IMPLs scanned)
- FEATURE-E: 2 drift items, 1 stale ref. (Run /audit-impl FEATURE-E for full report.)
- FEATURE-F: clean.
- ...

### Reference-doc issues (Rule 4 / 5)
- reference/x.md — Updated 45 days ago; Rule 4 status leak (contains "TODO:" list).
- reference/y.md — no diagrams, no code snippets (Rule 5).

### Folder-hygiene issues (Rule 9 / 10 / 11)
- docs/orphan-note.md — lowercase root file (Rule 10 violation).
- docs/research/old-thing.md — describes shipped feature, candidate for archive/.
- README.md missing entry for docs/some-new.md.

### CONTEXT.md / TODO.md / BACKLOG.md drift
- CONTEXT "Current Sprint" lists FEATURE-G — no matching TODO.md entry.
- BACKLOG item "do the X" — done in commit abc1234 but not struck through.

### Suggested next actions (priority order)
1. Promote FEATURE-A (~5 min, clears highest-value gate).
2. Draft reference/feature-c.md (~30 min, then promote FEATURE-C).
3. Doc-hygiene PR for the 4 folder-hygiene items (~15 min, batchable).
4. Audit FEATURE-E with /audit-impl FEATURE-E.
```

If a section has zero items, replace its body with `Clean.` rather than omitting the section — readers should be able to see at a glance that hygiene was checked across every dimension.

## Constraints

- **Read-only.** No edits, no file writes, no git mutations, no skill invocations that mutate (no auto `/promote-impl`). Tool grant for the orchestrator excludes `Edit`, `Write`, `Bash(git commit:*)`, etc.
- **Subagents do the heavy reads.** Audits + validation tasks fork into subagents so the main session's context stays clean — only the punch list comes back.
- **Cap aggregate output at ~600 words.** Long hygiene reports get ignored. Brevity is the feature.
- **No promotions, ever.** The skill *identifies* candidates; the operator runs `/promote-impl` separately. This separation is load-bearing — promotion is a destructive file move that must always be operator-confirmed.
- **Sample, don't exhaust.** With >8 stale IMPLs, audit the 8 stalest. The point is to surface the worst drift, not to produce an exhaustive ledger.
- **No write to `docs/report/`.** That path is for IMPL coordination reports, which are a separate, more thorough artifact. Hygiene sweeps are ephemeral.

## Tool allowlist (advisory, when supported)

`Read, Grep, Glob, Bash(git log:*), Bash(git diff:*), Bash(git status), Agent(Plan)`. Never `Edit`, `Write`, mutating git.

## Why this exists

The protocol's hygiene mechanisms (`/audit-impl` per IMPL, `/promote-impl` per IMPL, the two validation tasks, IMPL coordination reports) are individually targeted. Running them piecewise across a 20+ IMPL repo is friction the operator skips, so hygiene drift accumulates. `/hygiene-impl` is the single entry point that fans out the full sweep into parallel subagents, aggregates a prioritized punch list, and lets the operator pick what to act on. It exists for the same reason `/qa-pass` exists at end-of-phase — to be the obvious thing to run *now* without remembering which sub-skill applies to which symptom.

## Agent execution

When invoked, the agent reads this SKILL.md, then orchestrates the four steps above. Each `/audit-impl`-equivalent and each validation task fires as a parallel `Plan` subagent — context-preserving by construction. The aggregate report is the only thing that returns to the main session. If the operator wants the report persisted, they say so explicitly (and the natural target is a fresh IMPL coordination report under `docs/report/`, not this skill's output).
