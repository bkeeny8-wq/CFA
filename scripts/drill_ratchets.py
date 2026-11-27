#!/usr/bin/env python3
"""Recompute every ratchet in QuestionBankIntegrityTests.swift, in Python.

The Swift test is the one that runs in CI, but it needs Xcode. This mirrors
its logic exactly -- same regexes, same sentence counting, same ASCII-only
digit test -- so the new ceilings can be read off a container with no Swift.
"""
import collections
import glob
import json
import os
import re

ROOT = "/home/user/CFA"
KEYS = ("A", "B", "C")

BOILERPLATE = re.compile(
    r"That specification would be used as-is"
    r"|That approach would be applied without further adjustment", re.I)
TAIL = re.compile(
    r"(namely\s+.+\bas a complete account of|\bas the .{2,80} reading\.?$"
    r"|\bas a complete reading of "
    r"|every implication that reading is usually thought to carry"
    r"|[—–-]\s*as (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?$"
    r"|\.\s+As (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?$"
    r"|,\s+as (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?$)", re.I)
ABBREV = re.compile(r"\b(?:[A-Za-z]\.){2,}|\b(?:e\.g|i\.e|vs|No|Mr|Ms|Dr|St|Inc|Co)\.")
SENTENCE_BREAK = re.compile(r"[.!?]\s+")
BARE_QUALIFIER = re.compile(
    r"\b(?:most likely|least likely|closest to|best describes?|best characteri[sz]ed"
    r"|most appropriate|best explains?|most accurate|least accurate|best supported)"
    r"\s*:?\s*$", re.I)
AUXILIARY = re.compile(
    r"\b(?:is|are|was|were|will|would|should|does|do|did|has|have|had|can|could|may"
    r"|might|must|be|been|being"
    r"|which|what|who|whose|the|if|when|using|based|given|after|for|under|accord\w*"
    r"|compared|relative)\b", re.I)
DANGLING = re.compile(
    r"\b(?:Example|Exhibit|Table|Figure|Section|Equation|Case)\s+\d+"
    r"|according to the (?:CFA Institute )?curriculum"
    r"|the curriculum (?:states|says|notes|identifies|warns)", re.I)
QUALIFIER = re.compile(
    r"\b(?:most likely|least likely|closest to|best describes?"
    r"|best characteri[sz]ed|most appropriate|best explains?|most accurate"
    r"|least accurate|best supported)\b", re.I)
FINITE_VERB = re.compile(
    r"\b(?:is|are|was|were|will|would|should|does|do|did|has|have"
    r"|had|can|could|may|which|what|who|the|if|when|using|based|given|after"
    r"|for|under|accord\w*)\b", re.I)


def sentences(text):
    masked = ABBREV.sub("@", text or "")
    parts = SENTENCE_BREAK.sub("\x01", masked).split("\x01")
    return len([p for p in parts if p.strip()])


def has_digit(text):
    return any(c.isdigit() and c.isascii() for c in (text or ""))


def load():
    items = []
    for path in sorted(glob.glob(os.path.join(ROOT, "CFAL3/Resources/los_drills_r*.json"))):
        data = json.load(open(path))
        for group in data.get("drills", []):
            keys = []
            for q in group.get("questions", []):
                o, c = q.get("options"), q.get("correct")
                if isinstance(o, dict) and len(o) == 3 and c in o:
                    items.append({"id": q["id"], "stem": q.get("stem") or "",
                                  "options": o, "correct": c})
                    keys.append(c)
            if keys:
                yield_groups.append(keys)
    return items


yield_groups = []
items = load()
n = len(items)
print(f"{n} drills in {len(yield_groups)} LOS groups\n")

# --- testDrillOptionLengthDoesNotPredictTheAnswer -------------------------
uniq_long = uniq_short = tails = bp_distract = bp_keys = lone_lower = lone_upper = 0
keycount = collections.Counter()
for it in items:
    o, c = it["options"], it["correct"]
    keycount[c] += 1
    lower = [k for k, v in o.items() if v[:1].islower()]
    if len(lower) == 1 and lower[0] == c:
        lone_lower += 1
    upper = [k for k, v in o.items() if v[:1].isupper()]
    if len(upper) == 1 and upper[0] == c:
        lone_upper += 1
    klen = len(o[c])
    other = [len(v) for k, v in o.items() if k != c]
    if klen > max(other):
        uniq_long += 1
    if klen < min(other):
        uniq_short += 1
    for k, v in o.items():
        padded = BOILERPLATE.search(v) is not None
        if k == c:
            bp_keys += padded
            continue
        if TAIL.search(v):
            tails += 1
        bp_distract += padded

