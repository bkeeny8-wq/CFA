#!/usr/bin/env python3
"""Stop the answer key from marching A, B, C, A, B, C through every drill file.

    python3 scripts/fix_drill_answer_cycle.py --dry-run
    python3 scripts/fix_drill_answer_cycle.py

THE PROBLEM. The generator laid the correct answer down in strict rotation.
Across the 2,631 consecutive pairs in the corpus, 2,623 of them — 99.7% —
follow A to B to C to A. Thirty-four of the thirty-six files are at 100.0%.
Answer one question and you have every answer after it, for the rest of the
file, without reading anything.

That is worse than every length and wording cue put together, and unlike
those it is not a matter of degree: it is a complete answer key.

IT IS REACHABLE FROM THE UI. Options are never shuffled at display time, so
the stored letter is the letter on screen, and two entry points hand the
session to the runner in file order:

    LOSDrillReadingView.swift:114   "Run all N" on a single LOS
    CycleMapView.swift:418          practice a cycle-map phase

The reading-level "Drill all (shuffled)" button, the plan blocks and the
dashboard sessions all shuffle, so the cycle is hidden there but still sitting
in the data for anything added later.

THE FIX. Permute each question's three options — text, rationales and the
stored key together — so the key lands on a letter drawn from a hash of the
question id. Nothing is rewritten and nothing is deleted; A and C swap places
and the item is otherwise identical.

Target letters are assigned by walking the corpus in HASH order and dealing
A, B, C round-robin, which gives exactly one third each while leaving the
sequence in FILE order with no structure, because hash order and file order
are unrelated. Doing it the other way — a hash per question, independently —
also works but lands at 889 plus or minus thirty per letter and occasionally
produces a run of five, which looks like a pattern even though it is not one.

WHAT THIS DOES NOT DISTURB. Option lengths are untouched, so the rank
distribution set by fix_drill_length_cue.py survives exactly. Capitalisation
is untouched. Every field other than options, rationales and correct is
untouched.

WHAT IT DOES DISTURB. Attempt.selectedOption records which LETTER was chosen,
and after this runs an old attempt's "you answered B" points at whatever text
now sits in slot B. Attempt.wasCorrect is stored separately and is unaffected,
so scores, the review queue and every scheduling decision are unaffected. The
staleness is cosmetic and confined to re-reading an attempt made before this
ran.
"""

from __future__ import annotations

import argparse
import collections
import glob
import hashlib
import itertools
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = sorted(glob.glob(os.path.join(ROOT, "CFAL3/Resources/los_drills_r*.json")))
KEYS = ("A", "B", "C")
CYCLE = {"A": "B", "B": "C", "C": "A"}


def digest(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def cycle_rate(seq: list) -> tuple:
    hits = sum(1 for a, b in zip(seq, seq[1:]) if b == CYCLE[a])
    return hits, max(0, len(seq) - 1)


def longest_run(seq: list) -> int:
    best = run = 1
    for a, b in zip(seq, seq[1:]):
        run = run + 1 if a == b else 1
        best = max(best, run)
    return best


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    loaded = {p: json.load(open(p)) for p in FILES}
    questions = []          # (path, question) in file order
    for path in FILES:
        for drill in loaded[path].get("drills", []):
            for q in drill.get("questions", []):
                if isinstance(q.get("options"), dict) and q.get("correct") in KEYS:
                    questions.append((path, q))

    before = [q["correct"] for _, q in questions]
    hits, pairs = cycle_rate(before)
    print(f"{len(questions)} questions")
    print(f"  before: {hits}/{pairs} consecutive pairs follow A->B->C "
          f"({hits / pairs * 100:.1f}%), distribution "
          f"{dict(collections.Counter(before))}, longest run {longest_run(before)}")

    # Walk the corpus in the order it is actually served and draw each key
    # letter from the quota still unspent, weighted by what is left, with the
    # draw seeded on the question id so the whole thing is reproducible.
    # Depleting quotas guarantees exactly one third each; the weighting keeps
    # the draw unbiased until the very end.
    #
    # The one constraint is a cap on repeats. A free hash-per-question
    # assignment is genuinely unstructured, but it produced a run of NINE
    # identical answers in a row, and a learner who meets that will see a
    # pattern whether or not one is there. Four in a row is refused unless
    # there is no quota left to refuse with.
    quota = {k: len(questions) // 3 for k in KEYS}
    for i in range(len(questions) - sum(quota.values())):
        quota[KEYS[i]] += 1
    target, run_letter, run_len = {}, None, 0
    for _, q in questions:
        allowed = [k for k in KEYS if quota[k] > 0]
        if run_len >= 3:
            allowed = [k for k in allowed if k != run_letter] or allowed
        pot = sum(quota[k] for k in allowed)
        draw = int(digest(q["id"] + "!key"), 16) % pot
        for k in allowed:
            draw -= quota[k]
            if draw < 0:
                break
        target[q["id"]] = k
        quota[k] -= 1
        run_len = run_len + 1 if k == run_letter else 1
        run_letter = k

    moved = 0
    for _, q in questions:
        want = target[q["id"]]
        key = q["correct"]
        # Both permutations that put the key on `want`; pick by hash so the two
        # distractors do not keep their relative order either.
        candidates = [p for p in itertools.permutations(KEYS)
                      if p[KEYS.index(key)] == want]
        # p maps old slot i -> new letter p[i]
        pick = candidates[int(digest(q["id"] + "!perm"), 16) % len(candidates)]
        mapping = {KEYS[i]: pick[i] for i in range(3)}
        if all(k == v for k, v in mapping.items()):
            continue
        q["options"] = {mapping[k]: v for k, v in q["options"].items()}
        if isinstance(q.get("rationales"), dict) and sorted(q["rationales"]) == list(KEYS):
            q["rationales"] = {mapping[k]: v for k, v in q["rationales"].items()}
        q["options"] = {k: q["options"][k] for k in KEYS}
        if isinstance(q.get("rationales"), dict):
            q["rationales"] = {k: q["rationales"][k] for k in KEYS if k in q["rationales"]}
        q["correct"] = want
        moved += 1

    after = [q["correct"] for _, q in questions]
    hits2, _ = cycle_rate(after)
    print(f"  after:  {hits2}/{pairs} ({hits2 / pairs * 100:.1f}%), distribution "
          f"{dict(collections.Counter(after))}, longest run {longest_run(after)}")
    print(f"  {moved} question(s) permuted\n")

    worst = None
    for path in FILES:
        seq = [q["correct"] for p, q in questions if p == path]
        h, t = cycle_rate(seq)
        if t and (worst is None or h / t > worst[1]):
            worst = (os.path.basename(path), h / t)
    print(f"  worst single file now {worst[0]} at {worst[1] * 100:.1f}% (chance 33.3%)")

    if args.dry_run:
        print("\n(dry run — nothing written)")
        return 0
    for path in FILES:
        with open(path, "w") as fh:
            json.dump(loaded[path], fh, indent=2, ensure_ascii=False)
            fh.write("\n")
    print(f"\nwrote {len(FILES)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
