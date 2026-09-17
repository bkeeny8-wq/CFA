#!/usr/bin/env python3
"""Lengthen short LOS-drill distractors so the correct option is not uniquely
longest.

Keeps the stem, the correct key letter, and the correct option text. Expands
the closest shorter distractor (both only if needed) with a complete clause
that restates that wrong choice. Pieces come from the distractor's own claim
and from the non-contrast portion of its rationale. Does not copy CFA Institute
exam item text; these drills are original study items.

Usage:
    python3 scripts/balance_drill_option_length.py --dry-run
    python3 scripts/balance_drill_option_length.py
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = sorted(glob.glob(os.path.join(ROOT, "CFAL3/Resources/los_drills_r*.json")))
KEYS = ("A", "B", "C")

PREFIX = re.compile(
    r"^(?:Incorrect|Correct|Not investments|No\.|Wrong)\.\s*",
    re.I,
)
FULL_STMT = re.compile(r"^Full statement:\s*", re.I)
CONTRAST_SPLIT = re.compile(
    r"(?:,?\s+(?:not|rather than|instead of|as opposed to)\b|"
    r"\s+[\u2014\u2013]\s+not\b|"
    r";\s+not\b|"
    r"\s+the (?:correct|right) (?:answer|choice|option)\b)",
    re.I,
)
DEFUNK = re.compile(
    r"\b(?:warns against|explicitly downplayed|is not among|are not among|"
    r"none of these|does not equal|this is wrong|incorrectly|never requires|"
    r"is not the|are not the|is not identified|are not identified|"
    r"contributed to|flawed|misallocation|must not|cannot be|"
    r"the curriculum warns|the reading warns)\b",
    re.I,
)
WORD = re.compile(r"[A-Za-z][A-Za-z0-9\-]{2,}")
STOP = {
    "the", "and", "for", "that", "this", "with", "from", "have", "has", "had",
    "are", "was", "were", "been", "being", "not", "but", "its", "their",
    "most", "likely", "least", "than", "into", "over", "each", "any", "all",
    "per", "via", "using", "used", "use", "because", "since", "when", "which",
    "what", "does", "should", "would", "could", "may", "might", "also", "only",
    "more", "less", "such", "other", "both", "between", "among", "under",
    "after", "before", "during", "without", "within", "about", "against",
    "must", "shall", "will", "through", "onto", "same", "into", "then",
    "they", "them", "your", "their", "there", "here", "very", "just",
    "according", "following", "given", "based", "using", "including",
}


def option_stats(questions: list[dict]) -> dict:
    ul = us = n = 0
    for q in questions:
        opts = q.get("options") or {}
        corr = q.get("correct")
        if corr not in opts or len(opts) != 3:
            continue
        n += 1
        cl = len(opts[corr])
        others = [len(opts[k]) for k in opts if k != corr]
        if cl > max(others):
            ul += 1
        if cl < min(others):
            us += 1
    return {
        "n": n,
        "unique_longest": ul,
        "unique_shortest": us,
        "ul_rate": ul / n if n else 0,
        "us_rate": us / n if n else 0,
    }


def share_run(a: str, b: str, n: int = 28) -> bool:
    if not a or not b or len(a) < n or len(b) < n:
        return False
    al, bl = a.lower(), b.lower()
    step = 3 if len(al) < 80 else 6
    for i in range(0, len(al) - n + 1, step):
        if al[i : i + n] in bl:
            return True
    return False


def first_clause(text: str) -> str:
    t = text.strip()
    for sep in ("; ", " — ", " – ", ". ", ": "):
        i = t.find(sep)
        if i >= 18:
            return t[:i].strip()
    return t


def positive_clauses(rationale: str, correct: str, option: str) -> list[str]:
    text = PREFIX.sub("", (rationale or "").strip())
    text = FULL_STMT.sub("", text)
    m = CONTRAST_SPLIT.search(text)
    if m and m.start() >= 18:
        text = text[: m.start()].strip(" ,;:—–-")
    text = re.sub(r"\s+but does$", "", text, flags=re.I).strip()
    text = re.sub(r"\s+but$", "", text, flags=re.I).strip()
    if DEFUNK.search(text):
        return []
    if re.match(r"(?i)^(the curriculum|the reading|the cfa|per )", text):
        return []
    # Definitional only: the rationale should describe what this choice *is*,
    # not why a grader would reject it.
    if not re.search(
        r"(?i)^(this|that|it|they|the |[A-Z].{0,40}\b(is|are|describes|refers|means|equals|covers|classifies)\b)",
        text,
    ) and not any(
        text.lower().startswith(w) for w in option.lower().rstrip(".").split()[:4]
    ):
        return []
    if share_run(text, correct):
        return []
    if not text or text.lower().rstrip(".") in option.lower():
        return []
    out = []
    clause = first_clause(text)
    if 18 <= len(clause) <= 220 and not share_run(clause, correct):
        out.append(clause.rstrip(" .") + ("" if clause.endswith(".") else ""))
    if 18 <= len(text) <= 280 and text != clause and not share_run(text, correct):
        out.append(text.rstrip(" ."))
    # unique, shortest first
    seen = set()
    uniq = []
    for p in sorted(out, key=len):
        key = p.lower()
        if key not in seen:
            seen.add(key)
            uniq.append(p)
    return uniq


def decap(text: str) -> str:
    if text[:1].isupper() and (len(text) == 1 or text[1:2].islower()):
        return text[0].lower() + text[1:]
    return text


def stem_hook(stem: str) -> str:
    s = re.sub(r"\s+", " ", (stem or "")).strip()
    s = re.split(r"(?i)\bmost likely\b", s)[0].strip(" :")
    for sep in (". ", "? ", "; ", " — "):
        if sep in s:
            s = s.split(sep)[-1].strip()
    words = s.split()
    if len(words) > 14:
        s = " ".join(words[-14:])
    s = re.sub(r"(?i)\b(is|are|was|were|be|been|the|a|an|to|of|that|as|because|accordingly|occurred)\s*$", "", s).strip(" ,;:")
    s = re.sub(r"(?i)^(as|of|the|a|an)\s+", "", s).strip()
    if not s:
        return "the question as posed"
    return decap(s)


def stem_noun(stem: str) -> str:
    words = [
        w for w in re.findall(r"[A-Za-z]{4,}", stem or "") if w.lower() not in STOP
    ]
    preferred = [
        "properties", "property", "objective", "objectives", "types", "type",
        "approach", "approaches", "framework", "bias", "ratio", "spread",
        "plans", "plan", "activity", "result", "results", "method", "methods",
        "strategy", "strategies", "constraint", "constraints", "horizon",
        "forecasts", "forecast", "allocation", "return", "returns",
    ]
    lower = {w.lower(): w.lower() for w in words}
    for p in preferred:
        if p in lower:
            return p
    return words[-1].lower() if words else "result"


def claim_phrases(option: str, stem: str) -> list[str]:
    """Grammatical tails that keep the distractor's own wording in order."""
    claim = option.strip().rstrip(".")
    noun = stem_noun(stem)
    plural = noun.endswith("s") and not noun.endswith(("ss", "us", "is", "osis"))
    det = "those" if plural else "that"
    hook = stem_hook(stem)
    end_np = " ".join(claim.split()[-4:]).strip(" ,;:")
    end_np = re.sub(r"(?i)^(the|a|an)\s+", "", end_np)
    if end_np.lower().startswith("and "):
        end_np = " ".join(claim.split()[-5:]).strip(" ,;:")
        end_np = re.sub(r"(?i)^(the|a|an|and)\s+", "", end_np)
    phrases = [
        f"as {det} {noun}",
        f"as the {end_np} reading" if len(end_np.split()) >= 2 else "",
        f"as a complete reading of {hook}" if len(hook) >= 10 else "",
        (
            f"namely {decap(claim)}, as a complete account of {hook} "
            f"and of every implication that reading is usually thought to carry"
        ),
    ]
    seen = set()
    out = []
    for p in phrases:
        p = " ".join((p or "").split())
        if not p or p.lower() in claim.lower():
            continue
        k = p.lower()
        if k not in seen:
            seen.add(k)
            out.append(p)
    return out


