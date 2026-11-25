#!/usr/bin/env python3
"""Stage the inputs a drill-rewrite workflow run needs.

    python3 scripts/export_drill_rewrite_inputs.py --out DIR --readings r17
    python3 scripts/export_drill_rewrite_inputs.py --out DIR --group 0 --groups 5

Writes DIR/source.json (every question in scope, with its rationales), the
redacted DIR/source_blind.json the rewriters read, and prints the workflow
`args` payload on stdout: the slice bounds, and the stored key letter for every
question as one string aligned to the source array.

The key travels in args rather than being re-read from source.json because the
verifier is told it and the rewriter is not. A rewriter that knows which option
is correct writes a better correct option and worse distractors; one that has
to work it out from the rationales keeps all three honest.

Withholding it takes more than dropping the `correct` field, which is why the
blind file exists. 170 rationales in the first group open with "Correct." and
590 with "Incorrect." -- that is the key spelled out, in a field the rewriter
has to read to preserve each option's substance. source_blind.json drops
`correct` and strips those openers (and the `Full statement:` artefact, which
the house style says to clean anyway); nothing else about the rationale is
touched, so the rewriter still has every word of the reasoning and still has
to work out which option it vindicates.

--group/--groups splits the corpus across several workflow invocations. One
workflow is capped at 1,000 agents and a full pass over 2,667 questions at ten
to a batch needs 267 rewriters plus two verifiers each, so the corpus does not
fit in one run.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEYS = ("A", "B", "C")
FIELDS = ("id", "stem", "options", "correct", "rationales",
          "primary_los", "reading_id", "needs_calculator", "difficulty")


VERDICT_OPENER = re.compile(
    r"^\s*(?:Correct|Incorrect)\b[.:,!]?\s*(?:[-–—]\s*)?|\s*Full statement:\s*")


def blind(q: dict) -> dict:
    """The rewriter's copy: no stored key, and no rationale that names one."""
    out = {k: v for k, v in q.items() if k != "correct"}
    rationales = out.get("rationales")
    if isinstance(rationales, dict):
        out["rationales"] = {
            k: VERDICT_OPENER.sub("", v or "").strip() for k, v in rationales.items()
        }
    return out


def reading_number(path: str) -> int:
    m = re.search(r"los_drills_r(\d+)\.json$", path)
    return int(m.group(1)) if m else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--readings", default="", help="comma list like r17,r20; default all")
    ap.add_argument("--batch", type=int, default=10)
    ap.add_argument("--group", type=int, default=0)
    ap.add_argument("--groups", type=int, default=1)
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(ROOT, "CFAL3/Resources/los_drills_r*.json")),
                   key=reading_number)
    if args.readings:
        want = {r.strip() for r in args.readings.split(",") if r.strip()}
        files = [f for f in files if f"r{reading_number(f)}" in want]
    if args.groups > 1:
        files = [f for i, f in enumerate(files) if i % args.groups == args.group]

    os.makedirs(args.out, exist_ok=True)
    questions = []
    for path in files:
        data = json.load(open(path))
        for drill in data.get("drills", []):
            for q in drill.get("questions", []):
                if isinstance(q.get("options"), dict) and q.get("correct") in KEYS:
                    questions.append({k: q[k] for k in FIELDS if k in q})

    src = os.path.join(args.out, "source.json")
    with open(src, "w") as fh:
        json.dump(questions, fh, indent=2, ensure_ascii=False)

    blind_path = os.path.join(args.out, "source_blind.json")
    with open(blind_path, "w") as fh:
        json.dump([blind(q) for q in questions], fh, indent=2, ensure_ascii=False)

    # The workflow args carry no question ids at all. Agents are pointed at a
    # slice of source.json by POSITION, and the answer letters ride along as
    # one string aligned to that same array. Five hundred ids in an args blob
    # is payload that has to be transcribed by hand into the tool call, and
    # every character of it is a chance to get one wrong.
    payload = {
        "source": src,
        "blind": blind_path,
        "batch": args.batch,
        "count": len(questions),
        "keystr": "".join(q["correct"] for q in questions),
    }
    print(json.dumps(payload), flush=True)
    batches = -(-len(questions) // args.batch)
    print(f"# {len(files)} file(s), {len(questions)} questions, {batches} batches "
          f"-> up to {batches * 6} agents", file=__import__("sys").stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
