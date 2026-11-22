#!/usr/bin/env python3
"""Apply a rewritten-option patch to the LOS drill files, with validation.

    python3 scripts/apply_drill_rewrite.py --patch out.json --dry-run
    python3 scripts/apply_drill_rewrite.py --patch out.json

The patch is JSON, either a list or {"questions": [...]}, each entry:

    {"id": "r17_swf_los_d_q11",
     "stem": "...",                       # optional; omit to keep
     "options": {"A": "...", "B": "...", "C": "..."},
     "rationales": {"A": "...", "B": "...", "C": "..."}}   # optional

An entry carrying "correct" is checked against the stored key and REJECTED on
mismatch rather than obeyed. The key never moves: scheduling history and flags
are keyed to the question, so a moved key silently invalidates every past
review the owner has done.

Everything else is rejected too rather than written: a missing option letter,
a blank option, two options that collide once whitespace is normalised, or an
id the corpus does not have. Rejections are printed and the file is left alone.
Style-rule breaches are reported but not rejected — the linter is advice at
this stage, and the corpus-level score in drill_style_lint.py is the real test.
"""

from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import drill_style_lint as lint  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = sorted(glob.glob(os.path.join(ROOT, "CFAL3/Resources/los_drills_r*.json")))
KEYS = ("A", "B", "C")


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "")).strip().lower().rstrip(".")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--patch", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--include-held", action="store_true",
                    help="also apply items a verifier still objected to")
    args = ap.parse_args()

    raw = json.load(open(args.patch))
    entries = raw["questions"] if isinstance(raw, dict) else raw
    by_id, skipped_held = {}, 0
    for e in entries:
        if not e or not e.get("id"):
            continue
        # A held item is one the checker still objects to after a repair pass.
        # The ORIGINAL is badly written but correct, so leaving it alone is the
        # conservative move: bad style beats a broken question.
        if e.get("_status") == "held" and not args.include_held:
            skipped_held += 1
            continue
        by_id[e["id"]] = e            # last write wins, so a re-run can fix one item
    print(f"patch carries {len(by_id)} question(s)"
          + (f"; {skipped_held} held back by a verifier and NOT applied" if skipped_held else ""))

    loaded = {p: json.load(open(p)) for p in FILES}
    index = {}
    for path, data in loaded.items():
        for drill in data.get("drills", []):
            for q in drill.get("questions", []):
                if isinstance(q.get("options"), dict) and q.get("correct") in KEYS:
                    index[q["id"]] = (path, q)

    rejects = collections.Counter()
    before, after = collections.Counter(), collections.Counter()
    applied, shown = [], 0
    touched = set()

    for qid, e in by_id.items():
        if qid not in index:
            rejects["unknown_id"] += 1
            print(f"  reject {qid}: not in the corpus")
            continue
        path, q = index[qid]
        opts = e.get("options") or {}
        if sorted(opts) != list(KEYS) or not all(str(opts[k]).strip() for k in KEYS):
            rejects["bad_options"] += 1
            print(f"  reject {qid}: options must be a non-empty A, B and C")
            continue
        if len({norm(opts[k]) for k in KEYS}) < 3:
            rejects["duplicate_options"] += 1
            print(f"  reject {qid}: two options say the same thing")
            continue
        if e.get("correct") and e["correct"] != q["correct"]:
            rejects["moved_key"] += 1
            print(f"  reject {qid}: patch moves the key {q['correct']} -> {e['correct']}")
            continue
        rats = e.get("rationales") or {}
        if rats and (sorted(rats) != list(KEYS) or not all(str(rats[k]).strip() for k in KEYS)):
            rejects["bad_rationales"] += 1
            print(f"  reject {qid}: rationales must be a non-empty A, B and C")
            continue

        snapshot = {"stem": q.get("stem"), "options": dict(q["options"]),
                    "rationales": dict(q.get("rationales") or {})}
        for f in lint.lint_question(q):
            before[f] += 1
        for v in q["options"].values():
            for f in lint.lint_option(v):
                before[f] += 1

        if e.get("stem"):
            q["stem"] = e["stem"].strip()
        q["options"] = {k: str(opts[k]).strip() for k in KEYS}
        if rats:
            q["rationales"] = {k: str(rats[k]).strip() for k in KEYS}

        for f in lint.lint_question(q):
            after[f] += 1
        for v in q["options"].values():
            for f in lint.lint_option(v):
                after[f] += 1

        touched.add(path)
        applied.append(qid)
        if shown < args.sample:
            shown += 1
            print(f"\n  --- {qid}  (key {q['correct']})")
            print(f"  BEFORE {' '.join((snapshot['stem'] or '').split())}")
            for k in KEYS:
                print(f"      {'*' if k == q['correct'] else ' '} {k}. "
                      f"{' '.join(snapshot['options'][k].split())}")
            print(f"  AFTER  {' '.join((q.get('stem') or '').split())}")
            for k in KEYS:
                print(f"      {'*' if k == q['correct'] else ' '} {k}. "
                      f"{' '.join(q['options'][k].split())}")

    print(f"\napplied {len(applied)}, rejected {sum(rejects.values())} "
          f"{dict(rejects) if rejects else ''}")
    rules = sorted(set(before) | set(after))
    if rules:
        print(f"\n  rule breaches on the patched questions{'':8}before   after")
        for r in rules:
            print(f"    {r:28} {before[r]:8} {after[r]:7}")

    if args.dry_run:
        print("\n(dry run — nothing written)")
        return 0
    for path in sorted(touched):
        with open(path, "w") as fh:
            json.dump(loaded[path], fh, indent=2, ensure_ascii=False)
            fh.write("\n")
    print(f"\nwrote {len(touched)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
