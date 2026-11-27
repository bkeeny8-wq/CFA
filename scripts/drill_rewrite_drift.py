#!/usr/bin/env python3
"""Find rewrites whose MEANING may have moved, not just their wording.

The rewrite pass was meant to re-voice each option while preserving its
substance. The applier's gate cannot check substance -- it checks that the
key did not move and that the three options are distinct and non-empty. The
two LLM verifiers that could check substance never ran, so 2,270 rewrites are
unchecked.

This narrows what a verify pass has to look at, deterministically and for
free, by comparing each rewritten option against the original it replaced:

  polarity   a negation or a direction word flipped ("increase" -> "decrease",
             "not" appearing or vanishing). On the KEY this can make a true
             statement false; on a DISTRACTOR it can make a false one true,
             which is worse, because the question then has two answers.
  numeric    a figure present in the original is gone or different. The style
             rules say to inline the data rather than drop it, so a vanished
             number is either a rule breach or a question that can no longer
             be answered.
  gutted     almost no content words survive, so the option was replaced
             rather than rewritten and may be making a different claim.

An option can be flagged by more than one. Nothing here proves a defect --
"decreases" legitimately becomes "falls" and a reframed item legitimately
drops a figure. These are the items worth an LLM's attention, ranked.
"""
import collections
import glob
import json
import os
import re
import sys

NEW = "/home/user/CFA/CFAL3/Resources"
OLD = "/tmp/claude-0/-home-user-CFA/d0b73c48-5505-55c4-8713-3411fb736fd0/scratchpad/orig"
KEYS = ("A", "B", "C")

# Antonym pairs. Order inside a pair is arbitrary; what matters is that a
# text lands on one side or the other, and that old and new agree on which.
ANTONYMS = [
    ("increase", "decrease"), ("increases", "decreases"),
    ("rise", "fall"), ("rises", "falls"), ("rising", "falling"),
    ("higher", "lower"), ("more", "less"), ("greater", "smaller"),
    ("above", "below"), ("over", "under"),
    ("long", "short"), ("buy", "sell"), ("buys", "sells"),
    ("buying", "selling"), ("purchase", "sale"),
    ("positive", "negative"), ("gain", "loss"), ("gains", "losses"),
    ("appreciate", "depreciate"), ("appreciation", "depreciation"),
    ("widen", "narrow"), ("widens", "narrows"), ("widening", "narrowing"),
    ("up", "down"), ("upward", "downward"),
    ("outperform", "underperform"), ("overweight", "underweight"),
    ("surplus", "deficit"), ("premium", "discount"),
    ("debit", "credit"), ("before", "after"),
    ("exceed", "trail"), ("exceeds", "trails"),
    ("receiver", "payer"), ("receive", "pay"), ("receives", "pays"),
    ("inflow", "outflow"), ("inflows", "outflows"),
    ("surplus", "shortfall"), ("accumulation", "decumulation"),
    ("contango", "backwardation"),
    ("steepen", "flatten"), ("steepens", "flattens"),
    ("add", "remove"), ("adds", "removes"),
    ("maximize", "minimize"), ("maximise", "minimise"),
    ("overvalued", "undervalued"), ("overfunded", "underfunded"),
    ("hedged", "unhedged"), ("taxable", "tax-exempt"),
    ("qualified", "nonqualified"), ("fixed", "floating"),
    ("domestic", "foreign"), ("nominal", "real"),
    ("gross", "net"), ("before-tax", "after-tax"), ("pretax", "aftertax"),
]
NEGATION = re.compile(
    r"\b(?:not|no|never|neither|nor|none|without|cannot|can't|unable"
    r"|fails?|failed|exclude[sd]?|excluding|avoid(?:s|ed)?|lacks?"
    r"|insufficient|ineligible|impermissible|inappropriate|unnecessary)\b", re.I)
NUMBER = re.compile(r"\d+(?:[.,]\d+)*")
STOP = set("""a an the of to in on for by with at from as is are was were be been
being that this these those it its and or but if then than so such which who
whom whose what when where how any all both each more most other some only own
same very can will just should now would could may might must do does did has
have had not no nor""".split())


