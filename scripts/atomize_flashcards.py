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


def stem_front(front: str) -> str:
    """Drop prior 'part n of m' suffixes so re-splits do not stack."""
    return front.split("\n\n", 1)[0].rstrip()


def pack_pieces(parts: list[str], target_words: int = 45, min_words: int = 12) -> list[str]:
    out: list[str] = []
    buf = ""
    for part in parts:
        piece = part.strip()
        if not piece:
            continue
        candidate = f"{buf} {piece}".strip() if buf else piece
        if (
            buf
            and len(buf.split()) >= min_words
            and len(candidate.split()) > target_words
        ):
            out.append(buf)
            buf = piece
        else:
            buf = candidate
    if buf:
        if out and len(buf.split()) < min_words:
            out[-1] = f"{out[-1]} {buf}".strip()
        else:
            out.append(buf)
    return out


def clause_chunks(text: str, target_words: int = 45) -> list[str]:
    """Last-resort split for remaining long single-block backs."""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if len(lines) >= 2:
        packed = pack_pieces(lines, target_words)
        if len(packed) >= 2:
            return packed

    numbered = [n.strip() for n in re.split(r"(?m)(?=^\d+\.\s+)", text.strip()) if n.strip()]
    if len(numbered) >= 2:
        return numbered

    semi = [p.strip() for p in re.split(r";\s+", text) if p.strip()]
    if len(semi) >= 3:
        packed = pack_pieces(semi, target_words)
        if len(packed) >= 2:
            return packed

    dash = [p.strip() for p in re.split(r"\s+—\s+", text) if p.strip()]
    if len(dash) >= 2:
        packed = pack_pieces(dash, target_words)
        if len(packed) >= 2:
            return packed

    sents = sentence_chunks(text, target=max(120, target_words * 5))
    if len(sents) >= 2:
        return sents

    words = text.split()
    if len(words) <= target_words:
        return [text]
    return [
        " ".join(words[i : i + target_words])
        for i in range(0, len(words), target_words)
        if words[i : i + target_words]
    ]


def merge_short(pieces: list[str], min_words: int = 8, max_words: int = 49) -> list[str]:
    """Glue orphan labels ('2.', 'Weakness') onto a neighbor, but never
    rebuild a back longer than max_words."""
    if len(pieces) < 2:
        return pieces
    out: list[str] = []
    for piece in pieces:
        text = piece.strip()
        if not text:
            continue
        if out and len(text.split()) < min_words:
            combined = f"{out[-1]} {text}".strip()
            if len(combined.split()) <= max_words:
                out[-1] = combined
                continue
        out.append(text)
    if len(out) >= 2 and len(out[-1].split()) < min_words:
        combined = f"{out[-2]} {out[-1]}".strip()
        if len(combined.split()) <= max_words:
            out[-2] = combined
            out.pop()
    if len(out) >= 2 and len(out[0].split()) < min_words:
        combined = f"{out[0]} {out[1]}".strip()
        if len(combined.split()) <= max_words:
            out[1] = combined
            out.pop(0)
    return out


def word_windows(text: str, target: int = 45) -> list[str]:
    words = text.split()
    if len(words) <= target:
        return [text]
    return [
        " ".join(words[i : i + target])
        for i in range(0, len(words), target)
        if words[i : i + target]
    ]


def next_atom_id(base: str, used: set[str]) -> str:
    n = 2
    while True:
        candidate = f"{base}_p{n}"
        if candidate not in used:
            return candidate
        n += 1


def atomize(card: dict, used: set[str]) -> list[dict]:
    preamble, items = bullets(card["back"])
    words = len(card["back"].split())
    pieces: list[str]
    if len(items) >= 2:
        pieces = items
        if preamble and len(preamble.split()) >= 20:
            pieces = [preamble] + items
    else:
        paras = paragraphs(card["back"])
        pipe_parts = [p.strip() for p in re.split(r"\s+\|\s+", card["back"]) if p.strip()]
        numbered = [
            n.strip()
            for n in re.split(r"(?m)(?=^\d+\.\s+)", card["back"].strip())
            if n.strip()
        ]
        if len(paras) >= 2 and words > 50:
            pieces = paras
        elif len(pipe_parts) >= 2 and words > 50:
            pieces = pipe_parts
        elif len(numbered) >= 2 and words > 50:
            pieces = numbered
        elif words > 49:
            pieces = clause_chunks(card["back"])
        else:
            return [card]

    if len(pieces) < 2:
        return [card]
    pieces = merge_short(pieces)
    exploded: list[str] = []
    for piece in pieces:
        exploded.extend(word_windows(piece, 45) if len(piece.split()) > 49 else [piece])
    pieces = merge_short(exploded)
    if len(pieces) < 2:
        return [card]

    atoms = []
    n = len(pieces)
    claimed = set(used)
    claimed.add(card["id"])
    front = stem_front(card["front"])
    for i, piece in enumerate(pieces):
        atom = dict(card)
        if i == 0:
            atom["id"] = card["id"]
        else:
            atom["id"] = next_atom_id(card["id"], claimed)
            claimed.add(atom["id"])
        head = label(piece) if piece.startswith("•") else f"part {i + 1} of {n}"
        atom["front"] = f"{front}\n\n{head}"
        atom["back"] = piece
        atoms.append(atom)
    return atoms


def collapse_junk(cards: list[dict], protected: set[str], min_words: int = 3) -> list[dict]:
    """Fold leftover 1–2 word atoms created in this run into the previous
    sibling. Existing ids stay so progress rows still match."""
    out: list[dict] = []
    for card in cards:
        tiny = len(card["back"].split()) < min_words
        if tiny and out and card["id"] not in protected:
            prev = dict(out[-1])
            prev["back"] = f"{prev['back']} {card['back']}".strip()
            out[-1] = prev
            continue
        out.append(card)
    return out
    words = [len(c["back"].split()) for c in cards]
    words.sort()
    n = len(words)
    return {
        "n": n,
        "median_words": words[n // 2] if words else 0,
        "p90_words": words[int(n * 0.9)] if words else 0,
        "max_words": words[-1] if words else 0,
    }


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
    out = list(bundle["cards"])
    split = 0
    # Repeat until remaining longs stop splitting. A first pass can emit a
    # still-long piece that needs its own cut.
    while True:
        used = {c["id"] for c in out}
        nxt: list[dict] = []
        round_split = 0
        for card in out:
            atoms = atomize(card, used)
            if len(atoms) > 1:
                round_split += 1
            nxt.extend(atoms)
            used.update(a["id"] for a in atoms[1:])
        if round_split == 0:
            break
        split += round_split
        out = nxt
    out = collapse_junk(out, {c["id"] for c in bundle["cards"]})
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
    generated = bundle.get("generated_by") or ""
    if "atomized to one idea per card" not in generated:
        generated = (generated + "; atomized to one idea per card").strip("; ")
    bundle["generated_by"] = generated
    with open(PATH, "w", encoding="utf-8") as fh:
        json.dump(bundle, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
