---
name: logbook-append
description: Guided LOGBOOK.md entry creation. Pre-fills today's date, scaffolds the four-section template (Accomplished / Decisions / Blockers / Next), and shell-injects git log since the previous LOGBOOK entry as candidate accomplishments. Use this when ending a session that touched code or docs, or when explicitly asked to append a logbook entry.
---

# logbook-append

Guided LOGBOOK entry. Reduces friction so logbook entries actually get written; enforces the four-section structure so they stay scannable.

## When this fires

- User runs `/logbook-append`.
- Auto-trigger on session end if (a) code or docs changed and (b) no LOGBOOK entry was appended in this session — fires from the `audit-logbook` Stop hook.

## Procedure

1. **Locate LOGBOOK.md.**
   - Default: `docs/LOGBOOK.md`.
   - If multiple candidates (subrepo with its own LOGBOOK), prefer the one whose containing directory has the most recent commit.
2. **Find the previous entry's date.** `Grep -m 1 "^## " docs/LOGBOOK.md` for the latest `## YYYY-MM-DD — {title}` heading.
3. **Compose the template** with live-injected accomplishments candidates:

   ```markdown
   ## {today} — {one-line title — operator fills}

   **Accomplished:**
   {Live-inject candidates from `git log --since="{prev-date}" --oneline` and `git diff --stat {prev-date}..HEAD`. Operator edits/trims.}

   **Decisions:**
   {Operator fills. The "X over Y because Z" shape is preferred.}

   **Tests:** (optional)
   {Whether tests were added/updated/skipped, with rationale if skipped.}

   **Blockers:**
   {Anything stopping the next phase. None is fine — write "None.".}

   **Next:**
   {Concrete next action. Specific phase ID if applicable.}

   ---
   ```

4. **Insert at the top of the LOGBOOK** (after the header block, before the most recent `## ` entry). Append-only rule from DOCS-PROTOCOL.md Rule 2 means newest-on-top, never edit prior entries.
5. **Show the proposed entry** to the operator. Wait for "apply" / "edit" / "skip."
6. **Apply** via `Edit` tool. Don't commit.

## Live-injection patterns (use these in the template)

```markdown
{from `!`git log --since="{prev-date}" --oneline`}
{from `!`git diff --stat {prev-date}..HEAD`}
{from `!`git log --since="{prev-date}" --pretty=format:"- %s (%h)"`}
```

## Output shape (proposal)

```markdown
Proposed LOGBOOK.md entry (insert at top of session list):

## 2026-05-06 — AUTH P1+P2 ship + Rule 13 Open Questions added

**Accomplished:**

Candidates from git log since 2026-05-03:
- Add Open Questions section to AUTH-IMPL (a1b2c3d)
- Implement login + logout endpoints (e4f5g6h)
- 5 skills bootstrapped under .claude/skills/ (b3a4c5e)

[Operator: trim and rewrite as appropriate.]

**Decisions:**

[Operator fills. Examples to consider:
- Why JWT over session cookies? (Stateless backend constraint)
- Why bcrypt cost factor 12? (P3-grade hardware target)
]

**Tests:** [Operator fills.]
**Blockers:** [Operator fills.]
**Next:** [Operator fills — likely AUTH.3.1 or post-merge cleanup.]

---

Apply? (yes / edit / skip)
```

## Constraints

- **Append-only.** Never edit prior entries. If a correction is needed, append a `## YYYY-MM-DD — Correction to NN` entry instead.
- **Decisions section is the gold.** Don't auto-fill — the operator's *why X over Y* rationale is what survives compaction. Live-inject is for accomplishments only.
- **Four sections minimum** — Accomplished, Decisions, Blockers, Next. Tests is optional. Empty Decisions is suspect (a session with zero decisions probably had nothing notable; skip the entry instead).
- **Today's date.** Use `Bash(date +%Y-%m-%d)` if uncertain — never guess.

## Tool allowlist (advisory)

`Read, Edit, Grep, Glob, Bash(git log:*), Bash(git diff:*), Bash(date:*)`. No commit, no push.

## Agent execution

Project-level skills under `.claude/skills/` are not exposed via the agent's Skill tool surface as of 2026-05. When invoked inline, the agent Reads this SKILL.md, runs the `git log` injection, composes the template as a chat message, **waits for operator approval**, then applies via the Edit tool. The four-section shape is also enforced by the `logbook-entry` output style — the skill scaffolds, the style polices.

## Why this exists

LOGBOOK rationale density is the single highest-leverage documentation pattern — and one of the easiest to lose to friction. A guided template that pre-fills the boring parts (date, accomplishments candidates) keeps the entry-cost low so it actually happens. The Decisions section stays manual because that's where the value lives.

See [DOCS-PROTOCOL.md Rule 2](../../../docs/DOCS-PROTOCOL.md) (LOGBOOK rules).