def attach(option: str, piece: str) -> str:
    opt = option.strip()
    piece = piece.strip().rstrip(".")
    if not piece:
        return opt
    if piece.lower() in opt.lower():
        return opt
    if len(opt) < 55:
        glued = opt.rstrip(".") + " — " + decap(piece)
    elif opt.endswith("."):
        glued = opt + " " + piece[0].upper() + piece[1:]
    else:
        glued = opt.rstrip(".") + ", " + decap(piece)
    if not glued.endswith((".", "?", "!")):
        glued += "."
    return glued


def expand_to_target(
    option: str, rationale: str, correct: str, stem: str, target: int
) -> str:
    """Use the shortest complete piece that reaches `target`; stack only if none do."""
    if len(option) >= target:
        return option
    pieces = positive_clauses(rationale, correct, option) + claim_phrases(option, stem)
    reaching = []
    falling = []
    for piece in pieces:
        cand = attach(option, piece)
        if len(cand) <= len(option):
            continue
        if len(cand) >= target:
            reaching.append(cand)
        else:
            falling.append(cand)
    if reaching:
        return min(reaching, key=len)
    text = max(falling, key=len) if falling else option
    if len(text) >= target:
        return text
    for piece in pieces:
        if len(text) >= target:
            break
        cand = attach(text, piece)
        if len(cand) > len(text):
            text = cand
    return text


