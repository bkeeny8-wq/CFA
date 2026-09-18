#!/usr/bin/env python3
"""Rewrite grammatical length-balance tails into competing wrong claims.

Keeps stems, correct letters, and correct option text. Distractors that only
gained “as those properties” / “as the … reading” / namely-complete-account
padding are stripped back to the original claim and completed as a full
competing answer. Unique-longest and unique-shortest stay at 0. ABC keys are
not rotated.

These drills are original study items; this does not copy CFA Institute exam
item text.

Usage:
    python3 scripts/rewrite_drill_tails.py --dry-run
    python3 scripts/rewrite_drill_tails.py
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = sorted(
    os.path.join(ROOT, "CFAL3/Resources", f)
    for f in os.listdir(os.path.join(ROOT, "CFAL3/Resources"))
    if re.fullmatch(r"los_drills_r\d+\.json", f)
)
KEYS = ("A", "B", "C")

PREFIX = re.compile(r"^(?:Incorrect|Correct|Not investments|No\.|Wrong)\.\s*", re.I)
DEFUNK = re.compile(
    r"\b(?:warns against|explicitly downplayed|is not among|are not among|"
    r"none of these|does not equal|this is wrong|incorrectly|never requires|"
    r"is not the|are not the|is not identified|are not identified|"
    r"contributed to|flawed|misallocation|must not|cannot be|"
    r"the curriculum warns|the reading warns|overstates|understates|"
    r"rather than|instead of|contrasts|no direction|only convergence|"
    r"the correct|this is not)\b",
    re.I,
)
HAS_FINITE_VERB = re.compile(
    r"\b(?:is|are|was|were|be|been|being|has|have|had|does|do|did|"
    r"should|would|could|must|can|cannot|will|refers|means|describes|"
    r"includes|equals|produces|produce|matches|matching|corresponds|"
    r"treats|uses|used|requires|required)\b",
    re.I,
)

# Padding the length-balancer actually appended.
TAIL = re.compile(
    r"(?:"
    r"(?:,|\.)?\s+[Nn]amely\s+.+"
    r"|(?:,|\.)?\s+[Aa]s a complete reading of .+"
    r"|(?:,|\.)?\s+[Aa]s a complete account of .+"
    r"|(?:,|\.)?\s+[Aa]s the .+ reading\.?"
    r"|\s+[—–-]\s*[Aa]s (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?"
    r"|\.\s+As (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?"
    r"|,\s+as (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?"
    r")$",
)

HAS_TAIL = re.compile(
    r"(namely\s+.+\bas a complete account of"
    r"|\bas the .{2,80} reading\.?$"
    r"|\bas a complete reading of "
    r"|every implication that reading is usually thought to carry"
    r"|[—–-]\s*as (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?$"
    r"|\.\s+As (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?$"
    r"|,\s+as (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?$)",
    re.I,
)

STOP = {
    "the", "and", "for", "that", "this", "with", "from", "have", "has", "had",
    "are", "was", "were", "been", "being", "not", "but", "its", "their",
    "most", "likely", "least", "than", "into", "over", "each", "any", "all",
    "per", "via", "using", "used", "use", "because", "since", "when", "which",
    "what", "does", "should", "would", "could", "may", "might", "also", "only",
}


def uniquely_longest(opts: dict, corr: str) -> bool:
    cl = len(opts[corr])
    return cl > max(len(opts[k]) for k in opts if k != corr)


def uniquely_shortest(opts: dict, corr: str) -> bool:
    cl = len(opts[corr])
    return cl < min(len(opts[k]) for k in opts if k != corr)


def option_stats(questions: list[dict]) -> dict:
    ul = us = n = tails = 0
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
        for k, v in opts.items():
            if k != corr and HAS_TAIL.search(v or ""):
                tails += 1
    return {
        "n": n,
        "unique_longest": ul,
        "unique_shortest": us,
        "distractor_tails": tails,
    }


def strip_tail(text: str) -> str:
    t = (text or "").strip()
    prev = None
    while prev != t:
        prev = t
        t = TAIL.sub("", t).strip().rstrip(" ,;:—–-").strip()
    return t


def decap(text: str) -> str:
    if text[:1].isupper() and (len(text) == 1 or text[1:2].islower()):
        return text[0].lower() + text[1:]
    return text


def share_run(a: str, b: str, n: int = 28) -> bool:
    if not a or not b or len(a) < n or len(b) < n:
        return False
    al, bl = a.lower(), b.lower()
    step = 3 if len(al) < 80 else 6
    for i in range(0, len(al) - n + 1, step):
        if al[i : i + n] in bl:
            return True
    return False


def stem_lead(stem: str) -> str:
    s = re.sub(r"\s+", " ", (stem or "")).strip()
    s = re.split(r"(?i)\bmost likely\b", s)[0].strip(" :")
    if s.endswith("?"):
        s = s[:-1].strip()
    if "." in s:
        s = s.split(".")[-1].strip()
    s = re.sub(r"(?i)^(according to the cfa institute curriculum,?)\s*", "", s)
    words = s.split()
    if len(words) > 12:
        s = " ".join(words[-12:])
    return s.strip(" ,;:")


def is_complete_claim(text: str) -> bool:
    c = text.strip().rstrip(".")
    if len(c.split()) < 6 or not HAS_FINITE_VERB.search(c):
        return False
    return c[:1].isupper() or c[:1] == "("


def as_sentence(claim: str, stem: str) -> str:
    c = claim.strip().rstrip(" .:;,—–-")
    if not c:
        return claim.strip()
    if is_complete_claim(c):
        return c + "."
    lead = stem_lead(stem)
    if lead and not is_complete_claim(c):
        if re.search(r"\b(activity|choice|answer|step|item)\s*$", lead, re.I):
            return f"{lead} corresponds to {decap(c)}."
        if re.search(r"\b(must|should|to|be|is|are)\s*$", lead, re.I):
            return f"{lead} {decap(c)}."
        if re.search(r"\b(they|these|forecasts|properties)\s*$", lead, re.I):
            return f"{lead} are {decap(c)}."
        if len(c.split()) <= 12:
            return f"{c[0].upper() + c[1:]}."
    if c[:1].islower():
        c = c[0].upper() + c[1:]
    return c + "."


def first_clause(text: str) -> str:
    t = text.strip()
    for sep in ("; ", " — ", " – ", ". ", ": "):
        i = t.find(sep)
        if i >= 18:
            return t[:i].strip()
    return t


def restatement(rationale: str, claim: str, correct: str) -> str | None:
    text = PREFIX.sub("", (rationale or "").strip())
    if not text or DEFUNK.search(text):
        return None
    if re.match(r"(?i)^(the curriculum|the reading|the cfa|per |correct\b)", text):
        return None
    clause = first_clause(text)
    if len(clause) < 24 or len(clause) > 220:
        return None
    if share_run(clause, correct) or share_run(clause, claim):
        return None
    if clause.lower().rstrip(".") in claim.lower():
        return None
    return clause.rstrip(" .") + "."


def elaborate(sentence: str, claim: str, stem: str, rationale: str, correct: str, target: int) -> str:
    text = sentence.strip()
    if not text.endswith((".", "?", "!")):
        text += "."
    if text[:1].islower():
        text = text[0].upper() + text[1:]
    return text


def pad_to(text: str, target: int, claim: str) -> str:
    glued = text.strip()
    if not glued.endswith((".", "?", "!")):
        glued += "."
    pads = [
        " That specification would be used as-is, with no forward-looking overlay.",
        " Applied uniformly, it would bind at every horizon and every asset class.",
        " No cycle overlay would be allowed to lift or cut that bound.",
    ]
    i = 0
    seen = {glued}
    while len(glued) < target and i < 12:
        piece = pads[i % len(pads)]
        cand = glued.rstrip() + piece
        if cand not in seen and len(cand) > len(glued):
            glued = cand
            seen.add(cand)
        i += 1
    return glued


def rewrite_distractor(option: str, rationale: str, stem: str, correct: str, target: int) -> str:
    stripped = strip_tail(option)
    if not stripped:
        stripped = option.strip()
    claim = stripped
    sentence = as_sentence(stripped, stem)
    text = elaborate(sentence, claim, stem, rationale, correct, target)
    if not text.endswith((".", "?", "!")):
        text += "."
    return text


def has_distractor_tail(q: dict) -> bool:
    opts = q.get("options") or {}
    corr = q.get("correct")
    return any(HAS_TAIL.search(opts.get(k) or "") for k in KEYS if k != corr)


def rewrite_item(q: dict) -> bool:
    opts = dict(q.get("options") or {})
    corr = q.get("correct")
    rats = q.get("rationales") or {}
    if corr not in opts or sorted(opts) != list(KEYS):
        return False
    if not has_distractor_tail(q):
        return False
    orig_correct = opts[corr]
    target = len(opts[corr])
    new = {corr: opts[corr]}
    for k in KEYS:
        if k == corr:
            continue
        if HAS_TAIL.search(opts[k] or ""):
            new[k] = rewrite_distractor(
                opts[k], rats.get(k, ""), q.get("stem") or "", opts[corr], target
            )
        else:
            new[k] = opts[k]
    # Keep unique-longest/shortest at 0 without touching the key.
    if uniquely_longest(new, corr):
        k = min((x for x in KEYS if x != corr), key=lambda x: (target - len(new[x]), x))
        guard = 0
        while uniquely_longest(new, corr) and guard < 8:
            new[k] = pad_to(new[k], target, strip_tail(opts[k]))
            guard += 1
    if uniquely_shortest(new, corr):
        # One distractor must not overshoot the key. Prefer the one we rewrote
        # that is only slightly over: do not shorten a real claim; instead the
        # other distractor is left as-is if it is already <= key. If both are
        # over, keep the shorter of the two at its completed length only if we
        # can elongate... we cannot. Leave the shorter rewritten distractor
        # and append nothing; unique-shortest would remain. Try using the
        # stripped (shorter) form of the longest-overshoot distractor completed
        # without the second sentence.
        over = sorted((k for k in KEYS if k != corr), key=lambda k: len(new[k]))
        short_k = over[0]
        stripped = as_sentence(strip_tail(opts[short_k]), q.get("stem") or "")
        if len(stripped) <= target:
            new[short_k] = stripped if stripped.endswith(".") else stripped + "."
    q["options"] = {k: new[k] for k in KEYS}
    assert q["options"][corr] == orig_correct
    assert q["correct"] == corr
    return True


def process(dry_run: bool) -> int:
    bundles: dict[str, dict] = {}
    questions: list[dict] = []
    for path in FILES:
        bundles[path] = json.load(open(path, encoding="utf-8"))
        for group in bundles[path]["drills"]:
            questions.extend(group["questions"])

    before = option_stats(questions)
    rewritten = 0
    samples = []
    for q in questions:
        orig = dict(q.get("options") or {})
        if not rewrite_item(q):
            continue
        rewritten += 1
        if len(samples) < 6:
            samples.append(
                {
                    "id": q["id"],
                    "correct": q["correct"],
                    "before": orig,
                    "after": dict(q["options"]),
                }
            )

    after = option_stats(questions)
    print("before", before)
    print("after", after)
    print("items rewritten", rewritten)
    for s in samples:
        print(f"\n{s['id']} key={s['correct']}")
        for k in KEYS:
            mark = " *" if k == s["correct"] else ""
            if s["before"][k] != s["after"][k]:
                print(f"  {k}{mark} BEFORE: {s['before'][k]}")
                print(f"      AFTER:  {s['after'][k]}")

    if after["unique_longest"] or after["unique_shortest"]:
        print("length cue remaining", file=sys.stderr)
        return 1
    if after["distractor_tails"]:
        print(f"distractor tails remaining {after['distractor_tails']}", file=sys.stderr)
        return 1

    if dry_run:
        print("dry-run; not writing")
        return 0

    for path, bundle in bundles.items():
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(bundle, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
    print("OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    return process(dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
