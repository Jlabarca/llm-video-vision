# CONTEXT.md — llm-video-vision Project State

> Single source of truth for current state, architecture decisions, and active sprint.
> Updated: 2026-09-23

---

## What's Running

| Component | State | Notes |
|---|---|---|
| `watch` / `lvw` | In progress | One contact sheet, budget 9, cap 12. Keyframe scene pass + 30s floor + pixel dedup. |
| `detail` | In progress | A short window, budget ≤ 6, same sheet shape. |
| MCP stdio server | In progress | `node dist/server.js`. Skill at `skills/watch-video/SKILL.md`. |

---

## Architecture Decisions (Locked)

| Decision | Choice | Rationale | Date |
|---|---|---|---|
| Image budget | 9 default, hard cap 12, one grid | A hundred inline frames both miss the end of a long video and blow the context window. One sheet is the unit the model pays for. | 2026-09-23 |
| Scene pass | Keyframes at 320px, threshold 10, `partial` on timeout | Full-frame 4K analysis is what makes the upstream tool return an empty scene list after 600s. | 2026-09-23 |
| Coverage | Density floor + farthest-point thinning | The kept frames span the file. The first minutes are not the only minutes. | 2026-09-23 |
| Transcript | Captions first, language list, excerpt in the tool result | Manual captions in the requested language beat a Whisper pass. The full text stays on disk. | 2026-09-23 |
| Distribution | Original TypeScript MCP + CLI, not a Claude-only plugin | The host already interprets. The tool only perceives. Study: [research/upstream-claude-video-vision.md](research/upstream-claude-video-vision.md). | 2026-09-23 |

> The locked-decisions table is the load-bearing artifact of this methodology. Add a row every time you make a non-obvious choice with rationale, dated. See [DOCS-PROTOCOL.md Rule 8](DOCS-PROTOCOL.md).

---

## Milestone Status

| Milestone | Status | Notes |
|---|---|---|
| Repo birth (`ware new`) | ✅ Done | Public `jlabarca/llm-video-vision`, methodology installed 2026-09-23 |
| M0 budgeted watch | 🔄 In progress | Selection, sheet, captions, MCP, CLI. Eval set still deferred. |

---

## Current Sprint

**M0 — budgeted watch** (2026-09-23)

Goal: a `watch` call that covers a whole video with at most 12 images.

See [TODO.md](TODO.md) for the active checklist.

Active tracks:

- Selection, dedup, and the contact sheet
- Captions-first transcript excerpt
- MCP `watch` / `detail` and the `lvw` CLI

---

## Documentation Index

| Doc | Purpose |
|---|---|
| [README.md](README.md) | Docs folder index |
| [CONTEXT.md](CONTEXT.md) | This file — living state |
| [TODO.md](TODO.md) | Active sprint checklist |
| [BACKLOG.md](BACKLOG.md) | Non-blocking ideas and deferred work |
| [LOGBOOK.md](LOGBOOK.md) | Append-only session history |
| [DOCS-PROTOCOL.md](DOCS-PROTOCOL.md) | Documentation rules |
| [research/upstream-claude-video-vision.md](research/upstream-claude-video-vision.md) | Study of jordanrendric/claude-video-vision and the decisions this repo ships |