def uniquely_longest(opts: dict, corr: str) -> bool:
    cl = len(opts[corr])
    return cl > max(len(opts[k]) for k in opts if k != corr)


def uniquely_shortest(opts: dict, corr: str) -> bool:
    cl = len(opts[corr])
    return cl < min(len(opts[k]) for k in opts if k != corr)


def balance_item(q: dict) -> bool:
    opts = dict(q.get("options") or {})
    corr = q.get("correct")
    rats = q.get("rationales") or {}
    if corr not in opts or sorted(opts) != list(KEYS):
        return False
    if not uniquely_longest(opts, corr):
        return False
    target = len(opts[corr])
    distractors = sorted(
        (k for k in KEYS if k != corr),
        key=lambda k: (target - len(opts[k]), k),
    )
    # Closest-to-target first: smallest add often kills unique-longest.
    for key in distractors:
        if not uniquely_longest(opts, corr):
            break
        opts[key] = expand_to_target(
            opts[key], rats.get(key, ""), opts[corr], q.get("stem") or "", target
        )
    q["options"] = opts
    assert opts[corr] == q["options"][corr]
    return True


def process(dry_run: bool) -> int:
    bundles: dict[str, dict] = {}
    before_qs = []
    changed = 0
    still_ul = []
    samples = []
    large_gap = []

    for path in FILES:
        bundles[path] = json.load(open(path, encoding="utf-8"))

    for path, bundle in bundles.items():
        file_changed = False
        for group in bundle["drills"]:
            for q in group["questions"]:
                before_qs.append(
                    {"options": dict(q.get("options") or {}), "correct": q.get("correct")}
                )
                orig = dict(q.get("options") or {})
                orig_corr = q.get("correct")
                orig_gap = 0
                if orig_corr in orig and len(orig) == 3:
                    orig_gap = len(orig[orig_corr]) - max(
                        len(orig[k]) for k in orig if k != orig_corr
                    )
                if not balance_item(q):
                    continue
                file_changed = True
                changed += 1
                if uniquely_longest(q["options"], q["correct"]):
                    still_ul.append(
                        {"id": q["id"], "lens": {k: len(v) for k, v in q["options"].items()}}
                    )
                rec = {
                    "id": q["id"],
                    "correct": q["correct"],
                    "stem": (q.get("stem") or "")[:130].replace("\n", " "),
                    "before": orig,
                    "after": dict(q["options"]),
                    "gap": orig_gap,
                }
                if len(samples) < 8:
                    samples.append(rec)
                if orig_gap >= 80 and len(large_gap) < 4:
                    large_gap.append(rec)
        if file_changed and not dry_run:
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(bundle, fh, indent=2, ensure_ascii=False)
                fh.write("\n")

    after_qs = []
    for bundle in bundles.values():
        for group in bundle["drills"]:
            after_qs.extend(group["questions"])

    before = option_stats(before_qs)
    after = option_stats(after_qs)
    print("before", before)
    print("after", after)
    print("rewrote", changed, "still uniquely longest", len(still_ul))
    if still_ul:
        print("remaining:")
        for row in still_ul[:15]:
            print(" ", row["id"], row["lens"])
    print("\n--- samples ---")
    for s in samples:
        lb = {k: len(s["before"][k]) for k in KEYS}
        la = {k: len(s["after"][k]) for k in KEYS}
        print(f"\n{s['id']} correct={s['correct']} {lb} -> {la}")
        print(" ", s["stem"])
        for k in KEYS:
            mark = " *" if k == s["correct"] else ""
            if s["before"][k] != s["after"][k]:
                print(f"  {k}{mark} BEFORE: {s['before'][k]}")
                print(f"      AFTER:  {s['after'][k]}")
    print("\n--- large-gap samples ---")
    for s in large_gap:
        lb = {k: len(s["before"][k]) for k in KEYS}
        la = {k: len(s["after"][k]) for k in KEYS}
        print(f"\n{s['id']} correct={s['correct']} gap={s['gap']} {lb} -> {la}")
        print(" ", s["stem"])
        for k in KEYS:
            mark = " *" if k == s["correct"] else ""
            if s["before"][k] != s["after"][k]:
                print(f"  {k}{mark} BEFORE: {s['before'][k]}")
                print(f"      AFTER:  {s['after'][k]}")
            else:
                print(f"  {k}{mark} (unchanged) {s['after'][k][:160]}")

    if not dry_run:
        assert after["n"] == 2625, after
        assert after["ul_rate"] < 0.40, after
        assert after["us_rate"] < 0.40, after
        print("OK")
    return 0 if after["ul_rate"] < 0.40 and after["us_rate"] < 0.40 else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    return process(dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
