#!/usr/bin/env python3
"""Before-and-after on the drill corpus, against any git ref.

    python3 scripts/drill_rewrite_report.py                 # vs HEAD
    python3 scripts/drill_rewrite_report.py --ref 9f96f27   # vs a named commit
    python3 scripts/drill_rewrite_report.py --samples 5     # with examples

Reads the committed drill files out of git rather than the working tree, so it
can be run at any point during a rewrite and still show what actually changed.
Everything it reports is computed by drill_style_lint, so the rules here and
the rules the rewrite is held to cannot drift apart.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import drill_style_lint as lint  # noqa: E402

KEYS = ("A", "B", "C")
RULES = ("boilerplate", "multi_sentence", "equation", "arithmetic", "too_long",
         "shouting", "inconsistent_case", "mixed_option_types",
         "dangling_reference", "fragment_stem", "equation_in_stem",
         "shouting_stem")


def from_git(ref: str) -> dict:
    """Every drill question as that ref has it, by id."""
    listing = subprocess.run(
        ["git", "ls-tree", "--name-only", ref, "CFAL3/Resources/"],
        capture_output=True, text=True, cwd=ROOT).stdout.split()
    out = {}
    for path in listing:
        if "los_drills_r" not in path or "index" in path:
            continue
        # Bytes, not text: git's output is decoded here rather than by the
        # subprocess layer, which would translate line endings and quietly
        # change the character counts this whole report is about.
        raw = subprocess.run(["git", "show", f"{ref}:{path}"],
                             capture_output=True, cwd=ROOT).stdout
        try:
            data = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        for drill in data.get("drills", []):
            for q in drill.get("questions", []):
                if isinstance(q.get("options"), dict) and q.get("correct") in KEYS:
                    out[q["id"]] = q
    return out


def tally(questions: list) -> dict:
    per = {r: 0 for r in RULES}
    clean = 0
    for q in questions:
        flags = set(lint.lint_question(q))
        for v in q["options"].values():
            flags.update(lint.lint_option(v))
        for f in flags:
            if f in per:
                per[f] += 1
        if not flags:
            clean += 1
    return {"per": per, "clean": clean, "n": len(questions)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--samples", type=int, default=0)
    args = ap.parse_args()

    before = from_git(args.ref)
    after = {q["id"]: q for q in lint.load_drills("los_drills_r*")}

    shared = [i for i in after if i in before]
    changed = [i for i in shared
               if before[i]["options"] != after[i]["options"]
               or (before[i].get("stem") or "") != (after[i].get("stem") or "")]

    print(f"{len(after)} drill questions in the working tree, "
          f"{len(before)} at {args.ref}")
    print(f"{len(changed)} changed ({len(changed) / max(1, len(shared)) * 100:.1f}%), "
          f"{len(shared) - len(changed)} untouched")
    moved = [i for i in shared if before[i]["correct"] != after[i]["correct"]]
    print(f"{len(moved)} had the answer move to a different letter"
          + ("  <-- every one of these needs explaining" if moved else ""))

    b = tally([before[i] for i in shared])
    a = tally([after[i] for i in shared])
    print(f"\n{'rule':24}{'before':>12}{'after':>12}")
    for r in RULES:
        print(f"  {r:22}{b['per'][r]:8} {b['per'][r] / b['n'] * 100:5.1f}%"
              f"{a['per'][r]:8} {a['per'][r] / a['n'] * 100:5.1f}%")
    print(f"  {'CLEAN':22}{b['clean']:8} {b['clean'] / b['n'] * 100:5.1f}%"
          f"{a['clean']:8} {a['clean'] / a['n'] * 100:5.1f}%")

    bl = [len(v) for i in shared for v in before[i]["options"].values()]
    al = [len(v) for i in shared for v in after[i]["options"].values()]
    print(f"\n{'option length':24}{'before':>12}{'after':>12}        (case bank 18)")
    for name, fn in (("median", statistics.median), ("mean", statistics.mean),
                     ("max", max)):
        print(f"  {name:22}{fn(bl):8.0f}    {fn(al):8.0f}")

    print(f"\n{'answerable without reading':24}{'before':>12}{'after':>12}")
    bs = lint.no_reading_scores([before[i] for i in shared])
    as_ = lint.no_reading_scores([after[i] for i in shared])
    for k in sorted(bs, key=lambda k: -bs[k]):
        print(f"  {k:36}{bs[k]:7.1f}%{as_[k]:9.1f}%")
    print(f"  {'chance':36}   33.3%     33.3%")
    print(f"\n  worst strategy: {max(bs.values()):.1f}% -> {max(as_.values()):.1f}%")

    for i in changed[:args.samples]:
        print(f"\n  --- {i}  (key {after[i]['correct']})")
        print(f"  BEFORE {' '.join((before[i].get('stem') or '').split())}")
        for k in KEYS:
            print(f"      {'*' if k == before[i]['correct'] else ' '} {k}. "
                  f"{' '.join(before[i]['options'][k].split())}")
        print(f"  AFTER  {' '.join((after[i].get('stem') or '').split())}")
        for k in KEYS:
            print(f"      {'*' if k == after[i]['correct'] else ' '} {k}. "
                  f"{' '.join(after[i]['options'][k].split())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
