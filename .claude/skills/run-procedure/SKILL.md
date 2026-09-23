---
name: run-procedure
description: Execute a procedure from .claude/procedures/{name}/PROCEDURE.md — runs the Should-I-Run-Now gate, the step list, validates the Verdict block, conditionally executes follow-up actions, appends LOGBOOK. The executor counterpart to /record-procedure. Use when the operator invokes /run-procedure {name}, when a scheduled /loop or /schedule wrapper dispatches one, or when a project-specific AFK runner kicks off. Procedures are a structured sub-genre of SKILL.md; see docs/reference/procedure-schema.md.
---

# run-procedure

The executor for procedures — the SKILL.md sub-genre with a mandatory state gate, structured Verdict, and conditional execute step. Where `/run-impl` drives one IMPL through phase-by-phase shipment, `/run-procedure` drives one procedure through gate → research → decide → conditional-execute. The procedure's PROCEDURE.md is the body; this skill is the interpreter.

## When this fires

- Operator runs `/run-procedure {name}` — execute the named procedure once against current state.
- Optional flags:
  - `/run-procedure {name} --focus "..."` — pin the research to a specific topic (overrides the procedure's state-driven trigger scanner if it has one).
  - `/run-procedure {name} --scope "..."` — narrow or widen scope from the procedure's default.
  - `/run-procedure {name} --force` — bypass gate failure. Emits a LOGBOOK warning. Use only when the operator explicitly wants to override (BUG.3 mitigation in PROCEDURE-RECORDING-IMPL).
  - `/run-procedure {name} --budget '{...}'` — JSON object overriding `max_turns`, `max_wall_clock_min`, `max_tokens`, or `model`. Per-key override; unspecified keys fall back to PROCEDURE.md frontmatter.
  - `/run-procedure {name} --dry-run` — run the gate + steps but skip step 5 (execute) even if `execute_safe: true`. For sandbox / preview.
  - `/run-procedure {name} --audit` — after each step in Step 3, pause and dispatch a fresh-context auditor subagent. See [docs/reference/audit-mode.md](../../../docs/reference/audit-mode.md) for checkpoint payload shape, Verdict grammar, and revision-loop rules.
- Auto-trigger from `/loop` or `/schedule` wrappers — same behavior, no flags needed unless the schedule entry supplied them.
- Project-specific AFK-runner dispatch (if the project wires one) — the dispatch command carries `name` + optional inputs.
- **Manual only in v0.** No auto-firing from observed signals; the operator (or an explicit schedule/AFK dispatch) owns invocation.

## Procedure

### Step 0 — Resolve the procedure

1. Compute repo root via `git rev-parse --show-toplevel`.
2. Resolve `.claude/procedures/{name}/PROCEDURE.md`. If missing, abort with `Reason: not-found(procedure: {name})`.
3. Read the PROCEDURE.md. Parse the YAML frontmatter (name, genre, triggers, budget).
4. Validate against [docs/reference/procedure-schema.md](../../../docs/reference/procedure-schema.md) (see § 4 — Validation rules). On failure: abort with `Reason: schema-violation({rule})`.

### Step 1 — Recursion guard

1. Read `~/.claude/procedures/.recursion-guard` if present. The file is one stack-frame per line: `{name}|{started-ISO}|{pid-or-session-id}`.
2. If `{name}` already appears in the stack, that's depth-≥2 recursion — abort with `Reason: procedure-recursion` (BUG.4 mitigation).
3. If the stack depth (regardless of name) is ≥2, abort with same reason — recursive depth is the limit, not name-specific.
4. Append a stack frame. The frame is removed in Step 8 regardless of success/failure path.

Implementation detail: the guard file is per-user, not per-repo. A `walters-research` run on one repo and another on a different repo simultaneously is allowed (different sessions), but the recursion stack catches transitive procedure→procedure dispatch within a single session.

### Step 2 — Should-I-Run-Now gate

For each check in the procedure's `## Should I Run Now? (state gate)` section, in order:

1. Parse the check's `**NAME** — description ending in "SKIP if/when …"`.
2. Look up the named check's implementation. v0 ships with built-in implementations for the standard checks: `recent-run-cooldown`, `weekly-budget`, `active-afk-runs`, `candidate-unknown-found`. Procedure-specific checks should reduce to these or document a parseable predicate inline (e.g. `SKIP if file X exists`).
3. Run the check. If it fails:
   - If `--force` flag was set: log a warning to LOGBOOK + continue.
   - Else: abort with `Reason: gate-failed({check-name})`. Skip to Step 8 (cleanup) → Step 9 (report SKIP).

Standard checks (referenceable by name in any procedure):

| Check | Detection |
|---|---|
| `recent-run-cooldown` | Grep most-recent LOGBOOK entry beginning `## YYYY-MM-DD — {procedure-name}`. If <{cooldown-min from check description} ago → fail. |
| `weekly-budget` | Read `~/.claude/projects/{repo-slug}/budget.json` if present; check `tokens_used_this_week / weekly_cap` < 0.80. Vacuously pass if budget.json absent. |
| `active-afk-runs` | (Project-specific. Skip in template-default setups; adopters wiring an AFK runner re-add the check with their own sidecar schema and terminal-state detection.) |
| `candidate-unknown-found` | Procedure-specific. Defer to the procedure's trigger-scan logic; pass if scan returned ≥1 candidate OR `--focus` input supplied. |

Unknown check names produce `Reason: gate-failed(unknown-check: {name})` unless the procedure documents the check inline with a parseable predicate.

### Step 3 — Execute Steps in order

For each step in the procedure's `## Steps` section, in order:

1. Read the step's `### N. **{kind}** — {label}` heading. Dispatch on `{kind}`:

#### 3a. `research` — read sources

- If the step body contains a `Fanout:` line + subagent list: dispatch one `Agent`-tool call per subagent in **parallel** (single message, multiple tool uses). Each subagent gets `focus`/`scope` inputs + its assigned source set + the prompt verbatim from the step body.
- If no Fanout: the main session reads the listed sources directly via `Read` / `Glob` / `Grep`.
- Capture each subagent's output as Markdown content. Stash in `~/.claude/procedures/.run-state/{run-id}/research-{N}-{subagent}.md` (transient — cleaned up Step 8).
- If a subagent fails: log the failure; the synthesize step decides whether the failure is fatal (typically: 2-of-3 subagents succeeding is enough; <2 → halt with `Reason: research-incomplete`).

#### 3b. `synthesize` — stitch into one artifact

- The main session reads the prior step's outputs (subagent notes or direct reads) and produces one artifact, typically a research doc.
- Output path is computed deterministically from inputs per [procedure-schema § 6](../../../docs/reference/procedure-schema.md#6-conventions).
- Write via `Write` tool. Path is added to the run's `output_artifacts` list.

#### 3c. `decide` — produce Verdict block

- The main session reads the synthesize output + subagent notes and emits exactly one Verdict block.
- Verdict is parsed as YAML inside a ` ```verdict ` fenced block.
- Validate the Verdict against [procedure-schema § 3.5](../../../docs/reference/procedure-schema.md#35-verdict-block):
  - Required keys present.
  - `option` in `{ratify, defer, reject, escalate}`.
  - `confidence` in `[0.0, 1.0]`.
  - `follow_up` action types in `{bootstrap-impl, amend-adr, notify}`.
  - Each action's required sub-fields present.
- **No Verdict block emitted → abort with `Reason: no-verdict`** (BUG.2 mitigation). The run is marked failed; report step (3f) still fires with the failure state.
- Stash the parsed Verdict at `~/.claude/procedures/.run-state/{run-id}/verdict.yaml`.

#### 3d. `gate` — check execute_safe + budget + scope

- Verify `verdict.execute_safe == true`. If false → skip step 3e, mark `executed: false`.
- Verify remaining budget: `turns_used < max_turns - 5` AND `wall_clock_min < max_wall_clock_min - 3` (5-turn / 3-minute headroom for execute + report).
- Verify `follow_up` contains at least one action other than `notify` (a notify-only Verdict needs no execute step — gate fails clean, but `executed: false` doesn't mean failure here, just no-op).
- Any failure → record reason; skip 3e.

#### 3e. `execute` — dispatch follow-ups (conditional)

For each entry in `verdict.follow_up`, in list order:

- `action: bootstrap-impl`:
  - Resolve the `/bootstrap-impl` skill (read [.claude/skills/bootstrap-impl/SKILL.md](../bootstrap-impl/SKILL.md)).
  - Dispatch inline (the main session executes the skill's procedure) with `<FEATURE-NAME>` and `scope`.
  - Capture the resulting commit SHA(s). Record on the run.
- `action: amend-adr`:
  - Read the target file (default `docs/CONTEXT.md`, override via `path`).
  - Use `Edit` to append `row` to the named table. Locate the table by its header text or by section heading + table sentinel.
  - Verify the row landed: re-read the file, grep for the row text, confirm one occurrence.
  - Commit as `docs({procedure-slug}): amend ADR — {one-line summary derived from row}`.
- `action: notify`:
  - `channel: console` → echo the body into the run's terminal report (Step 9).
  - `channel: discord` → v0: emit `unsupported in v0` warning; record the body in the report but don't dispatch externally.
  - `channel: github` → v0: same as discord — unsupported, recorded, not dispatched.

Each action: success/error captured. If an action fails, continue with remaining actions (best-effort) but mark `executed: partial`. Report (3f) lists per-action outcomes.

#### 3f. `report` — LOGBOOK + final summary

- Read the procedure's `## Output Artifacts` section to know what to mention.
- Append a four-section LOGBOOK entry per the procedure's `report` step body (the procedure-author defines the template; the executor substitutes runtime values).
- Use `Edit` to insert at the top of LOGBOOK.md (after the file header, before the most recent `## ` entry). Append-only per DOCS-PROTOCOL.md Rule 2.
- Emit the terminal report to stdout for `/loop` / `/schedule` capture, or to the chat for operator-initiated runs.

#### 3g. `--audit` checkpoint (fires after each completed step above, if flag is set)

Skip entirely if `--audit` was not passed.

1. Assemble the checkpoint payload:
   ```yaml
   checkpoint:
     diff: |
       <output of `git diff HEAD` scoped to files touched in this step>
     what_i_did: |
       <one paragraph: what this step produced and why>
     options_i_see:
       - option: A
         description: "continue as planned"
   ```
   For fork situations (≥2 viable paths the worker cannot resolve), add additional entries to `options_i_see`.

2. Dispatch an `Agent`-tool subagent. Pass **only** the checkpoint payload YAML as the subagent's entire prompt — no session history, no prior context.

3. Parse the returned Verdict block (fenced ` ```verdict ` YAML). Required fields: `option`, `confidence`, `rationale`, `override_hint`. `chosen_option` required when `option: choose`.

4. Branch on `option`:
   - `approve` → proceed to next step.
   - `revise` → increment per-checkpoint revision counter (starts at 0, resets at each new step).
     - Counter ≤ 2: re-execute the current step from scratch, then re-run this checkpoint.
     - Counter = 3: auto-escalate regardless of auditor output (round cap exhausted).
   - `choose` → resume with `chosen_option` from `options_i_see`; do not increment counter.
   - `escalate` → surface the rationale and `override_hint` to the operator; block until the operator responds.

5. Budget and recursion guard apply as in the non-audit path (see `### Step 5` and `### Step 1`).

### Step 4 — Per-run audit trail

After all steps complete (success or halt), write a single-file audit trail:

`<repo-root>/.runs/procedures/{run-id}.jsonl` (one event per line, NDJSON):

```jsonl
{"event":"ProcedureStarted","run_id":"...","procedure":"walters-research","started_at":"..."}
{"event":"GateChecked","check":"recent-run-cooldown","result":"pass"}
{"event":"StepCompleted","step":1,"kind":"research","duration_ms":...}
{"event":"VerdictEmitted","verdict":{...}}
{"event":"ExecuteAction","action":"bootstrap-impl","feature":"...","sha":"..."}
{"event":"ProcedureCompleted","run_id":"...","verdict_option":"ratify","executed":true,"duration_ms":...}
```

Create `.runs/procedures/` if absent. Add `*.jsonl` under `.runs/` to gitignore once on first run if not already.

### Step 5 — Budget enforcement (continuous, not a single step)

Throughout Steps 2–3, the executor watches:

- Turn count vs `budget.max_turns`. Exceed → abort current step with `Reason: budget-exceeded(max_turns)`, jump to Step 8.
- Wall-clock vs `budget.max_wall_clock_min`. Same handling.
- Token count vs `budget.max_tokens`. Same handling.

Budget-exceeded aborts still produce a partial Verdict / partial report — the report step (3f) fires with the partial state so the operator sees what was accomplished.

### Step 6 — Release recursion guard

Always remove this run's stack frame from `~/.claude/procedures/.recursion-guard`. Happens on every exit path (success, gate-fail, schema-violation, budget-exceeded, crash). If the conversation crashes before this step, the next session sees a stale frame and tolerates it after 2h (same TTL pattern as `/run-impl` session locks).

### Step 7 — Cleanup transient state

Remove `~/.claude/procedures/.run-state/{run-id}/` (the per-step output stash). The `.runs/procedures/{run-id}.jsonl` audit trail is **not** cleaned — it's the persistent record.

### Step 8 — Report

Single terse report block (operator-facing for `/run-procedure`, captured for scheduled runs):

```
/run-procedure {name}

Procedure: {name}
Run ID: {run-id}
Verdict: {option} (confidence {confidence})
Execute safe: {true|false}
Executed: {true|false|partial}

Steps:
  1. research       — pass ({duration}s, {turns} turns, {N} subagents)
  2. synthesize     — pass ({duration}s, wrote docs/research/{slug}-study.md)
  3. decide         — pass (verdict emitted)
  4. gate           — pass | skipped(reason)
  5. execute        — pass | skipped(execute_safe=false) | partial(...)
  6. report         — pass (LOGBOOK appended)

Follow-up actions executed:
  - bootstrap-impl {FEATURE} ({scope}) — sha {abc1234}
  - amend-adr docs/CONTEXT.md — sha {def5678}
  - notify console — "..."

Artifacts:
  - docs/research/{slug}-study.md (new)
  - docs/LOGBOOK.md (appended)
  - .runs/procedures/{run-id}.jsonl (audit)

Budget used: {turns}/{max_turns} turns, {min}m/{max_min}m wall, {tokens}/{max_tokens} tokens
```

Halt paths produce the same shape with `Verdict: aborted({reason})` and partial step list. Step 6 (report) still fires on halts so the LOGBOOK records the failure state.

## Constraints

- **Manual invocation only by default.** Auto-firing requires a project-specific scheduled/AFK wrapper.
- **Recursion guard is non-negotiable.** Depth >2 always aborts — even with `--force`.
- **Gate failure ≠ run failure.** A SKIP from gate is a valid outcome — recorded in LOGBOOK, audit trail emitted, no error to the caller. Only schema-violation, no-verdict, and budget-exceeded are run failures.
- **Verdict block is the only way to claim success.** If the `decide` step's output doesn't contain a parseable `verdict` block, the run fails with `no-verdict` regardless of how clean the prior steps were (BUG.2 mitigation).
- **`Write` over `Edit` only for new artifacts.** Procedure outputs that don't exist yet (research docs, recording-source.md) use `Write`. LOGBOOK + CONTEXT.md (amend-adr) always use `Edit` to preserve append-only semantics (Rule 2).
- **No `git push` in v0.** Procedures may produce commits via follow-up actions, but never push. Operator decides when to ship.
- **No network actions outside `notify`** — and `notify` channels other than `console` are stubs in v0.

## Tool allowlist (advisory)

`Read, Glob, Grep, Edit, Write, Bash(git rev-parse:*), Bash(git log:*), Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(date:*), Agent` (the last one for the research subagent fanout).

Never used by this skill: `Bash(git push:*)`, `Bash(git reset:*)`, `Bash(git checkout -- :*)`.

## Why this exists

Three failure modes this skill targets:

1. **Schedulable research without operator presence.** `/loop` and `/schedule` already exist, but their body needs a state-gate to avoid burning budget when nothing has changed. Procedures supply that gate; this skill enforces it.
2. **Structured Verdicts that downstream gating can read.** A free-form skill output can't be parsed by an automation; a fenced YAML Verdict block can. The schema-validation in step 3c is what makes procedure outputs composable.
3. **Recursive procedure runaway.** Without the depth guard, a `walters-research` whose execute step bootstraps an IMPL whose initial LOGBOOK entry triggers another `walters-research` is an obvious loop. The recursion guard is cheap and catches the failure mode early.

The cost is a stricter schema than SKILL.md, but the payoff is procedures the operator can schedule without supervision — which is what makes the AFK fast-lane possible.

## Companion skills

- `/record-procedure {name}` — extracts a procedure draft from recent LOGBOOK + commit history (PROC.2 ships this).
- `/bootstrap-impl <FEATURE>` — invoked as a follow-up action when `verdict.follow_up` contains `bootstrap-impl`.
- `/loop` and `/schedule` — wrap `/run-procedure` for periodic execution. Project-specific AFK-runner wrappers (if wired) feed the same path.

## Agent execution

Project-level skills under `.claude/skills/` are not exposed via the Skill tool surface as of 2026-05. When an agent session encounters `/run-procedure {name}`, it reads this SKILL.md and executes the procedure inline: resolve the procedure → recursion guard → state gate → step loop → audit trail → cleanup → report. No Skill-tool dispatch.

## See also

- [docs/reference/procedure-schema.md](../../../docs/reference/procedure-schema.md) — the schema this skill validates against
- [.claude/procedures/walters-research/PROCEDURE.md](../../procedures/walters-research/PROCEDURE.md) — the canonical reference procedure
- [docs/archive/procedure-recording-design.md](../../../docs/archive/procedure-recording-design.md) § 5 — recording vs authoring vs replay (this skill executes; record-procedure records)
- [docs/PROCEDURE-RECORDING-IMPL.md](../../../docs/PROCEDURE-RECORDING-IMPL.md) — rollout tracker
- [.claude/skills/run-impl/SKILL.md](../run-impl/SKILL.md) — sibling skill for IMPL phase-driving; same automatic-by-default principle
