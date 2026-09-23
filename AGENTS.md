# AGENTS.md

> This file is the entry point for AI coding agents that follow the [AGENTS.md convention](https://agents.md) (Codex, Cursor, Aider, Copilot, JetBrains, Devin, Jules, Junie, and others).
>
> **Primary instructions live in [CLAUDE.md](CLAUDE.md)** (which links to [docs/CONTEXT.md](docs/CONTEXT.md) for current state and decisions). This file is a pointer — keep it thin so tools that look here don't read stale duplicates.

## How to use this repository as an agent

1. Read [CLAUDE.md](CLAUDE.md) for project overview, stack, and instructions.
2. Read [docs/CONTEXT.md](docs/CONTEXT.md) for current state, locked architecture decisions (with dates and rationale), milestones, and the active sprint.
3. Read [docs/DOCS-PROTOCOL.md](docs/DOCS-PROTOCOL.md) for the documentation methodology this project follows.
4. For any feature build that spans multiple sessions, the per-feature tracker lives at `docs/{FEATURE}-IMPL.md` (active) or `docs/impl/{FEATURE}-IMPL.md` (promoted). Look there before touching code in the feature's area.

## Methodology

This project follows [ghostdev](https://github.com/waremoto/ghostdev) — see [docs/DOCS-PROTOCOL.md](docs/DOCS-PROTOCOL.md) for the 15 rules. Key invariants:

- **CONTEXT.md is the single source of truth** for state and decisions. Update it first when state changes.
- **LOGBOOK.md is append-only.** Never edit prior entries. Four sections per entry: Accomplished / Decisions / Blockers / Next.
- **2+ source-content files in a phase ⇒ paste a `## Plan` section** in the relevant FEATURE-IMPL before editing (Rule 14).
- **Commit taxonomy is closed-set** (Rule 15): `feat`, `polish`, `fix`, `refactor`, `docs`, `test`. No `chore` / `style` / `ci` / `perf` / `build` / `revert`.

If you cannot tell which document to update for a change, default to: `CONTEXT.md` + `TODO.md` + `LOGBOOK.md`. The reference doc updates only when the system's *description* changed.
