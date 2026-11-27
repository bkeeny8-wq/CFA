#!/usr/bin/env python3
"""Find rewrites that deleted the word making a distractor false.

A 200-drill LLM audit of the rewrite pass (6 fatal defects in 200, a 3% rate)
found one mechanism behind nearly all of them. A distractor in this corpus is
often false ONLY because of a limiting word -- "Nasdaq only", "violated only
Standard I(C)", "never a model fee". Shortening the option to the house style
deletes that word, and the option becomes true. The question then has two
defensible answers and the stored key is no longer uniquely right.

    before   C. "Nasdaq only."                 false: Nasdaq is not the sole provider
    after    C. "Nasdaq."                      TRUE:  Nasdaq is a major provider

This is invisible to every check that ran before it. The key never moved. No
negation or antonym flipped -- "only" is not a negation. The options stayed
distinct and non-empty. The house-style counts improved. Nothing was wrong
except the answer.

So this looks for limiting words that the original option had and the rewrite
does not, scored by how much that word was doing. It is a candidate list for a
verifier, not a defect list: "only" is often deleted harmlessly along with the
clause it modified. On the three audited positives it fires on all three.

    python3 -I scripts/drill_lost_limiter.py --orig DIR [--key-only] [--show N]
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re

NEW = "CFAL3/Resources"
KEYS = ("A", "B", "C")

# Ranked by how often the word alone carries an option's falsity. An
# exclusivity word usually IS the claim; a quantifier usually sharpens one.
LIMITERS = {
    "exclusivity": ["only", "solely", "exclusively", "sole", "alone", "never",
                    "always", "every", "all", "any", "none", "no other",
                    "entirely", "wholly", "strictly", "purely", "must",
                    "cannot", "exclusively"],
    "degree": ["at least", "at most", "more than", "less than", "fewer than",
               "greater than", "no more than", "no less than", "up to",
               "merely", "just", "primarily", "mainly", "largely", "typically",
               "generally", "usually", "often", "rarely", "unlimited"],
}
WEIGHT = {"exclusivity": 2, "degree": 1}


def present(word: str, text: str) -> bool:
    return re.search(rf"\b{re.escape(word)}\b", text or "", re.I) is not None


def load(directory: str) -> dict:
    out = {}
    for path in sorted(glob.glob(os.path.join(directory, "los_drills_r*.json"))):
        for group in json.load(open(path)).get("drills", []):
            for q in group.get("questions", []):
                o, c = q.get("options"), q.get("correct")
                if isinstance(o, dict) and len(o) == 3 and c in o:
                    out[q["id"]] = q
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--orig", required=True, help="directory of pre-rewrite drill files")
    ap.add_argument("--new", default=NEW)
    ap.add_argument("--key-only", action="store_true",
                    help="only options sitting on the stored key")
    ap.add_argument("--show", type=int, default=0)
    ap.add_argument("--out", default="")
    ap.add_argument("--min-score", type=int, default=2)
    args = ap.parse_args()

    old, new = load(args.orig), load(args.new)
    rows = []
    for qid, nq in new.items():
        oq = old.get(qid)
        if oq is None or oq["options"] == nq["options"]:
            continue
        key = nq["correct"]
        for letter in KEYS:
            if args.key_only and letter != key:
                continue
            a, b = oq["options"][letter], nq["options"][letter]
            if a == b:
                continue
            lost = []
            for kind, words in LIMITERS.items():
                for w in words:
                    if present(w, a) and not present(w, b):
                        lost.append((kind, w))
            if not lost:
                continue
            score = sum(WEIGHT[k] for k, _ in lost)
            if score < args.min_score:
                continue
            rows.append({
                "id": qid, "letter": letter, "is_key": letter == key,
                "score": score, "lost": [w for _, w in lost],
                "kinds": sorted({k for k, _ in lost}),
                "before": " ".join(a.split()), "after": " ".join(b.split()),
            })

    rows.sort(key=lambda r: (-r["score"], r["id"]))
    kinds = collections.Counter(k for r in rows for k in r["kinds"])
    words = collections.Counter(w for r in rows for w in r["lost"])
    print(f"{len(rows)} options lost a limiting word "
          f"({sum(1 for r in rows if r['is_key'])} of them the key)")
    print(f"  by kind  {dict(kinds)}")
    print("  commonest words lost: "
          + ", ".join(f"{w}({n})" for w, n in words.most_common(8)))
    print(f"  distinct questions: {len({r['id'] for r in rows})}")

    for r in rows[:args.show]:
        print(f"\n--- {r['id']} {r['letter']}"
              f"{' (KEY)' if r['is_key'] else ''}  score {r['score']}"
              f"  lost {','.join(r['lost'])}")
        print(f"  BEFORE {r['before'][:200]}")
        print(f"  AFTER  {r['after'][:200]}")

    if args.out:
        json.dump(rows, open(args.out, "w"), indent=2, ensure_ascii=False)
        print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
