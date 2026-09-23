---
name: record-procedure
description: Extract a procedure draft from a recent session by reading LOGBOOK entries + git log since N hours and inferring the session shape (trigger → research → verdict → execute). Writes a draft .claude/procedures/{name}/PROCEDURE.md + an audit trail at recording-source.md. The recorder counterpart to /run-procedure. Use after a research-shaped session that's worth capturing for reuse — when the operator says "this is the kind of arc I want to schedule." Per OQ-3 of PROCEDURE-RECORDING-IMPL: commit-graph + LOGBOOK based; transcript-based is P-future polish.
---

# record-procedure

The recorder for procedures. Where `/run-procedure` interprets a PROCEDURE.md against current state, `/record-procedure` writes a PROCEDURE.md by inferring shape from a session that just happened. The session lives in `git log` + the LOGBOOK; the recorder reads both, clusters by topic, and drafts a procedure that — when subsequently `/run-procedure`'d against analogous inputs — should reproduce a similar arc.

## When this fires

- Operator runs `/record-procedure {name}` — record the last 24h of session activity as a draft procedure named `{name}`.
- Optional flags:
  - `/record-procedure {name} --since "{N}h"` — override the lookback window (default `24h`). Accepts `h`, `d` units, or an ISO-8601 date like `2026-05-12T08:00:00Z`.
  - `/record-procedure {name} --topic "{filter}"` — narrow the clustering to commits/entries matching the filter (substring or regex). Useful when a session bundled multiple unrelated arcs.
  - `/record-procedure {name} --auto-save` — skip the operator-confirmation step before writing. Use only when the recorder is invoked from another procedure or a scripted batch.
  - `/record-procedure {name} --no-trail` — skip writing the `recording-source.md` audit trail. Default is to write it; this flag exists for one-off experiments.
- **Manual invocation only in v0.** No auto-firing.

## Procedure

### Step 0 — Resolve target

1. Compute repo root via `git rev-parse --show-toplevel`.
2. Resolve output dir: `.claude/procedures/{name}/`.
3. If `.claude/procedures/{name}/PROCEDURE.md` already exists: abort with `Reason: already-exists({path})`. Recording is non-destructive — overwriting a procedure happens via explicit operator edit, not implicit re-record.
4. Validate `{name}` is kebab-case + ≤40 chars. If not: abort with `Reason: invalid-name({rule})`.

### Step 1 — Gather raw source material

In parallel where possible:

1. **LOGBOOK entries** — read [docs/LOGBOOK.md](../../../docs/LOGBOOK.md) and any sub-repo LOGBOOK.md (Glob `**/LOGBOOK.md` excluding `node_modules`/`bin`/`obj`). For each, parse entries with `## YYYY-MM-DD —` headings. Filter to entries whose date is within the `--since` window.
2. **Git log** — `git log --since="{since-date}" --pretty=format:"%H|%aI|%s|%b"`. Capture commit SHA, ISO date, subject, body. If `--topic` was supplied, additionally filter with `--grep "{topic}"`.
3. **Research-doc creations** — `git log --since="{since-date}" --diff-filter=A --name-only --pretty=format:"%H"` filtered to paths matching `docs/research/*.md`. Captures which research docs were authored in the window.
4. **IMPL doc activity** — `git log --since="{since-date}" --name-only --pretty=format:"%H"` filtered to paths matching `*-IMPL.md`. Captures which IMPLs were touched.

If `--topic` filter narrows the source material to fewer than 2 commits AND fewer than 1 LOGBOOK entry: abort with `Reason: insufficient-source-material`. There isn't enough to infer a procedure shape from — the operator probably wants to either (a) widen `--since`, (b) loosen `--topic`, or (c) write the procedure by hand.

### Step 2 — Cluster into one or more session arcs

Group the gathered material into one or more **arcs**. An arc is a contiguous run of activity sharing a theme:

1. **Initial clustering by IMPL touched.** Commits touching the same `*-IMPL.md` belong to the same arc (likely). Commits touching no IMPL are clustered by subject-line similarity.
2. **Refine with LOGBOOK boundaries.** A LOGBOOK entry typically captures one arc. Map each entry to the commits in its day's range; assign the LOGBOOK's title as the arc's working title.
3. **Apply `--topic` filter** if supplied. Drop arcs whose commits + LOGBOOK don't match. If zero arcs survive: abort with `Reason: topic-filter-too-narrow`.

