#!/usr/bin/env python3
"""Make LOS-drill option length carry no information about the answer.

    python3 scripts/fix_drill_length_cue.py --dry-run
    python3 scripts/fix_drill_length_cue.py

THE PROBLEM. Sort a drill's three options by length and ask where the correct
one sits. It should be longest a third of the time, middle a third, shortest a
third. It was MIDDLE 96.4% of the time. On the 1,586 drills where the gaps
exceed about three words — visible at a glance — "pick the middle option" was
correct 1,586 times out of 1,586. That is a working answer key that needs no
knowledge of the curriculum at all.

HOW IT HAPPENED, because the history matters for not repeating it. The drills
were generated with the correct option UNIQUELY LONGEST 76.6% of the time — the
usual artefact of writing the right answer as the complete one. Two repair
passes then ran:

    9265ff6  lengthen a distractor so the key is not uniquely longest
    c6a0a85  lengthen the key where it was uniquely shortest

Each pass fixed its own tail and neither looked at the middle. Squeezing both
tails of a three-way ranking leaves exactly one place for the key to go. Two
cues of 33% strength became one cue of 96% strength. Reverting is not a fix
either: 76.6% is only marginally less exploitable than 96.4%.

THE FIX. Give every question a TARGET RANK for its correct option, cycling
1/2/3 over a stable hash of the question id so the corpus comes out in exact
thirds and the assignment cannot correlate with subject matter. Then reach that
rank with the least intervention available:

THE FIX IS DELETION ONLY. Every option has two authored forms: the text before
9265ff6, and the text now. This script chooses between them and writes nothing
new. Reverting a padded distractor pushes the correct option UP the ranking;
reverting a padded correct option (c6a0a85 lengthened keys that were uniquely
shortest) pushes it DOWN. Those two moves are the whole toolkit.

NO EXPANSION. The obvious way to reach a third at "correct shortest" is to
lengthen both distractors, and balance_drill_option_length.expand_to_target()
is sitting right there. It was tried and it is not usable: asked for text it
produces things like

    "precise, timely, and quantitative — as a complete reading of these are
     that they."
    "improve the precision of the sample means but not the variances. As a
     complete reading of the question as posed."

Its clause extractor falls back to a degenerate template whenever the rationale
has no clean positive clause to lift, which is most of the time. Shipping that
would replace a length cue with a far louder one — pick the option that reads
like broken English — and would make the drills unreadable besides.

WHAT THAT COSTS. Only 14% of questions can reach "correct shortest" by
deletion, because the generator wrote correct answers long and there is often
nothing to delete. So the script gives rank 3 to every question that can take
it, then splits the remainder evenly between rank 1 and rank 2. The result is
roughly 43/43/14 rather than a clean 33/33/33 — the residual cue is a weak
"the shortest option is rarely right", worth 43% against 33% chance, down from
a 96% cue. Closing the last of it needs distractors rewritten as real prose,
which is an authoring job, not a text-manipulation one.

Stems, keys and rationales are never touched.
"""

from __future__ import annotations

import argparse
import collections
import glob
import hashlib
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = sorted(glob.glob(os.path.join(ROOT, "CFAL3/Resources/los_drills_r*.json")))
PRE_PAD = "9265ff6^"  # the last commit before any length balancing ran
KEYS = ("A", "B", "C")


def originals(ref: str) -> dict:
    """Option texts as authored, before either balancing pass."""
    out = {}
    listing = subprocess.run(
        ["git", "ls-tree", "--name-only", ref, "CFAL3/Resources/"],
        capture_output=True, text=True, cwd=ROOT).stdout.split()
    for path in listing:
        if "los_drills_r" not in path or "index" in path:
            continue
        raw = subprocess.run(["git", "show", f"{ref}:{path}"],
                             capture_output=True, cwd=ROOT).stdout
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            continue
        for drill in data.get("drills", []):
            for q in drill.get("questions", []):
                if isinstance(q.get("options"), dict):
                    out[q["id"]] = q["options"]
    return out


def rank_of(opts: dict, key: str) -> int:
    """1 = correct option is longest, 3 = shortest."""
    return sorted(opts, key=lambda k: -len(opts[k])).index(key) + 1


