---
name: roadmap
description: Create or update a repo's docs/ROADMAP.md — the live RoadMD v1 board (a fenced ```roadmap YAML model the cockpit renders natively). Authors the model with judgment from the repo's IMPL trackers plus a free-text instruction ("/roadmap reflect the plan in docs/design/foo.md"), reconciles an existing board instead of clobbering it, self-checks the R1–R7 rules, and regenerates the mermaid+table view if a roadmap renderer is available. Manual invocation only — never auto-fires.
---

# roadmap

Author or update `docs/ROADMAP.md` — the **RoadMD v1** live board. The board is a single Markdown file that is simultaneously a human-readable doc, a machine-parseable model the cockpit renders natively, and a format that structurally cannot drift (the visual parts are generated from the model, never hand-edited).

This skill is the **judgment-driven** counterpart to any mechanical "seed a board from folder names" endpoint: instead of mapping every `docs/*-IMPL.md` to `next` and every `docs/impl/*-IMPL.md` to `done` by folder alone, it *reads* the trackers and the operator's instruction and sets status, dependencies, and the single `next` pointer correctly.

## When this fires

- Operator runs `/roadmap [instruction]` — free-form trailing text steers the authoring, e.g.
  - `/roadmap` — create-or-update from the repo's IMPL trackers, best-judgment defaults.
  - `/roadmap reflect the plan in docs/design/combat-rework.md` — read that doc and shape the board to it.
  - `/roadmap mark NETCODE-AUDIT active and make it the next node`
  - `/roadmap the bots waves are all done; V1-HARDEN is blocked on NETCODE-MODERNIZATION`
- Optional flag: `/roadmap --fresh [instruction]` — ignore any existing board and author from scratch (still never deletes the file without showing a diff first).
- Optional flag: `/roadmap --path <repo-relative-path> [instruction]` — target a board other than `docs/ROADMAP.md`.
- Optional flag: `/roadmap --dry-run [instruction]` — author + validate + show the model, but do not write the file.
- **Do NOT auto-fire.** Editing the program board is an operator decision.

## Operating principle

