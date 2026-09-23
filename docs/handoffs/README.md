# docs/handoffs/ — ephemeral session resumes

Written by the [`/handoff`](../../.claude/skills/handoff/SKILL.md) skill. **Not durable state.**

- **Ephemeral.** Everything here except this README and `.gitkeep` is gitignored. Handoffs are scratch, not artifacts.
- **Topic-keyed.** One file per IMPL slug — `docs/handoffs/<FEATURE>.md`. Re-running `/handoff` on the same feature **overwrites** it. No timestamps in the name, no history.
- **Cold-start optimized.** Each file front-loads read-order + "you are here" + the exact resume prompt to paste into a fresh session, so the next session resumes at full fidelity from a few hundred tokens.

## Why not just use the LOGBOOK?

[`LOGBOOK.md`](../LOGBOOK.md) is the durable, append-only audit trail (what happened, Rule 14). A handoff is the disposable live-resume (what to do next, right now). Different jobs, different lifetimes — don't conflate them. The handoff's "In flight (NOT yet in LOGBOOK)" section is the part nothing else captures.

## Lifecycle

```
long session nears the smart-zone limit (~120k tokens)
  → /handoff <FEATURE>        (compress this session → docs/handoffs/<FEATURE>.md)
  → /clear  (or close the session)
  → fresh session: paste the resume prompt
  → /run-impl <FEATURE>       (drive from the first unchecked box)
```

A handoff older than a few days is suspect — prefer `/audit-impl <FEATURE>` (a fresh drift check) over trusting stale scratch.
