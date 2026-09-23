---
name: tdd
description: Strict Red → Green → Refactor. Write one failing test that pins the next behavior, the minimal code to pass it, then a refactor pass with the test green. Use when adding or changing behavior in code (not docs/config) and you want tests as back-pressure against untested slop. Paired with the tdd-test-gate PreToolUse hook, which warns (or blocks) a Write/Edit to an implementation file when no new test symbol was added in the session. Manual invocation only.
---

# tdd

Pocock's back-pressure pattern: the LLM is a fast junior who will happily emit plausible, untested code. A failing test written *first* is the cheapest forcing function for correctness — it pins the intended behavior before the implementation exists, so "it compiles" can't masquerade as "it works."

This skill is the *workflow*; `bin/tdd-test-gate.{ps1,sh}` is the *enforcement*. The skill tells you the loop; the hook makes skipping it visible (warn) or impossible (block).

## When this fires

- Operator runs `/tdd [target]` before adding/changing a unit of behavior.
- Also surfaces passively: the `tdd-test-gate` PreToolUse hook prints `[tdd-gate] …` to stderr when you Write/Edit an implementation file with no new test in the session diff. That nudge *is* the skill asking you to go Red first.
- **Manual only** for the skill. The hook is automatic but warn-by-default.

## The loop

1. **Red.** Write exactly one failing test that names the next behavior. Run it; confirm it fails for the *right* reason (asserting the behavior, not a typo/import error). One test, one behavior — resist batching.
2. **Green.** Write the *minimal* implementation that makes it pass. No speculative generality, no adjacent features. Run the test; confirm green.
3. **Refactor.** With the test green, clean up — names, duplication, shallow→deep module shape — re-running the test after each change. The green test is the safety net that makes refactoring fearless.
4. Repeat for the next behavior. Commit per phase (Rule 15 `test(...)`/`feat(...)`), not per micro-step.

## How the hook enforces it

`tdd-test-gate` runs on every `Edit|Write` (PreToolUse):

- **Classifies the target.** Acts only on implementation files (`.cs/.ts/.tsx/.js/.jsx/.py`) that are **not** test paths (`tests?/`, `__tests__/`, `*.test.*`, `*.spec.*`, `*_test.*`). Docs, config, shell hooks, and test files themselves are no-ops.
- **Gated on active work.** Only fires while an `*-IMPL.md` has an open `- [ ]` checkbox — it won't nag on a repo with no in-flight phase.
- **Scans the session diff** (`git diff HEAD` + staged, or a base set via `GHOSTDEV_TDD_BASE_REF`) for a **new test symbol** on an added line: `it(`, `describe(`, `test(`, `[Test]`, `[Fact]`, `def test_`.
- **Verdict:** symbol present → allow (exit 0). Absent → **warn** (exit 1, stderr, the tool still proceeds) by default; **block** (exit 2, tool refused) when escalated.

Exit contract (also pinned by `bin/fixtures/tdd-gate/README.md`, which the `.ps1` and `.sh` ports are tested against): `0` allow · `1` warn · `2` block.

## Escalation & escape hatch

- **Escalate to block** on a critical path: set `GHOSTDEV_HOOK_BLOCK=1` (env) or add `> block-mode: true` to the active IMPL header. Then a no-test impl Write is *refused*, not just flagged.
- **Stricter "require red"** is a documented future toggle (`GHOSTDEV_TDD_REQUIRE_RED=1`) — run the test and require an actual failing result, not just a symbol. Not implemented in v1.
- **Legitimately test-free change?** (a pure rename, a generated file, a config-shaped `.ts`.) The default is warn — just proceed; the stderr line is a passive signal, not a wall. If it's noise on a whole class of edits, narrow the matcher in `.claude/settings.json` rather than fighting it per-edit.

## Constraints

- **Warn-by-default.** The gate never blocks unless explicitly escalated. It is a signal, not a gate, until you choose otherwise — consistent with the warn-first hook policy.
- **One behavior per Red.** The discipline is the value; batching tests defeats the "minimal code to green" step.
- **Tests are the unit of trust, not the goal.** Green tests enable refactoring and pin behavior — don't write tests you wouldn't believe.
- **The skill edits nothing on its own.** `/tdd` guides; you write the test and the code. The only automated actor is the hook, and it only reads + emits a verdict.

## Agent execution

When a session encounters `/tdd …`, read this SKILL.md and run the loop inline: Red (one failing test) → Green (minimal impl) → Refactor (green-guarded cleanup). The `tdd-test-gate` hook fires automatically on impl-file writes; treat its `[tdd-gate]` stderr line as the cue to go Red first. No Skill-tool dispatch.

## Companion skills

- `/qa-pass` — end-of-phase audit; verifies tests were *touched* in the phase. `/tdd` makes that pass trivially by construction.
- `/run-impl` — drives phases; impl-file writes during a run trip the same gate.
- `/handoff` — if a Red/Green cycle spans a context boundary, hand off mid-loop with the failing test named in the resume prompt.