def words(text):
    return [w for w in re.findall(r"[A-Za-z][A-Za-z\-']+", (text or "").lower())
            if w not in STOP]


def polarity(text):
    """Which side of each antonym pair this text lands on, plus negation count."""
    low = f" {(text or '').lower()} "
    sig = {}
    for i, (a, b) in enumerate(ANTONYMS):
        ina = re.search(rf"\b{re.escape(a)}\b", low) is not None
        inb = re.search(rf"\b{re.escape(b)}\b", low) is not None
        if ina != inb:                      # both or neither tells us nothing
            sig[i] = a if ina else b
    return sig, len(NEGATION.findall(text or ""))


def numbers(text):
    return collections.Counter(
        n.replace(",", "") for n in NUMBER.findall(text or ""))


def load(directory):
    out = {}
    for path in sorted(glob.glob(os.path.join(directory, "los_drills_r*.json"))):
        data = json.load(open(path))
        for group in data.get("drills", []):
            for q in group.get("questions", []):
                o, c = q.get("options"), q.get("correct")
                if isinstance(o, dict) and len(o) == 3 and c in o:
                    out[q["id"]] = {"stem": q.get("stem") or "", "options": o,
                                    "correct": c, "file": os.path.basename(path)}
    return out


old, new = load(OLD), load(NEW)
changed = [i for i in new if i in old
           and (new[i]["options"] != old[i]["options"]
                or new[i]["stem"] != old[i]["stem"])]
print(f"{len(old)} drills before, {len(new)} after, {len(changed)} textually changed\n")

findings = []
for qid in changed:
    o, nw = old[qid], new[qid]
    key = nw["correct"]
    assert key == o["correct"], f"{qid}: key moved"
    for letter in KEYS:
        a, b = o["options"][letter], nw["options"][letter]
        if a == b:
            continue
        reasons = []
        sa, na = polarity(a)
        sb, nb = polarity(b)
        flipped = [(ANTONYMS[i], sa[i], sb[i]) for i in set(sa) & set(sb)
                   if sa[i] != sb[i]]
        if flipped:
            reasons.append("polarity:" + ",".join(
                f"{x}->{y}" for _, x, y in flipped))
        if na and not nb:
            reasons.append("polarity:negation-dropped")
        elif nb > na and na == 0:
            reasons.append("polarity:negation-added")
        gone = numbers(a) - numbers(b)
        if gone:
            reasons.append("numeric:lost " + " ".join(sorted(gone)))
        wa, wb = set(words(a)), set(words(b))
        if wa:
            kept = len(wa & wb) / len(wa)
            if kept < 0.20 and len(wa) >= 4:
                reasons.append(f"gutted:{kept:.0%}-of-content-words-kept")
        if reasons:
            findings.append({"id": qid, "file": nw["file"], "letter": letter,
                             "is_key": letter == key, "reasons": reasons,
                             "before": a, "after": b})

by_rule = collections.Counter(r.split(":")[0] for f in findings for r in f["reasons"])
on_key = sum(1 for f in findings if f["is_key"])
qs = {f["id"] for f in findings}
key_qs = {f["id"] for f in findings if f["is_key"]}

print(f"{len(findings)} suspect options across {len(qs)} questions")
print(f"  on the KEY        {on_key} options, {len(key_qs)} questions")
print(f"  on a distractor   {len(findings) - on_key} options\n")
for rule, c in by_rule.most_common():
    print(f"  {rule:10} {c}")

json.dump(findings, open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "drift_findings.json"), "w"),
          indent=2, ensure_ascii=False)
json.dump(sorted(qs), open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "drift_ids.json"), "w"), indent=2)
print(f"\nwrote drift_findings.json and drift_ids.json ({len(qs)} ids)")

if "--show" in sys.argv:
    for f in [x for x in findings if x["is_key"]][:int(sys.argv[-1])]:
        print(f"\n--- {f['id']} {f['letter']} (KEY)  {';'.join(f['reasons'])}")
        print(f"  BEFORE {' '.join(f['before'].split())}")
        print(f"  AFTER  {' '.join(f['after'].split())}")