Author the **model** (the ```roadmap YAML block). Everything else — the mermaid graph, the status table, the computed progress — is *generated from* the model, so this skill never hand-writes those. The operator's review surface is the resulting file diff.

Prefer **update over replace**: an existing board carries hand-authored `note:` lines, `needs:` edges, a `north_star:`, and `decisions:` the operator curated. Reconcile against it; do not blow it away.

## The RoadMD v1 model (what you author)

One fenced block per file, info-string exactly `roadmap`, containing YAML:

```roadmap
v: 1
project: <stable-id>            # matches the cockpit workspace id; lowercase, stable
title: <Human Title>
updated: <YYYY-MM-DD>           # bump on every model edit
north_star: >                   # optional; one paragraph, human-owned — preserve if present
  One sentence on what "done" means for this repo.
nodes:
  - id: <slug>                  # ^[a-z0-9][a-z0-9-]*$ — unique, STABLE, never renamed
    title: <FEATURE-NAME>
    kind: wave                  # wave | feature | capability | infra | decision
    status: done                # planned | next | active | blocked | done | descoped
    done: <YYYY-MM-DD>          # REQUIRED iff status: done
    needs: [<other-id>, ...]    # DAG edges by id; build order = topological sort
    impl: docs/<FEATURE>-IMPL.md        # repo-relative link to the tracker
    ref: docs/reference/<name>.md       # optional
    note: <one line max>        # detail lives in the IMPL, never here
decisions:                      # optional — open operator knobs, structured
  - id: <slug>
    status: open                # open | resolved
    note: <one line>
    blocks: [<id>, ...]         # optional — ids this decision gates
live:                           # optional — deploy state of running pieces
  - piece: <name>
    state: ok                   # ok | degraded | down
    note: <one line>
```

**The R1–R7 rules — self-check every one before writing (a renderer enforces them too, but you must not emit an invalid model):**

| # | Rule |
|---|---|
| R1 | Exactly one ` ```roadmap ` fence; YAML must parse; `v`, `project`, `updated`, `nodes` all present. |
| R2 | Enums are closed. `kind` ∈ {wave, feature, capability, infra, decision}; `status` ∈ {planned, next, active, blocked, done, descoped}. No prose states. |
| R3 | Every `needs` id must exist; the graph must be acyclic. |
| R4 | `status: done` requires a `done:` date; a `done` node may **not** `need` a non-done node (that would be a lying board). |
| R5 | **At most one** node may be `status: next`. It is *the* pointer — "what do we do now" must be unambiguous. |
| R6 | The generated render section (mermaid + table) must be byte-identical to what the generator emits — so never hand-write inside the `<!-- roadmap:render … -->` markers. |
| R7 | Progress (`done/total` per kind) is **computed**, never stored. Do not write a progress field. |

## Procedure

### Step 1 — Resolve target + mode

- Target path: `--path` if given, else `docs/ROADMAP.md` at the workspace root.
- Read the target if it exists. If it has a ` ```roadmap ` block → **UPDATE mode**. Else (or with `--fresh`) → **CREATE mode**.
- Derive `project`: in UPDATE mode keep the existing value; in CREATE mode use the cockpit/workspace id if known, else the repo directory name lowercased.

### Step 2 — Gather the source material

Read into the session (do not dispatch subagents for a single-repo board unless the tracker count is large — then an `Explore` subagent to summarize statuses is worth it):

1. **The operator's instruction** (the free-text after `/roadmap`). This is the primary steering signal. If it points at a doc ("reflect the plan in X"), read X in full.
2. **Active trackers** — glob `docs/*-IMPL.md` (exclude `docs/impl/`). For each, read its `## Implementation Status` / checklist header to judge status:
   - all phases checked / "PROMOTED" language → `done` (but if it's still under `docs/`, prefer `active`/`next` and flag that it looks promotable).
   - some phases checked, work ongoing → `active`.
   - a blocker noted (Blockers section non-empty, "blocked on …") → `blocked`.
   - untouched / plan-only → `planned`.
   - explicitly descoped / superseded → `descoped`.
3. **Promoted trackers** — glob `docs/impl/*-IMPL.md` → `done`, with `done:` = the file's last-modified date (or a date the tracker states).
4. **Existing board** (UPDATE mode) — the current nodes, notes, needs, north_star, decisions. This is authoritative for anything the operator hand-curated.
5. **Dependency hints** — an IMPL's "needs / depends on / blocked by" prose, and the operator's instruction, feed `needs:` edges.

### Step 3 — Author (CREATE) or reconcile (UPDATE) the model

**CREATE:** emit one node per tracker with judged status; wire `needs:` from the dependency hints; pick exactly one `next` node (the smallest un-started slice the dependency order points at, or whatever the operator's instruction names); write a `north_star` from the instruction or the repo's CONTEXT/vision doc if one exists.

**UPDATE — reconcile, do not clobber:**
- **Keep** every existing node's `id`, hand-authored `note:`, `needs:`, `ref:`, and the `north_star`/`decisions`/`live` blocks unless the instruction changes them.
- **Add** a node for any tracker not yet on the board.
- **Advance** status where the filesystem proves drift: a node still `next`/`active`/`planned` whose IMPL now lives under `docs/impl/` → flip to `done` with today's (or the promoted file's) date. Mention each flip in the report.
- **Apply** the operator's instruction last — it overrides heuristics (e.g. "mark X blocked", "make Y the next node").
- **Preserve `id` stability** — never rename an id to match a new title; titles can change, ids cannot (R3 edges depend on them).

Then **self-check R1–R7**. Fix any violation before writing. The most common ones: two `next` nodes (R5) and a `done` node needing a non-done node (R4).

### Step 4 — Write the model, regenerate the view

1. Write the file with the prose header preserved (north-star prose, standing rules) + the updated ` ```roadmap ` block. In CREATE mode, scaffold a minimal header (`# ROADMAP.md — <title>` + a one-line "The live board (RoadMD v1); the roadmap block below is the source of truth" note).
2. **Regenerate the derived view (mermaid graph + status table)** if a roadmap renderer is available. Discover it in this order and use the first that resolves:
   - `$GHOSTDEV_ROADMAP_BIN` — if set, run `$GHOSTDEV_ROADMAP_BIN check <path>` then `$GHOSTDEV_ROADMAP_BIN render <path>`.
   - A project-local roadmap CLI — if the workspace ships one (a `roadmap` subcommand on the project's dev CLI, or a `bin/*roadmap*` script), run its `check` then `render`.
   - Otherwise **skip the render** — the ```roadmap model is still valid and the cockpit renders it natively from the YAML. Note in the report that the mermaid/table section was not regenerated (no renderer found) and how to render later.
   - Never hand-write the mermaid or table (R6). If no renderer exists, leave the render markers absent rather than fake them.
3. If a renderer ran `check` and it fails, **fix the model and re-run** — do not commit a board the validator rejects.

### Step 5 — Report

Terse summary:

```text
<Created|Updated> docs/ROADMAP.md — <N> nodes (<done>/<total> done), next: <node-id or "none">.
Status changes this run:
  - <id>: <old> → <new> (<why: promoted / operator instruction / new tracker>)
Validation: <R1–R7 clean via renderer | self-checked (no renderer found — model valid, mermaid not regenerated)>.
```

If invoked with `--dry-run`, print the authored ```roadmap block instead of writing, and stop.

## Constraints

- **Author the model only.** Never hand-write the mermaid graph, the status table, or a progress field — all three are generated (R6/R7). If you can't run the generator, omit the render section; don't fabricate it.
- **Ids are immutable.** Reconcile by id. Renaming an id silently breaks `needs:` edges and any cockpit deep-link.
- **One `next` (R5).** If the operator's instruction and the heuristics disagree on the pointer, the instruction wins; if neither names one, pick the dependency-frontier node and say so.
- **Never silently overwrite a curated board.** UPDATE mode preserves hand-authored notes/edges/north_star; `--fresh` still shows the resulting diff before the write is final.
- **Status is judged, not folder-derived.** Reading a tracker's checklist beats mapping its folder — a descoped IMPL under `docs/` is `descoped`, not `next`.
- **Detail stays in the IMPL.** `note:` is one line. The board is the map, not the territory (no-duplication rule).

## Companion skills

- `/bootstrap-impl <feature>` — scaffold a new tracker; then `/roadmap` folds it onto the board as a node.
- `/run-impl <FEATURE>` — execute a tracker's phases; re-run `/roadmap` after a phase ships to advance the node's status.
- `/promote-impl <FEATURE>` — Rule 12 promotion; re-run `/roadmap` to flip the node to `done` and move its `impl:` link under `docs/impl/`.

## Agent execution

When a session encounters `/roadmap …`, read this SKILL.md and execute the procedure inline (Read trackers + instruction → author/reconcile the ```roadmap model → self-check R1–R7 → write → render if a tool is discoverable → report). No Skill-tool dispatch is required.
