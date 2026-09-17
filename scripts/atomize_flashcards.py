#!/usr/bin/env python3
"""Split bundled flashcard backs into one-idea cards.

Original study cards (not CFA Institute exam items). Long backs with
bullet lists become one card per bullet so SRS ratings mean something.
The original id is kept for the first atom so existing progress still
matches. Notes keep the long form.

Usage:
    python3 scripts/atomize_flashcards.py --dry-run
    python3 scripts/atomize_flashcards.py
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "CFAL3/Resources/flashcards.json")

BULLET = re.compile(r"(?m)^[ \t]*[•\-]\s+")


def bullets(text: str) -> tuple[str, list[str]]:
    chunks = re.split(r"(?m)(?=^[ \t]*[•\-]\s+)", text)
    preamble: list[str] = []
    items: list[str] = []
    for raw in chunks:
        chunk = raw.strip()
        if not chunk:
            continue
        if BULLET.match(chunk):
            items.append(re.sub(r"^[ \t]*[•\-]\s+", "• ", chunk).strip())
        else:
            preamble.append(chunk)
    return "\n\n".join(preamble).strip(), items


def label(bullet: str) -> str:
    body = re.sub(r"^•\s*", "", bullet).strip()
    if ":" in body:
        head = body.split(":", 1)[0].strip()
        if 2 <= len(head.split()) <= 12:
            return head
    words = body.split()
    return " ".join(words[:8]).rstrip(".,;")


def sentence_chunks(text: str, target: int = 280) -> list[str]:
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    out: list[str] = []
    buf = ""
    for part in parts:
        if not part:
            continue
        if buf and len(buf) + 1 + len(part) > target:
            out.append(buf.strip())
            buf = part
        else:
            buf = f"{buf} {part}".strip()
    if buf:
        out.append(buf.strip())
    return [c for c in out if c]


def paragraphs(text: str) -> list[str]:
    return [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]


def next_atom_id(base: str, used: set[str]) -> str:
    n = 2
    while True:
        candidate = f"{base}_p{n}"
        if candidate not in used:
            return candidate
        n += 1


def atomize(card: dict, used: set[str]) -> list[dict]:
    preamble, items = bullets(card["back"])
    pieces: list[str]
    if len(items) >= 2:
        pieces = items
        if preamble and len(preamble.split()) >= 20:
            pieces = [preamble] + items
    else:
        paras = paragraphs(card["back"])
        words = len(card["back"].split())
        pipe_parts = [p.strip() for p in re.split(r"\s+\|\s+", card["back"]) if p.strip()]
        if len(paras) >= 2 and words > 60:
            pieces = paras
        elif len(pipe_parts) >= 2 and words > 50:
            pieces = pipe_parts
        elif words > 90:
            chunks = sentence_chunks(card["back"], target=160)
            pieces = chunks if len(chunks) >= 2 else [card["back"]]
        else:
            return [card]

    if len(pieces) < 2:
        return [card]

    atoms = []
    n = len(pieces)
    claimed = set(used)
    claimed.add(card["id"])
    for i, piece in enumerate(pieces):
        atom = dict(card)
        if i == 0:
            atom["id"] = card["id"]
        else:
            atom["id"] = next_atom_id(card["id"], claimed)
            atom["formula"] = None
            claimed.add(atom["id"])
        head = label(piece) if piece.startswith("•") else f"part {i + 1} of {n}"
        atom["front"] = f"{card['front'].rstrip()}\n\n{head}"
        atom["back"] = piece
        atoms.append(atom)
    return atoms


def stats(cards: list[dict]) -> dict:
    words = [len(c["back"].split()) for c in cards]
    words.sort()
    n = len(words)
    return {
        "n": n,
        "median_words": words[n // 2] if words else 0,
        "p90_words": words[int(n * 0.9)] if words else 0,
        "max_words": words[-1] if words else 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    bundle = json.load(open(PATH, encoding="utf-8"))
    before = stats(bundle["cards"])
    out: list[dict] = []
    split = 0
    used = {c["id"] for c in bundle["cards"]}
    for card in bundle["cards"]:
        atoms = atomize(card, used)
        if len(atoms) > 1:
            split += 1
        out.extend(atoms)
        used.update(a["id"] for a in atoms[1:])
    after = stats(out)
    ids = [c["id"] for c in out]
    assert len(ids) == len(set(ids)), "duplicate ids"
    print("before", before)
    print("after", after)
    print("cards split", split)
    print("atoms", len(out) - len(bundle["cards"]), "new")

    if after["median_words"] > 80:
        print("median still long", file=sys.stderr)
        return 1
    if args.dry_run:
        print("dry-run; not writing")
        return 0

    bundle["cards"] = out
    bundle["generated_by"] = (
        (bundle.get("generated_by") or "") + "; atomized to one idea per card"
    ).strip("; ")
    with open(PATH, "w", encoding="utf-8") as fh:
        json.dump(bundle, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