def variants(q: dict, orig: dict) -> dict:
    """Every option arrangement reachable by reverting some options.

    rank -> the chosen {A,B,C} texts. Reverting fewer options is preferred, so
    the corpus keeps as much of the reviewed current text as it can.
    """
    import itertools
    opts, key = q["options"], q["correct"]
    choices = []
    for k in KEYS:
        forms = [opts[k]]
        if orig.get(k) and orig[k] != opts[k]:
            forms.append(orig[k])
        choices.append(forms)
    best = {}
    for combo in itertools.product(*choices):
        trial = dict(zip(KEYS, combo))
        if len(set(v.strip() for v in trial.values())) < 3:
            continue
        r = rank_of(trial, key)
        reverts = sum(1 for k in KEYS if trial[k] != opts[k])
        if r not in best or reverts < best[r][0]:
            best[r] = (reverts, trial)
    return {r: t for r, (_, t) in best.items()}


def allocate(items: list) -> dict:
    """Give rank 3 to everything that can take it, then split the rest.

    Rank 3 is the scarce one — roughly one question in seven can reach it by
    deletion — so it is assigned first and greedily. Ranks 1 and 2 are then
    balanced over whatever remains, by a stable hash so the split does not
    track subject matter.
    """
    # Most-constrained-first. A question that can only land in one place takes
    # that place before anything with a choice competes for it; otherwise the
    # flexible questions crowd into the common rank and the scarce ones have
    # nowhere left to go. Ties break on a hash of the id so the assignment is
    # reproducible and uncorrelated with subject matter.
    order = sorted(items, key=lambda x: (len(x[1]),
                                         hashlib.sha256(x[0].encode()).hexdigest()))
    count = collections.Counter()
    capacity = collections.Counter()
    for _, reach in items:
        for r in reach:
            capacity[r] += 1
    # Fair share per rank: never promise more than the corpus can supply.
    quota = {}
    left = len(items)
    for r in sorted(capacity, key=lambda r: capacity[r]):
        share = min(capacity[r], left // max(1, (3 - len(quota))))
        quota[r] = share
        left -= share
    plan = {}
    for qid, reach in order:
        if not reach:
            plan[qid] = None
            continue
        pick = min(reach, key=lambda r: (count[r] / max(1, quota.get(r, 1)), r))
        plan[qid] = pick
        count[pick] += 1
    return plan


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    orig = originals(PRE_PAD)
    print(f"recovered {len(orig)} pre-padding question(s) from {PRE_PAD}")

    # Pass one: what can each question reach?
    loaded, reach = {}, []
    for path in FILES:
        with open(path) as fh:
            loaded[path] = json.load(fh)
        for drill in loaded[path].get("drills", []):
            for q in drill.get("questions", []):
                if not isinstance(q.get("options"), dict) or q.get("correct") not in KEYS:
                    continue
                reach.append((q["id"], variants(q, orig.get(q["id"], {}))))
    plan = allocate(reach)
    can3 = sum(1 for _, v in reach if 3 in v)
    print(f"{len(reach)} questions; {can3} ({can3/len(reach)*100:.0f}%) can reach "
          f"'correct shortest' by deletion alone")

    # Pass two: apply.
    stats = collections.Counter()
    before, after = collections.Counter(), collections.Counter()
    touched_files = 0
    by_id = {qid: v for qid, v in reach}
    for path, data in loaded.items():
        changed = False
        for drill in data.get("drills", []):
            for q in drill.get("questions", []):
                if not isinstance(q.get("options"), dict) or q.get("correct") not in KEYS:
                    continue
                key = q["correct"]
                before[rank_of(q["options"], key)] += 1
                want = plan.get(q["id"])
                opts = by_id[q["id"]].get(want) if want else None
                if opts and opts != q["options"]:
                    q["options"] = opts
                    stats["reverted"] += 1
                    changed = True
                elif opts:
                    stats["already"] += 1
                else:
                    stats["unreachable"] += 1
                after[rank_of(q["options"], key)] += 1
        if changed and not args.dry_run:
            with open(path, "w") as fh:
                json.dump(data, fh, indent=2, ensure_ascii=False)
                fh.write("\n")
            touched_files += 1

    n = sum(before.values())
    print(f"\n{n} drill questions")
    print(f"{'':22}{'before':>18}{'after':>18}")
    for r, label in ((1, "correct longest"), (2, "correct middle"), (3, "correct shortest")):
        print(f"  {label:20}{before[r]:7} {before[r]/n*100:6.1f}% "
              f"{after[r]:9} {after[r]/n*100:6.1f}%")
    print("\nactions:", dict(sorted(stats.items())))
    if args.dry_run:
        print("\n(dry run — nothing written)")
    else:
        print(f"\nwrote {touched_files} files")

    worst = max(after.values()) / n * 100
    print(f"\nbest single length heuristic now scores {worst:.1f}% (chance 33.3%, was 96.4%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
