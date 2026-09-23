#!/usr/bin/env python3
"""promote-check — the six /promote-impl pre-conditions as one exit-coded command.

DOCS-PROTOCOL Rule 19 says promotion APPLIES without asking. That is only safe because the
pre-conditions are checked mechanically first; a skill that re-derives them by hand each time
will eventually skip one. This is that check, standalone and stdlib-only, so an adopter gets
the gate and the no-prompt behaviour together. (Shipping the rule without its checker is the
one combination that is worse than today: all of the speed, none of the pre-conditions.)

Five of the six are machine facts. The sixth — is `reference/{slug}.md` a TRUE description of
the system? — is not machine-checkable at all, so it gets a SHAPE proxy (the Rule 12 sections,
no bare `<TBD>`, at least one `file:line` cite) plus a `note` line that never gates. The note
is the honest residue: a person still has to read it.

    python bin/promote-check.py --suite FEATURE [--repo .]

    exit 0  promotable
    exit 1  promotable with warnings (advisory: dirty docs/, shape problems, no rail)
    exit 2  NOT promotable (unchecked boxes, open bugs, no reference doc, claimed tier red)

A project that keeps no run rail (`.runs/*.jsonl`) still gets every other check; the verify
pre-condition degrades to a warning rather than a block, because a missing rail is an absent
*record*, not evidence of a failure. If your project keeps one, the block returns automatically.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REFERENCE_SECTIONS = ("Overview", "Architecture", "Key Files", "API Surface",
                      "Usage Guide", "Caveats", "Related Docs")
VERIFY_KIND = "loop.verify"

# ── tiny helpers ────────────────────────────────────────────────────────────────


def md_section(text, heading):
    """Body of `## {heading}` up to the next `## ` heading ('' when absent)."""
    m = re.search(r"(?m)^##\s+" + re.escape(heading) + r"\b[^\n]*\n", text)
    if not m:
        return ""
    rest = text[m.end():]
    n = re.search(r"(?m)^##\s", rest)
    return rest[:n.start()] if n else rest


def git_head(repo_root):
    """Full HEAD sha, or None when this is not a git repo."""
    try:
        r = subprocess.run(["git", "-C", str(repo_root), "rev-parse", "HEAD"],
                           capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def open_bugs(known_bugs_section):
    """Headings under Known Bugs that are neither struck (~~) nor carry a fixed/resolved line."""
    heads = list(re.finditer(r"(?m)^###\s+(.+)$", known_bugs_section))
    out = []
    for i, h in enumerate(heads):
        title = h.group(1).strip()
        if "~~" in title:
            continue
        end = heads[i + 1].start() if i + 1 < len(heads) else len(known_bugs_section)
        body = known_bugs_section[h.end():end]
        if re.search(r"(?im)^\s*[*_~]*\s*(fixed|resolved|closed)\b", body) or \
           re.search(r"(?i)\*\*status:?\*\*?:?\s*(fixed|resolved|closed)", body):
            continue
        out.append(title.split(" — ")[0].split(" -- ")[0][:60])
    return out


def reference_shape(ref_text):
    """(missing_sections, has_tbd, has_cite) — the machine proxy for pre-condition 4.

    A BACKTICK-QUOTED `<TBD>` is prose, not a placeholder: without that carve-out a reference
    doc that merely NAMES the marker — listing it among the things that halt a run, say —
    fails its own shape gate.
    """
    missing = [h for h in REFERENCE_SECTIONS
               if not re.search(r"(?im)^##+\s+.*" + re.escape(h), ref_text)]
    has_tbd = bool(re.search(r"(?<!`)<TBD>(?!`)", ref_text))
    has_cite = bool(re.search(r"\.\w{1,6}:\d+\b|#L\d+", ref_text))
    return missing, has_tbd, has_cite

# ── the run rail (optional) ─────────────────────────────────────────────────────


def read_verify(repo_root, suite):
    """Latest `loop.verify` payload for `suite` from `{repo}/.runs/*.jsonl`.

    Returns (payload_or_None, rail_exists). The second value is what separates "this project
    keeps no rail" from "this project keeps one and it has nothing to say about this suite" —
    two facts that must not produce the same verdict.
    """
    runs_dir = Path(repo_root) / ".runs"
    if not runs_dir.is_dir():
        return None, False
    latest = None
    for path in sorted(runs_dir.glob("*.jsonl")):
        try:
            raw_text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for raw in raw_text.splitlines():
            if not raw.strip():
                continue
            try:
                rec = json.loads(raw)
                if rec.get("Kind") != VERIFY_KIND:
                    continue
                payload = json.loads(rec.get("Payload") or "{}")
            except ValueError:
                continue
            if not isinstance(payload, dict):
                continue
            if suite is not None and payload.get("suite") != suite:
                continue
            if latest is None or (payload.get("at") or "") > (latest.get("at") or ""):
                latest = payload
    return latest, True


def verify_verdict(payload, head_commit):
    """(status, detail) for a verify payload vs current HEAD.

    absent -> never verified · red -> fewer passes than tests that actually ran (a SKIP is not
    a failure, but a suite that skipped everything verified nothing and is red) · stale ->
    green at a different commit · pass -> green AND at HEAD.
    """
    if not payload:
        return "absent", "no verify record on the rail -- run the tests"
    # `or 0` on every count rather than `.get(k, 0)`: the rail is arbitrary JSON and an
    # explicit `"total": null` would return None and crash the comparisons below.
    passed = payload.get("passed") or 0
    total = payload.get("total") or 0
    skipped = payload.get("skipped") or 0
    commit = payload.get("commit")
    short = (commit or "?")[:8]
    if not all(isinstance(v, int) for v in (passed, total, skipped)):
        return "red", "verify RED (non-integer counts) @ %s" % short
    executed = max(total - skipped, 0)
    note = ", %d skipped" % skipped if skipped else ""
    # Malformed arithmetic is RED, never quietly rounded into a pass: a payload claiming more
    # skips than tests, or more passes than were run, is not evidence of anything.
    if skipped < 0 or skipped > total or passed > executed:
        return "red", ("verify RED (incoherent: %d passed, %d total, %d skipped) @ %s"
                       % (passed, total, skipped, short))
    if not total or executed <= 0:
        return "red", "verify RED (nothing executed: %d total%s) @ %s" % (total, note, short)
    if passed < executed:
        return "red", "verify RED (%d/%d executed%s) @ %s" % (passed, executed, note, short)
    if commit != head_commit:
        return "stale", ("green but @ %s != HEAD %s -- re-run the tests"
                         % (short, (head_commit or "?")[:8]))
    return "pass", ("green %d/%d executed%s @ HEAD %s"
                    % (passed, executed, note, (head_commit or "?")[:8]))

# ── the six checks ──────────────────────────────────────────────────────────────


def promote_check(repo_root, feature):
    """Rows of (level, text); level in ok|warn|block|note. Pure over the filesystem + rail."""
    repo_root = Path(repo_root)
    rows = []
    docs = repo_root / "docs"
    impl = docs / ("%s-IMPL.md" % feature)

    # 1 -- the tracker exists
    if not impl.exists():
        rows.append(("block", "docs/%s-IMPL.md does not exist" % feature))
        return rows
    text = impl.read_text(encoding="utf-8", errors="replace")
    rows.append(("ok", "%s exists" % impl.name))

    # 2 -- every checklist box ticked
    unchecked = re.findall(r"(?m)^\s*- \[ \]\s*\**([A-Za-z0-9.-]+)", md_section(text, "Checklist"))
    if unchecked:
        rows.append(("block", "%d unchecked box(es): %s%s"
                     % (len(unchecked), ", ".join(unchecked[:6]),
                        " ..." if len(unchecked) > 6 else "")))
    else:
        rows.append(("ok", "all checklist boxes checked"))

    # 3 -- no open Known Bugs
    bugs = open_bugs(md_section(text, "Known Bugs"))
    if bugs:
        rows.append(("block", "%d open Known Bug(s): %s" % (len(bugs), "; ".join(bugs))))
    else:
        rows.append(("ok", "no open Known Bugs"))

    # 4 -- reference doc: existence (fact) + shape (proxy) + content (a note, never a gate)
    slug = feature.lower()
    ref = docs / "reference" / ("%s.md" % slug)
    if not ref.exists():
        rows.append(("block", "docs/reference/%s.md does not exist -- draft it first; "
                              "promotion moves a doc, it does not create one" % slug))
    else:
        missing, has_tbd, has_cite = reference_shape(
            ref.read_text(encoding="utf-8", errors="replace"))
        problems = []
        if missing:
            problems.append("missing sections: " + ", ".join(missing))
        if has_tbd:
            problems.append("contains <TBD>")
        if not has_cite:
            problems.append("no file:line cite")
        if problems:
            rows.append(("warn", "reference/%s.md shape: %s" % (slug, "; ".join(problems))))
        else:
            rows.append(("ok", "reference/%s.md shape OK" % slug))
        rows.append(("note", "reference/%s.md: content unreviewed by a person "
                             "(Rule 19 residue -- not machine-checkable)" % slug))

    # 5 -- verify provenance. This tests the HONESTY OF THE CLAIM, not the presence of tests:
    #      a tracker that declares a verify tier owes a green record; one that declares none,
    #      or carries a `tests-deferred:` waiver, owes nothing.
    deferred = re.search(r"(?m)^>\s*tests-deferred:\s*(.+)$", text)
    tiers = sorted(set(re.findall(r"verify:\s*(unit|integration|e2e)\b", text)))
    payload, rail_exists = read_verify(repo_root, feature)
    status, detail = verify_verdict(payload, git_head(repo_root))
    if not rail_exists:
        # OQ-3: no rail is an ABSENT RECORD, not a failed test. It cannot block, or every
        # project without a run rail would be permanently un-promotable. It also must not be
        # silent, or the strongest pre-condition disappears with no trace.
        if deferred:
            rows.append(("ok", "tests-deferred: %s (waiver on record)" % deferred.group(1).strip()))
        elif tiers:
            rows.append(("warn", "verify tier(s) %s claimed, but this project keeps no .runs "
                                 "rail -- the claim is UNVERIFIABLE here; confirm the tests are "
                                 "green before applying" % "/".join(tiers)))
        else:
            rows.append(("warn", "no verify tier claimed and no .runs rail -- nothing attests "
                                 "that anything was tested"))
    elif status == "pass":
        rows.append(("ok", "verify %s" % detail))
    elif deferred:
        rows.append(("ok", "tests-deferred: %s (waiver on record)" % deferred.group(1).strip()))
    elif tiers:
        rows.append(("block", "verify tier(s) %s claimed but the rail is %s -- %s"
                     % ("/".join(tiers), status, detail)))
    else:
        rows.append(("warn", "no verify tier claimed and the rail is %s -- %s" % (status, detail)))

    # 6 -- docs/ clean (advisory: promotion writes there, and a dirty tree makes the
    #      promotion commit pick up someone else's work)
    try:
        st = subprocess.run(["git", "-C", str(repo_root), "status", "--porcelain", "--", "docs"],
                            capture_output=True, text=True, timeout=30)
        dirty = [l for l in st.stdout.splitlines() if l.strip()] if st.returncode == 0 else []
    except (OSError, subprocess.TimeoutExpired):
        dirty = []
    rows.append(("warn", "%d uncommitted path(s) under docs/" % len(dirty)) if dirty
                else ("ok", "docs/ clean"))
    return rows


def exit_code(rows):
    levels = {lvl for lvl, _ in rows}
    return 2 if "block" in levels else (1 if "warn" in levels else 0)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="The six /promote-impl pre-conditions (DOCS-PROTOCOL Rule 19).")
    ap.add_argument("--suite", required=True,
                    help="FEATURE stem, i.e. docs/{FEATURE}-IMPL.md")
    ap.add_argument("--repo", default=".", help="repo root (default: cwd)")
    ap.add_argument("--json", action="store_true", help="emit rows as JSON")
    args = ap.parse_args(argv)

    rows = promote_check(args.repo, args.suite)
    code = exit_code(rows)
    if args.json:
        print(json.dumps({"suite": args.suite, "exit": code,
                          "rows": [{"level": l, "text": t} for l, t in rows]}, indent=2))
        return code

    color = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
    def paint(s, c):
        return "\033[%sm%s\033[0m" % (c, s) if color else s
    glyph = {"ok": paint("  ok   ", "32"), "warn": paint("  WARN ", "33"),
             "block": paint("  BLOCK", "31"), "note": paint("  note ", "2")}
    for lvl, txt in rows:
        print("%s %s" % (glyph[lvl], txt))
    verdict = {0: paint("promotable", "32"),
               1: paint("promotable with warnings", "33"),
               2: paint("NOT promotable", "31")}[code]
    print("  promote-check %s: %s" % (args.suite, verdict))
    return code


if __name__ == "__main__":
    sys.exit(main())
