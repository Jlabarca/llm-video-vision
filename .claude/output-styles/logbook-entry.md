---
name: logbook-entry
description: Strict four-section LOGBOOK.md entry format. Use when writing or editing entries in any project's LOGBOOK.md so cross-session entries stay consistent in shape.
---

# Output style — logbook-entry

When this style is active, every LOGBOOK.md entry MUST follow exactly this shape:

```markdown
## YYYY-MM-DD — One-line title (≤80 chars)

**Accomplished:**

- Bullet 1 — what shipped, with file links and commit hashes where relevant
- Bullet 2
- ...

**Decisions:**

- **X over Y** — one-line rationale, ideally referencing prior incidents or constraints
- **Z** — why
- ...

**Tests:** (optional; omit if no test changes this session)

- What was added / updated / skipped, with rationale if skipped

**Blockers:**

- Anything stopping the next phase. Write `None.` if there are none — don't leave blank.

**Next:**

- Concrete next action. Specific phase ID if applicable (e.g., `AUTH.4.5`).

---
```

## Rules

1. **Newest entry on top** — insert directly after the LOGBOOK header block, before the most recent existing entry.
2. **Never edit prior entries.** Append-only. Corrections go in a new `## YYYY-MM-DD — Correction to NN` entry.
3. **Decisions section is the gold.** *Why X over Y because Z* shape is preferred. Capture rationale that survives compaction.
4. **Live shell injection encouraged for Accomplishments** — `git log --since="{prev-date}" --oneline` produces real candidates, not vibes.
5. **Tests section is optional but informative** when present. Leave it out if no tests changed; don't pad.
6. **Blockers must say `None.` if none** — silence is ambiguous.
7. **Title ≤80 chars** — entries are scanned via README/grep; long titles wrap and degrade scannability.

## Anti-patterns

- ❌ Entries without a Decisions section. Even bug-fix sessions usually had one micro-decision.
- ❌ Bullets that read "did some work on X." Be specific or skip the bullet.
- ❌ Backwards-looking commentary ("we should have caught this earlier"). The LOGBOOK is forward-facing — *what was decided, what's next.*
- ❌ Re-stating the diff. The diff is in git; the LOGBOOK captures *why*.
- ❌ Multiple `## ` headings per entry. One date, one title, one entry.

## Why this style exists

LOGBOOK rationale density is the highest-leverage documentation pattern in single-operator, agent-assisted development — and one of the easiest to lose to drift. A session that writes only "Accomplishments" loses the *why X over Y* signal that survives compaction.

This output style codifies the four-section template so it survives both LLM forgetfulness and operator fatigue. Used in conjunction with the `/logbook-append` skill ([template/.claude/skills/logbook-append/SKILL.md](../skills/logbook-append/SKILL.md)).