If multiple arcs survive, ask the operator (`AskUserQuestion`) which one to record. v0 records one procedure per invocation — bulk-recording is deferred.

### Step 3 — Infer the procedure shape

For the selected arc, derive each PROCEDURE.md section:

#### 3a. Frontmatter

| Field | Inference |
|---|---|
| `name` | From the `{name}` argument |
| `genre` | Default `research-verdict` if the arc produced a `docs/research/*-study.md` doc + a Decisions section in LOGBOOK; `audit-report` if the arc produced an audit doc; `refactor-sweep` if commits are mostly `polish:` / `refactor:`; ask the operator otherwise |
| `triggers` | Default `[manual]`. Operator may flip to `[manual, scheduled]` post-edit |
| `budget.max_turns` | Heuristic: `commits-in-arc * 5`, capped at 50. Below 5 commits → default to 30 (matches walters-research) |
| `budget.max_wall_clock_min` | Heuristic: actual wall-clock between first and last commit in arc, rounded up to nearest 5 min. Capped at 60 |
| `budget.max_tokens` | Default 200000. Recorder does not have visibility into actual token usage; left at the procedure-author's default |
| `budget.model` | Default `sonnet`. Operator edits post-record if the arc actually used Opus |

#### 3b. State gate

Default to walters-research-style gate checks (the standard four):

- `recent-run-cooldown` — 60 min default
- `weekly-budget` — 80% default
- `active-afk-runs` — no-trample default
- `candidate-unknown-found` — only if `genre: research-verdict`; replaced with `target-set-non-empty` for other genres

The recorder writes these as placeholders with a `<TBD>` note suggesting the operator review for the specific procedure. State-gate inference from a recorded session is inherently lossy — the gate is about *when* to run, which depends on context the recorded session may not exhibit.

#### 3c. Inputs

Inferred from the arc's commit messages + LOGBOOK Decisions section:

- If commits reference a specific feature name (`feat(foo):` ... `feat(bar):`), surface `feature` as an input
- If LOGBOOK Decisions mention "scope" or "focus", surface those as inputs
- Otherwise: default to `focus` (optional string) + `scope` (optional string), matching walters-research

#### 3d. Steps

This is the most heuristic part. Map arc events to step kinds:

| Arc event | Inferred step kind |
|---|---|
| `git log` shows a `docs/research/*-study.md` creation | `research` step |
| LOGBOOK has a Decisions section with rationale | `decide` step |
| Commits include `feat(...)` or `fix(...)` after the research/decide | `execute` step |
| LOGBOOK Next: line ends the arc | `report` step |
| `git log` shows multiple research docs created in parallel (within minutes) | research step with `Fanout:` block |

The recorder produces step bodies that are *paraphrases* of the source material, not verbatim copies — the step is a template for future runs, not a replay of the original. Each step body ends with a `> Recording source: <commit SHA(s) + LOGBOOK date>` line so the audit trail is in-band.

#### 3e. Verdict block

If the LOGBOOK Decisions section is well-formed, infer:

- `option` — usually `ratify` (the arc shipped); `defer` only if commits were reverted; `reject` if no executable output landed
- `confidence` — heuristic from the Decisions section's language ("strongly", "clearly" → 0.9; "we decided", "settled on" → 0.7; "leaning toward", "tentative" → 0.5)
- `rationale` — first complete sentence of LOGBOOK Decisions
- `override_hint` — last sentence of LOGBOOK Decisions, OR first sentence of LOGBOOK Blockers
- `execute_safe` — `true` if commits actually shipped in the arc; `false` if they didn't
- `follow_up` — generated by inspecting executed commits:
  - `feat(foo):` commit → `{ action: bootstrap-impl, feature: FOO, scope: <inferred> }`
  - `docs(...):` commit touching CONTEXT.md → `{ action: amend-adr, table: CONTEXT.md, row: "<row inferred from diff>" }`
  - LOGBOOK Next: line → `{ action: notify, channel: console, body: "<next line>" }`

Drafted Verdicts get a `<TBD: review by operator>` note in the override_hint field — recorded verdicts are almost always paraphrases that benefit from operator polish.

#### 3f. Output artifacts

