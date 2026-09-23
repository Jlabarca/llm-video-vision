---
name: clarify-impl
description: Generate Spec Kit-style clarifying questions for an in-flight FEATURE-IMPL.md before phase 1 starts. Use this when an IMPL doc has been drafted but the operator hasn't filled in the Open Questions section, or when an IMPL is about to flip a phase 1 checkbox to in-progress and ambiguity is suspected. Reads the IMPL header, surfaces ≤3 ambiguity-targeted questions, returns them for the operator to resolve. Per docs/DOCS-PROTOCOL.md Rule 13.
---

# clarify-impl

Forces the Spec Kit "clarify" ceremony onto a FEATURE-IMPL.md before phase 1 work begins. Catches under-specified IMPLs early, before code starts.

## When this fires

- Operator runs `/clarify-impl FEATURE` (where `FEATURE` matches a `docs/{FEATURE}-IMPL.md` filename stem).
- Operator runs `/clarify-impl --hard FEATURE` — the **adversarial** mode: a 7-question design-tree walk instead of the ≤3 soft pass. Use before committing to a wide-open or high-blast-radius IMPL (the Pocock `/grill-me` adaptation). See [§ --hard mode](#--hard-mode-adversarial-design-tree-walk).
- Auto-trigger is also acceptable when an `## Open Questions` section is missing from a freshly-drafted IMPL doc and the next user prompt mentions starting phase 1 work.

## Procedure

1. **Locate the IMPL.** Glob `**/*-IMPL.md` recursively from the workspace root, excluding `node_modules/`, `bin/`, `obj/`, `.git/`, and `**/impl/planned/` (Rule 10 overflow). Match the user-supplied `FEATURE` name (case-insensitive) against the filename stem. Common roots: `docs/`. If a project uses submodules or sister repos, the operator can pass an explicit path. If ambiguous, ask which one.
2. **Read the IMPL header.** Specifically: title block, AI Continuation Prompt, Architecture, Current State, Implementation Status table, Checklist phase 1.
3. **Check for an existing `## Open Questions` section.**
   - If present and resolved (no `**Resolution:**` lines blank): report "already clarified" and exit.
   - If present but unresolved: surface the open ones for resolution.
   - If absent: proceed to generate.
4. **Generate ≤3 clarifying questions** targeting ambiguity in the IMPL. Look specifically for:
   - **Scope ambiguity** — phases reference systems or files that don't exist or aren't named precisely.
   - **Decision gaps** — IMPL asserts a choice without naming the alternative or rationale.
   - **Source-audit gaps** — IMPL cites research/reference docs that may not exist (`Glob` to verify).
   - **Test gates** — `What Needs Testing` references behavior that isn't observable from the IMPL's surface.
   - **Dependency assumptions** — phase N assumes phase N-1 ships specific behavior that isn't enumerated.
5. **Return as a structured patch** the operator can paste under `## Open Questions`:

   ```markdown
   ## Open Questions

   > Spec Kit-style clarify step. ≤3 items. Mark resolved or accept default with rationale before P1 starts.

   1. **Q:** {question}
      **Resolution:** ___ (operator fills in)
   2. ...
   ```

6. **Do not edit the IMPL file directly** — return the markdown block for the operator to paste. Editing without the operator's review violates Rule 14 (architect mode).

## --hard mode (adversarial design-tree walk)

`/clarify-impl --hard FEATURE` swaps the soft ≤3 pass for an adversarial walk — the Pocock `/grill-me` adaptation. **Same single-shot, read-only mechanism** (no multi-turn loop, no new subagent); only the framing and the cap change.

What changes vs. default:

- **Cap 7, not 3** (override `GHOSTDEV_CLARIFY_HARD_CAP=N`). Don't pad to 7 — stop when ambiguity is genuinely exhausted. It's a cap, not a quota.
- **Adversarial framing.** Walk every branch of the design tree. For each phase and each asserted decision, ask the question that would *break* it: "what if the opposite is true?", "what unnamed dependency does this assume?", "which failure mode is unhandled?", "what invariant is stated nowhere?".
- **Targets, in priority order:** (1) **decision gaps** — an asserted choice with no named alternative or reversal cost; (2) **cross-phase dependency assumptions** — phase N silently needs phase N-1 behavior X that no checkbox produces; (3) **integration seams / failure modes** the surface doesn't reach; (4) **unstated invariants**; then the four default targets (scope, source-audit, test-gate, dependency).

**Termination:** the 7-cap (or `GHOSTDEV_CLARIFY_HARD_CAP`) OR genuine exhaustion, whichever comes first. Single-shot — it does not re-invoke itself. Every question stays a real fork the operator must resolve, never rhetorical.

## Constraints

- **Cap of 3 (default); 7 under `--hard`.** In default mode, >3 means the IMPL isn't ready — recommend more research first. `--hard` is the deliberate exception: it opts into the 7-question adversarial walk for wide-open or high-blast-radius IMPLs (override the cap via `GHOSTDEV_CLARIFY_HARD_CAP`). The default ≤3 behavior is unchanged when `--hard` is absent.
- **Don't generate questions you could answer yourself.** Targets ambiguity, not test coverage. If the IMPL is clear, return "no clarifications needed" and exit.
- **Live shell injection allowed** for source-audit checks: `` !`Glob docs/research/{cited-doc}.md` `` to verify cited references exist.
- **Read-only.** This skill never edits files. It returns a block.

## Example output (good)

```markdown
## Open Questions

> Spec Kit-style clarify step. ≤3 items. Mark resolved or accept default with rationale before P1 starts.

1. **Q:** Phase P4 references `docs/research/hooks-policy.md` as design output. Should this doc be created during P4.1 or carved from existing notes?
   **Resolution:** ___
2. **Q:** Test-suite-green gate — for IMPLs adding new SDK primitives, does "tests-green" mean unit-only, or does the integration suite need to pass?
   **Resolution:** ___
3. **Q:** Phase IDs reference `WORKER-POOL.2.3` but no such phase exists in the Implementation Status table. Add the phase or remove the references?
   **Resolution:** ___
```

## Example output (skip)

```
No clarifications needed. The IMPL header, Architecture, and phase 1 checklist are unambiguous.
```

## Example output (--hard)

For a deliberately under-specified IMPL, `--hard` walks deeper — decision gaps and cross-phase dependencies first:

```markdown
## Open Questions

> Adversarial clarify (--hard). Up to 7 items — answer each before P1.

1. **Q:** P2 says "store findings in the ledger" but names no identity key — two re-worded findings would collide or duplicate. What is the finding key, and is it stable across re-wording?
   **Resolution:** ___
2. **Q:** P3 (dispatch) silently assumes P2 emits a tractable `where` field, but nothing in P2's checklist produces it. Hidden cross-phase dependency, or does P3 derive it?
   **Resolution:** ___
3. **Q:** The design asserts "human-gated" but no checkbox creates the gate surface. What is the actuator, and what is its default — armed or dark?
   **Resolution:** ___
4. **Q:** "Re-validate on approval" — if re-validation still fails, does it loop, escalate, or silently drop? The failure branch is unspecified.
   **Resolution:** ___
5. **Q:** Phase ordering assumes the rail is append-only; if two producers write concurrently, is ordering guaranteed, or is a last-writer-wins race possible?
   **Resolution:** ___
```

## Agent execution

Project-level skills under `.claude/skills/` are not exposed via the agent's Skill tool surface as of 2026-05. When an agent session encounters `/clarify-impl FEATURE` or decides this skill applies, it executes the procedure **inline**: Read this SKILL.md, glob for the IMPL, Read the IMPL header sections, generate the questions, return the markdown block as a chat message for the operator to paste. No Skill-tool dispatch.

If `Updated:` on the IMPL is older than the methodology adoption date for the project (e.g., older than the date Rule 13 was added — track this per-project), the IMPL may predate the clarify ceremony. Default behavior: emit a one-liner — `Legacy IMPL (Updated: {date}, pre-Rule-13 era). Skip clarify? (y/n)` — and only generate questions if the operator confirms. Avoids ceremonial output on long-cooked IMPLs.

## Why this exists

Spec Kit's `/speckit.clarify` slash command is the single most-cited "would have caught the bug earlier" pattern in field studies. This skill closes that gap when the operator adopts ghostdev without adopting Spec Kit itself. See [DOCS-PROTOCOL.md Rule 13](../../../docs/DOCS-PROTOCOL.md).
