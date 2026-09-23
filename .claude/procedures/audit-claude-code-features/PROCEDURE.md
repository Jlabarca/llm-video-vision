# Procedure: Audit Claude Code Features & Methodology Leverage

> Periodic sweep of Claude Code capabilities against ghostdev template surface.  
> Identifies new features, gaps, and adoption-time improvements.
>
> **Trigger**: Quarterly (calendar), or 48h after major Claude Code release notes, or on-demand.  
> **Duration**: ~2–3 hours.  
> **Output**: Pull request with research docs + template updates, or summary memo if no changes needed.

---

## Should I Run This Now?

✅ Run this if:
- It's been 3 months since the last audit
- Claude Code released major feature updates (check https://claude.com/changelog, `claude.ai/code` help modal, or `/help` output)
- An adopter files an issue: "I didn't know I could use [feature]"
- You're about to cut a new ghostdev release (v0.1, v0.2, etc.)

❌ Skip if:
- You ran an audit in the past 4 weeks AND no new Claude Code releases
- You're mid-implementation of P1–P3 phases (this is a cross-cutting meta-task)

---

## Steps

### 1. **Gather Claude Code Surface** (30–45 min)

Read or run the following to capture the current state:

```powershell
# Option A: Interactive, in Claude Code REPL
/help

# Outputs: list of available commands, skills, hooks, etc.
# Copy the full output → save to claude-code-surface.txt
```

Also check:
- [ ] `https://claude.com/changelog` (past 3 months) — screenshot new features
- [ ] `/help` modal in Claude Code (desktop or web) — any new sections?
- [ ] MCP ecosystem updates (https://modelcontextprotocol.io/implementations) — new servers?
- [ ] Anthropic SDK changelog (https://github.com/anthropic-ai/anthropic-sdk-python/releases)

**Capture as markdown**: Create a scratch file `audit-surface.md` with sections:
```markdown
# Claude Code Surface — {date}

## Commands
[paste from /help output]

## Skills
[list + one-line purpose]

## Hooks
[list + trigger description]

## MCP Servers Available
[list + status]

## SDK Features (if relevant)
[notable new additions since last audit]
```

### 2. **Cross-Reference Against Template** (30–40 min)

Open [`ghostdev/template/GUIDE.md`](../../../../template/GUIDE.md) and [`template/CLAUDE.md`](../../../../template/CLAUDE.md).

For **each feature** in your audit surface:
- [ ] Is it mentioned in template docs?
- [ ] If yes: is the guidance current, actionable, and complete?
- [ ] If no: should it be? (filter by "would an adopter benefit?")

Create a **gap list** in `audit-gaps.md`:

```markdown
# Gaps: Features Not in Template

| Feature | Mention? | Should Be? | Why | Priority |
|---|---|---|---|---|
| `/goal` | No | Yes | Phase signaling, better planning | P3 |
| `/schedule` | No | Yes | Async orchestration for large projects | P2 |
| ... | | | | |

# Updates Needed: Current Guidance Is Stale

| Section | Feature | Issue | Fix |
|---|---|---|---|
| GUIDE.md § Async | `/loop` | Only mentions recurring tasks; missing interval tuning | Add timing guidance |
| ... | | | |
```

### 3. **Research New Features in Context** (20–30 min)

For the top 3–5 gaps marked **P2 or P3**:

Run `/goal` with an explicit scope:
```
/goal "Research how [feature] would improve ghostdev methodology for adopters. 
Consider: (a) workflow integration, (b) cost impact, (c) documentation burden. 
Return a 200-word summary with a yes/no recommendation and priority level."
```

Or ask directly:
```
I'm auditing Claude Code features for ghostdev template coverage.
Gap: [feature] is not documented. For an adopter project, would [feature] 
help with [workflow]? What's the barrier to adoption if we don't doc it?
```

**Capture**: Save summaries → these feed the research doc.

### 4. **Update Research Doc** (20–30 min)

Edit [`ghostdev/docs/research/claude-code-feature-audit.md`](../../../../docs/research/claude-code-feature-audit.md):

- [ ] Update "Last audit" date at top
- [ ] Add any newly discovered features to "Known Underutilized Features" (if not already listed)
- [ ] Update the priority/effort matrix with new data
- [ ] Append "Session Notes" section with what you found

Example:
```markdown
## Session Notes — 2026-08-29 Audit

- Discovered `/goal` framing is now available (was missing in 2026-05 audit)
- `/schedule` added repeat patterns support (interval tuning) → update P3 docs
- MCP: Notion integration is now stable (was beta) → P4 → P3.5
- Prompt caching hit rates improved in SDK v1.8 → reduces implementation cost
```

### 5. **PR or Summary** (30 min)

**Option A: Create a PR** (if you found 3+ substantive gaps or update needs)

- Commit updated research doc
- Commit any template doc updates (e.g., GUIDE.md § Async additions)
- Commit `.claude/procedures/this-procedure/PROCEDURE.md` update (refresh dates, notes)
- PR title: `docs(methodology): Q3 2026 Claude Code feature audit`
- PR summary: Paste relevant sections from gap list + priority matrix

**Option B: Memo** (if no gaps or only cosmetic issues)

Post in LOGBOOK.md:
```markdown
### Audit: Claude Code Features (2026-08-29)

Surface is current. No new P2–P3 features missed. Minor polish to `/schedule` docs recommended (P3, 30 min).
Next audit: ~2026-11-29.
```

### 6. **Schedule Next Audit** (5 min)

After this audit, schedule the next:

```powershell
/schedule "at 5pm on Dec 1, 2026, run the Claude Code feature audit procedure"
```

Or set a calendar reminder + BACKLOG item.

---

## Verdict

After steps 1–4, decide:

**✅ DO**: Update template docs (estimated effort, priority)
- Commit + PR
- Add tasks to methodology IMPL tracker
- Log in LOGBOOK

**⏸️ DEFER**: Found gaps but lower priority than current work
- Add to `docs/BACKLOG.md` with P-level
- Schedule follow-up audit in 6 weeks

**⏭️ SKIP**: No changes needed, surface is current
- Quick memo in LOGBOOK
- Schedule next audit (usually +3 months)

---

## Follow-Up Actions

If you found items to update:

1. **Small fixes** (30–60 min): Do immediately, commit to main
2. **Medium docs** (1–3 hrs): File as task in GHOSTDEV-METHOD-IMPL.md, tag with `P3-quick-wins`
3. **Large features** (3+ hrs): Add to BACKLOG.md, prioritize in next planning cycle

---

## Resources

- Claude Code `/help` command
- [ghostdev/docs/research/claude-code-feature-audit.md](../../../../docs/research/claude-code-feature-audit.md) — the base research doc
- [ghostdev/template/GUIDE.md](../../../../template/GUIDE.md) — what adopters see
- [claude.com/changelog](https://claude.com/changelog)
- [MCP Implementations](https://modelcontextprotocol.io/implementations)
