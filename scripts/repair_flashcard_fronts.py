#!/usr/bin/env python3
"""Strip answer text that the splitting passes left on flashcard fronts.

When a long back was cut into atoms, the splitters labelled each atom by
summarising the atom's own back — so the front of a bullet atom opened with
the first words of its answer and the card read as pre-revealed. A few fronts
stacked two such labels and quoted the answer twice.

The prompt itself is always the first block of the front and is untouched;
only the trailing label is rewritten, to the positional "part n of m" the
non-bullet atoms already used. Ids and backs are left alone so existing SRS
progress still matches.

Usage:
    python3 scripts/repair_flashcard_fronts.py --dry-run
    python3 scripts/repair_flashcard_fronts.py
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "CFAL3/Resources/flashcards.json")

ATOM_SUFFIX = re.compile(r"(_p\d+)+$")
PART_LABEL = re.compile(r"^part \d+ of \d+$")


def base_id(card_id: str) -> str:
    return ATOM_SUFFIX.sub("", card_id)


def prompt(front: str) -> str:
    return front.split("\n\n", 1)[0].rstrip()


def label(position: int, total: int) -> str:
    return f"part {position} of {total}"


def repair(cards: list[dict]) -> tuple[list[dict], dict]:
    """Atoms of one source card are contiguous in file order, so a running
    count over that order gives each atom its position."""
    totals: dict[str, int] = {}
    for card in cards:
        totals[base_id(card["id"])] = totals.get(base_id(card["id"]), 0) + 1

    leaking = set(leaks(cards))
    seen: dict[str, int] = {}
    out: list[dict] = []
    tally = {"leaked": 0, "misnumbered": 0, "unchanged": 0}
    for card in cards:
        base = base_id(card["id"])
        seen[base] = seen.get(base, 0) + 1
        total = totals[base]

        head = prompt(card["front"])
        new_front = head if total == 1 else f"{head}\n\n{label(seen[base], total)}"

        if new_front == card["front"]:
            tally["unchanged"] += 1
        elif card["id"] in leaking:
            tally["leaked"] += 1
        else:
            tally["misnumbered"] += 1

        fixed = dict(card)
        fixed["front"] = new_front
        out.append(fixed)
    return out, tally


def leaks(cards: list[dict]) -> list[str]:
    """A front must say nothing about its own answer beyond the prompt."""
    bad = []
    for card in cards:
        blocks = card["front"].split("\n\n")[1:]
        for block in blocks:
            if not PART_LABEL.match(block.strip()):
                bad.append(card["id"])
                break
    return bad


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    bundle = json.load(open(PATH, encoding="utf-8"))
    cards = bundle["cards"]
    before = len(leaks(cards))
    fixed, tally = repair(cards)
    after = leaks(fixed)

    print(f"cards {len(cards)}")
    print(f"answer text on the front: {before} -> {len(after)}")
    print(f"relabelled leaks {tally['leaked']}, renumbered {tally['misnumbered']}, "
          f"unchanged {tally['unchanged']}")

    if after:
        print("still leaking: " + ", ".join(after[:5]), file=sys.stderr)
        return 1
    if [c["id"] for c in fixed] != [c["id"] for c in cards]:
        print("ids moved", file=sys.stderr)
        return 1
    if [c["back"] for c in fixed] != [c["back"] for c in cards]:
        print("backs changed", file=sys.stderr)
        return 1
    if args.dry_run:
        print("dry-run; not writing")
        return 0

    bundle["cards"] = fixed
    with open(PATH, "w", encoding="utf-8") as fh:
        json.dump(bundle, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
