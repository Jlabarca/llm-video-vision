---
name: audit-impl
description: Read-only drift audit of a FEATURE-IMPL.md against the actual codebase. Use this when an IMPL's "Current State" date is more than 7 days old, when an IMPL is about to be promoted (pre-flight check), or when picking up a feature after a long pause. Dispatches to a Plan subagent (read-only, isolated context) so the heavy file reads don't pollute the main session. Returns a <300-word punch list of drift items.
---

# audit-impl

Drift audit between an IMPL doc's "Current State (date)" claims and the actual repo. Reports a punch list — no edits.

## When this fires

- User runs `/audit-impl FEATURE` (case-insensitive match).
- Recommended pre-flight before `/promote-impl`.
- Recommended after >7 days since the IMPL's `Updated:` line.

## Procedure

This skill is **read-only** and runs in a forked subagent context (`Plan` agent) so the file reads don't pollute the main session.

1. **Dispatch a Plan subagent** with the brief below. The subagent reads the IMPL fully + scans every file in the IMPL's "Key Files Reference" table + greps for the IMPL's phase IDs across the repo + checks `git log` for the IMPL file.
2. **Subagent prompt skeleton:**

   ```
   Read docs/{FEATURE}-IMPL.md fully.

   For each file in its "Key Files Reference" table:
   - Verify the file exists at the cited path
   - If line numbers are cited, verify the line still contains the cited symbol
   - Note files that have changed materially since the IMPL's Updated: date

   For each unchecked checkbox in the IMPL:
   - Grep the codebase for the phase ID (e.g., "AUTH.2.1") in commit messages
   - If found in commits but unchecked in IMPL → drift item

   For each cited research/reference doc:
   - Verify the doc exists at the cited path

   Report a punch list under 300 words:
   - Drift items (concrete: "X claims Y but Z")
   - Stale references (links that 404 inside the repo)
   - Apparent inconsistencies between checklist and git history
   - Tests claimed in "What Needs Testing" but not present in tests/ folders

   Do not propose fixes. Do not edit. Just report.
   ```

3. **Return the subagent's report verbatim** plus a single-line summary count: `N drift items, M stale references, K test gaps.`

## Output shape

```
Audit: AUTH-IMPL (Updated: 2026-04-30, 6 days ago)

Drift items (3):
- AUTH.1.4 unchecked but commit a1b2c3d "Disable retry policy" appears to satisfy it.
- "Key Files Reference" cites src/services/auth/SessionStore.ext:55 — file no longer
  exists post-1.3 swap (deleted in commit ef45678).
- Implementation Status table says P3 "Plan-only" but P3.1 has commit history.

Stale references (1):
- Cites docs/research/oauth-flow-audit.md §3.1 — section anchor not present in current
  audit doc revision (audit was rewritten 2026-05-02).

Test gaps (2):
- TEST.4 (token refresh ROI) claimed in IMPL — no corresponding test file in tests/.
- TEST.6 (e2e) claimed — present but skipped via [Ignore] attribute.

Summary: 3 drift, 1 stale ref, 2 test gaps.
```

## Constraints

- **Read-only.** No edits, no file writes, no git mutations. The subagent's tool grant must exclude `Edit`, `Write`, `Bash(git commit:*)`, etc.
- **Subagent fork required when supported.** This is the load-bearing context-preservation move. Heavy file reads stay in the subagent; only the report comes back.
- **Cap report at ~300 words.** Brevity is the feature. Long audits get ignored.
- **No fixes proposed.** This skill detects drift; the operator decides what to do.
- **Don't audit phases the IMPL itself marks `STATUS: PLAN-ONLY`.** Plan-only IMPLs are intentionally unimplemented; auditing them produces noise.

## Tool allowlist (advisory, when supported)

`Read, Grep, Glob, Bash(git log:*), Bash(git diff:*), Bash(git status)`. Never `Edit`, `Write`, mutating git.

## Agent execution

Project-level skills under `.claude/skills/` are not exposed via the agent's Skill tool surface as of 2026-05, but `audit-impl` works **better** that way: the load-bearing primitive is the Agent tool with `subagent_type=Plan` (read-only, isolated context). When invoked inline, the agent reads this SKILL.md, then dispatches a Plan subagent with the prompt skeleton above. Only the <300-word report comes back to the main session — context-preserving by construction.

## Why this exists

The "Updated: <date>" line on IMPL docs decays. A periodic audit pass surfaces drift cheaply — and forks-into-subagent so the audit doesn't burn the main session's context window. This is the published anti-context-rot move.