print("length-does-not-predict")
print(f"  longest share   {uniq_long / n:.4f}  ({uniq_long})")
print(f"  shortest share  {uniq_short / n:.4f}  ({uniq_short})")
print(f"  middle share    {1 - uniq_long / n - uniq_short / n:.4f}")
print(f"  boilerplateDistractors {bp_distract}   (must be 0)")
print(f"  distractorTails        {tails}   (must be 0)")
print(f"  boilerplateOnKeys      {bp_keys}   (must be 0)")
print(f"  loneLowercaseIsKey     {lone_lower}   (must be 0)")
print(f"  loneUppercaseIsKey     {lone_upper}   (must be 0)")
print(f"  keys {dict(keycount)}\n")

# --- testDrillStyleMatchesTheCaseBank ------------------------------------
counts = collections.Counter()
for it in items:
    vals = list(it["options"].values())
    if any(BOILERPLATE.search(v) for v in vals):
        counts["boilerplate"] += 1
    if any(sentences(v) > 1 for v in vals):
        counts["multi_sentence"] += 1
    if any("=" in v for v in vals):
        counts["equation"] += 1
    if any(len(v) > 120 for v in vals):
        counts["too_long"] += 1
    if len({has_digit(v) for v in vals}) > 1:
        counts["mixed_option_types"] += 1
    stem = it["stem"]
    if DANGLING.search(stem):
        counts["dangling_reference"] += 1
    if BARE_QUALIFIER.search(stem) and not AUXILIARY.search(stem):
        counts["heading_stem"] += 1
    if len({v[:1].islower() for v in vals if v}) > 1:
        counts["inconsistent_case"] += 1

old = {"boilerplate": 0, "multi_sentence": 1, "equation": 0,
       "too_long": 0, "mixed_option_types": 18, "dangling_reference": 0,
       "heading_stem": 40, "inconsistent_case": 9}
print("house-style ceilings")
for rule in sorted(old):
    print(f"  {rule:20} {counts[rule]:6}   was {old[rule]}")
print()

# --- testDrillsCannotBeAnsweredWithoutReadingThem ------------------------
def by_length(it, pool):
    return max(pool, key=lambda k: len(it["options"][k])) if pool else it["correct"]


def longest(it):
    return by_length(it, list(it["options"]))


def shortest(it):
    return min(it["options"], key=lambda k: len(it["options"][k]))


def middle(it):
    return sorted(it["options"], key=lambda k: -len(it["options"][k]))[1]


def drop_multi(it):
    live = [k for k, v in it["options"].items() if sentences(v) == 1]
    if len(live) == 1:
        return live[0]
    return by_length(it, live or list(it["options"]))


def drop_bp(it):
    live = [k for k, v in it["options"].items() if not BOILERPLATE.search(v)]
    if len(live) == 1:
        return live[0]
    return by_length(it, live or list(it["options"]))


def odd_type(it):
    num = [k for k, v in it["options"].items() if has_digit(v)]
    if len(num) == 1:
        return num[0]
    prose = [k for k, v in it["options"].items() if not has_digit(v)]
    if len(prose) == 1:
        return prose[0]
    return by_length(it, list(it["options"]))


strategies = {
    "take the longest option": longest,
    "take the shortest option": shortest,
    "take the middle-length option": middle,
    "drop the two-sentence option, then longest": drop_multi,
    "drop the boilerplate option, then longest": drop_bp,
    "take the odd option out by type": odd_type,
}
print("surface cues (ceiling 0.44, floor 0.20)")
best = 0.0
for name, pick in sorted(strategies.items()):
    s = sum(pick(it) == it["correct"] for it in items) / n
    best = max(best, s)
    flag = "  <-- FLOOR" if s <= 0.22 else ""
    print(f"  {s:.4f}  {name}{flag}")
print(f"  best {best:.4f}\n")

# --- testDrillAnswerPositionIsNotASequence -------------------------------
fwd = {"A": "B", "B": "C", "C": "A"}
trans = collections.Counter()
pairs = 0
longest_run = 1
for keys in yield_groups:
    run = 1
    for prev, nxt in zip(keys, keys[1:]):
        pairs += 1
        if prev == nxt:
            trans["same"] += 1
            run += 1
            longest_run = max(longest_run, run)
        else:
            run = 1
            trans["forward" if fwd[prev] == nxt else "backward"] += 1
print("answer position (band 0.20-0.47)")
for name in sorted(trans):
    print(f"  {trans[name] / pairs:.4f}  {name}")
print(f"  pairs {pairs}, longestRun {longest_run}")