Enumerate from the arc's file changes:

- `docs/research/*-study.md` paths that were created → list as "always" outputs (typed `research-doc`)
- LOGBOOK appends → list as "always" output
- CONTEXT.md amendments → list as "conditional on amend-adr" output
- IMPL bootstrap (NEW `*-IMPL.md`) → list as "conditional on bootstrap-impl" output

### Step 4 — Draft the PROCEDURE.md

Compose using the schema (see [docs/reference/procedure-schema.md § 3](../../../docs/reference/procedure-schema.md#3-proceduremd-schema)). Include:

1. The frontmatter from § 3a.
2. A `> ` blockquote summary derived from LOGBOOK Decisions, ending with "Source: recorded from session {start-date}–{end-date} via /record-procedure {YYYY-MM-DD}."
3. All six required H2 sections (`## Should I Run Now?` / `## Inputs` / `## Steps` / `## Verdict` / `## Output Artifacts` / `## Notes`) populated per Step 3.
4. A footer `## See also` block linking the schema, the recording-source.md audit trail, and any cited research docs.

Validate the drafted PROCEDURE.md against the [schema § 4 validation rules](../../../docs/reference/procedure-schema.md#4-validation-rules). If validation fails: include the validation errors as `<!-- VALIDATION-ISSUE: ... -->` HTML comments inside the draft and surface them in Step 6 (operator confirm). The operator can fix-while-reviewing.

### Step 5 — Write the audit trail

Compose `.claude/procedures/{name}/recording-source.md`:

```markdown
# {name} — recording source

> Audit trail for the procedure recorded via /record-procedure on {today}.
> Source window: {since-date} → {now}.
> Source filter: --topic "{topic}" (or "none" if not supplied).

## Source LOGBOOK entries

- [docs/LOGBOOK.md](../../../docs/LOGBOOK.md): {YYYY-MM-DD} — {title}
- [{sub-repo}/docs/LOGBOOK.md](../../../{sub-repo}/docs/LOGBOOK.md): {YYYY-MM-DD} — {title}
  (only if sub-repo LOGBOOK entries were in the arc)

## Source commits

| SHA | Date | Subject |
|---|---|---|
| {abc1234} | 2026-05-13 | feat(...): ... |
| ... | ... | ... |

## Inferred mapping

| Arc event | Inferred step | Mapped to PROCEDURE section |
|---|---|---|
| {commit / entry} | research-fanout | Step 1 |
| {commit / entry} | decide | Step 3 (Verdict) |
| {commit / entry} | bootstrap-impl follow-up | Step 5 execute action |

## Validation issues (if any)

- (validation errors from Step 4, if any)

## Notes for operator review

- Confidence heuristic picked {N}; consider lowering if {LOGBOOK signal X}
- State gate was inferred as walters-research-standard; specialize if needed
- {other inference caveats}
```

This file is **not** consumed at runtime by `/run-procedure` — it's a design-time artifact for the operator + future archaeology. Same conventions as `walters-research/trigger-scan.md`.

### Step 6 — Operator confirmation

Unless `--auto-save` was supplied:

1. Surface the draft PROCEDURE.md content (use `AskUserQuestion` with options `Save as drafted (Recommended) / Open in editor before saving / Discard`).
2. On `Save`: write the file. On `Open`: write to a tempfile path and report the path + the destination. On `Discard`: abort.
3. Optionally show the `recording-source.md` content separately or together; the operator may also choose to discard just the audit trail and keep the PROCEDURE.

### Step 7 — Write artifacts + report

1. Create `.claude/procedures/{name}/` if not present.
2. Write `PROCEDURE.md` + (unless `--no-trail`) `recording-source.md` via `Write`.
3. Append a LOGBOOK entry recording the operation: `## {today} — record-procedure: {name} drafted from {arc-title}`.
4. Emit the final report:

```
/record-procedure {name}

Recorded: {name}
Source window: {since-date} → {now}
Arc: "{arc-title}" — {N} commits, {M} LOGBOOK entries
Validation: {pass | N issues}
Files written:
  - .claude/procedures/{name}/PROCEDURE.md ({line-count} lines)
  - .claude/procedures/{name}/recording-source.md ({line-count} lines, audit)
  - docs/LOGBOOK.md (appended)

Inference confidence: {high | medium | low}
Recommended next steps:
  1. Review the drafted state gate (often the lossiest part)
  2. Tighten Verdict's rationale / override_hint
  3. Smoke: /run-procedure {name} --dry-run --focus "<test focus>"
```

## Constraints

- **Non-destructive.** Recording never overwrites an existing PROCEDURE.md. The operator deletes + re-records if intentional replacement is desired.
- **Manual invocation in v0.** No scheduled or auto-record. The operator decides what's worth capturing.
- **Heuristic, not deterministic.** Recorded procedures are *drafts*. The recorder cannot perfectly recover intent from artifacts — the operator review pass is load-bearing.
- **Commit-graph + LOGBOOK only.** Transcript-based recording is P-future (OQ-3 of [PROCEDURE-RECORDING-IMPL.md](../../../docs/PROCEDURE-RECORDING-IMPL.md)). Don't read `%USERPROFILE%/.claude/projects/` — that's the override-only path.
- **No git push, no destructive ops.** Recorder writes files + commits the LOGBOOK append, nothing else.

## Tool allowlist (advisory)

`Read, Glob, Grep, Write, Edit, Bash(git rev-parse:*), Bash(git log:*), Bash(git show:*), Bash(date:*), AskUserQuestion`. The clustering + inference is text-processing, no external dispatch.

Never used: `Bash(git push:*)`, `Bash(git reset:*)`, `Bash(rm:*)` against existing artifacts.

## Why this exists

Three failure modes this skill targets:

1. **Successful sessions evaporate.** A research → verdict → ratify arc costs hours of operator + LLM time; without a recording mechanism, the next analogous question re-derives from scratch. Recording captures the *shape* so subsequent invocations are cheaper.
2. **Manual procedure authoring is too high-friction.** Writing a PROCEDURE.md from scratch (six required sections, schema compliance, Verdict examples) competes with just doing the work in-session. Recorder lowers the bar: do the work; record after; review + polish.
3. **Audit trails go stale.** Tying the drafted procedure to a commit-SHA + LOGBOOK-entry trail makes the inference inspectable. Future operators (or future-you) can re-derive how the procedure was first scoped, which heuristics fired, and what got lost in translation.

The cost is that recorded procedures need an operator review pass before they're production-quality. That's the inverse trade vs `/bootstrap-impl` (which automates IMPL birth from scratch); here the source material is real, so the recorder produces less but with higher fidelity.

## Companion skills

- `/run-procedure {name}` — the executor; consumes the schema the recorder emits.
- `/bootstrap-impl <FEATURE>` — analogous "automatic by default" skill for IMPL docs (this recorder is the procedure-flavored equivalent for an existing arc rather than a feature-description).
- `/logbook-append` — adjacent; produces the LOGBOOK entries the recorder reads.

## Agent execution

Project-level skills under `.claude/skills/` are not exposed via the Skill tool surface as of 2026-05. When an agent session encounters `/record-procedure {name}`, it reads this SKILL.md and executes the procedure inline: resolve target → gather source → cluster → infer → draft + validate → audit trail → operator confirm → write + report. No Skill-tool dispatch.

For sessions where the operator wants to record-and-immediately-run, chain: `/record-procedure {name}` then `/run-procedure {name} --focus "<test focus>"`. The second invocation validates that the recorded procedure parses end-to-end against the schema.

## See also

- [docs/reference/procedure-schema.md](../../../docs/reference/procedure-schema.md) § 9 (Recording conventions) — the inverse-mapping rules this skill consumes
- [.claude/skills/run-procedure/SKILL.md](../run-procedure/SKILL.md) — the executor counterpart
- [.claude/procedures/walters-research/PROCEDURE.md](../../procedures/walters-research/PROCEDURE.md) — canonical reference for what a recorded procedure should look like
- [docs/archive/procedure-recording-design.md](../../../docs/archive/procedure-recording-design.md) § 5.2 — design rationale for commit-graph-based recording
- [docs/PROCEDURE-RECORDING-IMPL.md](../../../docs/PROCEDURE-RECORDING-IMPL.md) — rollout tracker
- [.claude/skills/bootstrap-impl/SKILL.md](../bootstrap-impl/SKILL.md) — sibling pattern; same `automatic-by-default` principle applied to a different artifact type
