#!/usr/bin/env python3
"""Stop the capital letter at the front of an option from naming the answer.

    python3 scripts/fix_drill_capitalisation_cue.py --dry-run
    python3 scripts/fix_drill_capitalisation_cue.py

THE PROBLEM. The generator wrote distractors as standalone capitalised
sentences and correct answers as lowercase continuations of the stem. The
result is a cue that needs no curriculum knowledge at all: where exactly one
option begins with a lowercase letter, it is the key 96% of the time, and that
fires on 919 of 2,667 drills.

This one is NOT collateral damage from the length-balancing passes — it is
present on 35% of the pre-balancing data too, so it has been in the corpus
since generation and survived both earlier audits. It was found by the Nov 2026
content audit, which noticed that the key was "the only option that
grammatically continues the stem".

THE FIX. Uppercase the first letter of every option. Capitalising the first
word of a list item can never produce a wrong word — unlike lowercasing, which
would mangle "GIPS", "Norway's" and every other proper noun — so the direction
is chosen for safety rather than for grammar. A capitalised item after a
colon-terminated stem is ordinary style and reads fine.

Options opening with a digit or a symbol ("3% of the fund's value", "+50.") are
left alone, and the script checks afterwards that they have not become a cue of
their own. Character counts never change, so the length distribution fixed by
fix_drill_length_cue.py is preserved exactly.

The case bank does not have this problem (the cue fires on 1 of its 270
multiple-choice items) and is not touched.
"""

from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = sorted(glob.glob(os.path.join(ROOT, "CFAL3/Resources/los_drills_r*.json")))
KEYS = ("A", "B", "C")
# "iShares"-style words would be corrupted by a naive .upper() on the first
# character. There are none today; the guard is here so that adding one later
# does not silently break it.
CAMEL = re.compile(r"^[a-z][a-zA-Z]*[A-Z]")


def lift(text: str) -> str:
    if not text or not text[:1].islower() or CAMEL.match(text):
        return text
    return text[0].upper() + text[1:]


def cue_counts(questions: list) -> dict:
    """How often each "the odd one out is the key" rule would fire."""
    out = collections.Counter()
    for q in questions:
        opts, key = q["options"], q["correct"]
        for name, test in (
            ("lone_lower", lambda v: v[:1].islower()),
            ("lone_upper", lambda v: v[:1].isupper()),
            ("lone_digit", lambda v: v[:1].isdigit()),
            ("lone_symbol", lambda v: bool(v) and not v[0].isalnum()),
        ):
            odd = [x for x, v in opts.items() if test(v)]
            if len(odd) == 1:
                out[name + "_fires"] += 1
                if odd[0] == key:
                    out[name + "_is_key"] += 1
    return out


def report(label: str, questions: list) -> None:
    c = cue_counts(questions)
    n = len(questions)
    print(f"  {label}")
    for rule in ("lone_lower", "lone_upper", "lone_digit", "lone_symbol"):
        fires, hits = c[rule + "_fires"], c[rule + "_is_key"]
        acc = f"{hits / fires * 100:5.1f}%" if fires else "    — "
        print(f"    {rule:12} fires on {fires:5} ({fires / n * 100:4.1f}%)   "
              f"names the key {hits:5} ({acc} of the time)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    loaded = {p: json.load(open(p)) for p in FILES}

    def every() -> list:
        return [q for d in loaded.values() for dr in d["drills"] for q in dr["questions"]
                if isinstance(q.get("options"), dict) and q.get("correct") in KEYS]

    before_lengths = [
        sorted(q["options"], key=lambda k: -len(q["options"][k])).index(q["correct"])
        for q in every()
    ]
    print(f"{len(every())} drill questions\n")
    report("BEFORE", every())

    changed_opts = 0
    for path, data in loaded.items():
        touched = False
        for drill in data.get("drills", []):
            for q in drill.get("questions", []):
                if not isinstance(q.get("options"), dict):
                    continue
                for k, v in list(q["options"].items()):
                    lifted = lift(v)
                    if lifted != v:
                        q["options"][k] = lifted
                        changed_opts += 1
                        touched = True
        if touched and not args.dry_run:
            with open(path, "w") as fh:
                json.dump(data, fh, indent=2, ensure_ascii=False)
                fh.write("\n")

    print()
    report("AFTER", every())

    after_lengths = [
        sorted(q["options"], key=lambda k: -len(q["options"][k])).index(q["correct"])
        for q in every()
    ]
    print(f"\n  {changed_opts} option(s) recapitalised")
    print(f"  length ranking unchanged: {before_lengths == after_lengths}")
    if args.dry_run:
        print("  (dry run — nothing written)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
