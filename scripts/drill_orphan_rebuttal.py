#!/usr/bin/env python3
"""Find distractors whose rationale rebuts a claim the option no longer makes.

The lost-limiter detector asks what the rewrite deleted from an option. It has
to be run against the originals, it flags 1,276 options to find 7 real defects,
and it misses any case where the falsifier was a construction rather than a word
("reduces to", "is limited to") or a causal clause carrying no limiter at all.

This asks a different and much sharper question, and asks it of the corpus as it
stands, with no originals needed: does the rationale for a WRONG option argue
against an exclusivity claim that the option itself does not make? That mismatch
is the signature the audit kept finding by hand --

    option  C  "confirmation that a will exists."
    ratio.  C  "Confirming that a will exists is the beginning of the
                inventory, not the whole of it."

The rationale rebuts "only confirmation that a will exists", which is what the
option said before it was shortened. The option as it now reads is simply true,
so the item has two defensible answers. An orphaned rebuttal is evidence the
falsifier was deleted and nobody updated the reasoning.

It is a candidate list for a human or a verifier, not a defect list. A rationale
may legitimately observe that the key is the fuller answer without the distractor
being true, and most of these do: measured against the 16 fatal defects a 1,280
drill LLM audit found, this flags 84 options and catches 4 of them, a recall of
25% at a precision of 4.8%. That is nine times the precision of the lost-limiter
detector and a sixth of its candidate count, and still not good enough to stand
in for the audit. All 41 of its candidates outside the audited region were read
by hand and yielded no further defect.

    python3 -I scripts/drill_orphan_rebuttal.py [--show N] [--out FILE]
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re

ROOT = "CFAL3/Resources"
KEYS = ("A", "B", "C")

# A rationale saying "this option is not the whole story" only makes sense
# against an option that claimed to BE the whole story.
REBUTTAL = re.compile(
    r"\bnot the (?:whole|sole|only|entire|full|complete)\b"
    r"|\bnot (?:the )?only\b"
    r"|\bbarely (?:begins?|scratch)"
    r"|\b(?:is|are) only (?:the|a|an|one|part)\b"
    r"|\bis the beginning\b|\bbegins? the (?:picture|inventory|list|story)\b"
    r"|\bnot systematically\b"
    r"|\balone (?:is|are|does|do|would|cannot|is not)\b"
    r"|\b(?:is|are) not limited to\b"
    r"|\bonly part of\b|\bone of (?:several|many)\b"
    r"|\bnot the whole\b|\brather than the whole\b"
    r"|\bgoes further than\b|\bmore than (?:just|simply)\b", re.I)

# If the option still carries one of these, its exclusivity claim survived and
# the rationale is not orphaned.
LIMITER = re.compile(
    r"\b(?:only|solely|exclusively|sole|alone|never|always|every|all|any|none"
    r"|entirely|wholly|strictly|purely|must|cannot|nothing more|no other"
    r"|limited to|reduces to|confined to|merely|just|simply)\b", re.I)


def load() -> list:
    items = []
    for path in sorted(glob.glob(os.path.join(ROOT, "los_drills_r*.json"))):
        for group in json.load(open(path)).get("drills", []):
            for q in group.get("questions", []):
                o, c = q.get("options"), q.get("correct")
                if isinstance(o, dict) and len(o) == 3 and c in o:
                    items.append((q, os.path.basename(path)))
    return items


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--show", type=int, default=0)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    rows = []
    for q, fname in load():
        rats = q.get("rationales") or {}
        for letter in KEYS:
            if letter == q["correct"]:
                continue                      # the key is not rebutted
            opt, rat = q["options"][letter], rats.get(letter) or ""
            if not REBUTTAL.search(rat):
                continue
            if LIMITER.search(opt):
                continue                      # claim survived; not orphaned
            rows.append({
                "id": q["id"], "file": fname, "letter": letter,
                "key": q["correct"],
                "cue": REBUTTAL.search(rat).group(0),
                "option": " ".join(opt.split()),
                "rationale": " ".join(rat.split()),
                "stem": " ".join((q.get("stem") or "").split()),
            })

    rows.sort(key=lambda r: (r["file"], r["id"], r["letter"]))
    cues = collections.Counter(r["cue"].lower() for r in rows)
    print(f"{len(rows)} distractors carry a rebuttal their option no longer earns")
    print(f"  across {len({r['id'] for r in rows})} questions")
    print("  commonest cues: " + ", ".join(f"{c}({n})" for c, n in cues.most_common(8)))

    for r in rows[:args.show]:
        print(f"\n--- {r['id']} {r['letter']} (key {r['key']})  cue: {r['cue']!r}")
        print(f"  STEM {r['stem'][:150]}")
        print(f"  OPT  {r['option'][:150]}")
        print(f"  RAT  {r['rationale'][:260]}")

    if args.out:
        json.dump(rows, open(args.out, "w"), indent=2, ensure_ascii=False)
        print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
