# llm-video-vision

Token-budgeted video perception for any LLM: one contact sheet, captions before transcription, a hard cap of 12 frames.

> See [docs/CONTEXT.md](docs/CONTEXT.md) for current state, locked architecture decisions (with dates and rationale), and the active sprint. CONTEXT.md is the single source of truth — read it before assuming anything about the project.

## Stack

- **Language**: TypeScript (Node.js 20+)
- **Framework**: MCP stdio server (`@modelcontextprotocol/sdk`) plus the `lvw` CLI
- **Build / runtime**: `tsc`. Runtime needs `ffmpeg`, `ffprobe`, and `yt-dlp` for URLs
- **Test**: vitest (`npm test`)

## Documentation methodology

This project follows [ghostdev](https://github.com/waremoto/ghostdev). Read [docs/DOCS-PROTOCOL.md](docs/DOCS-PROTOCOL.md) end-to-end before making changes.

The operating loop:

```
1. open IMPL → 2. plan section if 2+ source files → 3. tick a box, with its
   evidence, and commit it → 4. /qa-pass at the phase boundary
   → 5. /logbook-append → 6. repeat until the phases are done
   → 7. /promote-impl — chained automatically by a default-mode /run-impl

Or: /run-impl <FEATURE> and let it drive the whole loop, stopping only for a
reason it names (Rule 18).
```

Fourteen skills under `.claude/skills/` automate the procedural parts — `/bootstrap-impl`, `/clarify-impl`, `/audit-impl`, `/run-impl`, `/qa-pass`, `/logbook-append`, `/promote-impl`, `/hygiene-impl`, `/handoff`, `/roadmap`, `/tdd`, `/record-procedure`, `/run-procedure`, `/triage-sessions`. Hooks under `bin/` surface state and warn on protocol drift; they warn rather than block by default (`GHOSTDEV_HOOK_BLOCK=1` opts into blocking). Status line shows the active phase ID. Output style `logbook-entry` enforces the four-section LOGBOOK shape. `themes/methodology-infographic.yaml` is the theme-pack spec for a planned state-visualization layer (the ghostdev GUIDE § Visualize state); no wrapper ships in `bin/` for it yet, and the methodology works fully without it.

Two scripts in `bin/` are yours to call directly, not hooks: `python bin/promote-check.py --suite {FEATURE}` runs the six Rule 19 promotion pre-conditions and exits 0/1/2, and `bin/branch-reaper.{sh,ps1}` lists agent branches by proof class (report-only; `--reap` deletes only branches with zero commits ahead, via `git branch -d`).

To activate the harness: rename `.claude/settings.example.json` → `.claude/settings.json`.

## What goes where

| Question | File |
|---|---|
| "What milestone are we on?" | [docs/CONTEXT.md](docs/CONTEXT.md) |
| "What am I doing right now?" | [docs/TODO.md](docs/TODO.md) |
| "What's deferred?" | [docs/BACKLOG.md](docs/BACKLOG.md) |
| "What happened last session?" | [docs/LOGBOOK.md](docs/LOGBOOK.md) |
| "How does system X work?" | `docs/reference/x.md` |
| "How might we build feature Y?" | `docs/research/y.md` |
| "What's the active feature tracker?" | `docs/{FEATURE}-IMPL.md` |
| "Why did we choose X over Y?" | [docs/CONTEXT.md](docs/CONTEXT.md) → Architecture Decisions table |

## Conventions

- **Mermaid diagrams use dark theme** (Rule 5):
  ` ```mermaid` then `---`, `config:`, `  theme: dark`, `---`.
- **File path links** use relative paths: `[file.ext:42](src/file.ext#L42)`.
- **Commit taxonomy is closed-set** (Rule 15): `feat`, `polish`, `fix`, `refactor`, `docs`, `test`.
- **A box is ticked with its evidence** (Rule 22): `- [x] FEAT.1.1 … — evidence: <test name | command → exit 0 | path>`. A bare `[x]` is a claim, not a record.
- **Commit at every checkpoint** (Rule 20): per source-changing box, not per phase.

For everything else, see [docs/DOCS-PROTOCOL.md](docs/DOCS-PROTOCOL.md).
