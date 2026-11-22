#!/usr/bin/env python3
"""Measure LOS-drill options against the house style the case bank already uses.

    python3 scripts/drill_style_lint.py                  # whole corpus
    python3 scripts/drill_style_lint.py --reading r17    # one file
    python3 scripts/drill_style_lint.py --bank           # score the case bank instead
    python3 scripts/drill_style_lint.py --sample 5       # print offending items

WHY THIS EXISTS. The drills were generated to a different specification than
the one CFA Institute writes to, and the two are visible side by side inside
this repo: question_bank.json holds 270 real-format item-set questions whose
options run to a MEDIAN OF 18 CHARACTERS ("A. 1.5%.", "B. Switzerland."),
while the drills' options run to 97. A CFA option is the candidate answer and
nothing else. A drill option, as generated, is a small paragraph: the stem's
claim restated, the arithmetic worked through, and a second sentence of
generator filler.

That is not only unrealistic, it leaks the answer. Four measured cues:

    strategy, needing no knowledge of the curriculum      scores
    drop the option that runs to two sentences,
      then take the longest of what is left                73.6%
    drop the option carrying generator boilerplate,
      then take the longest                                69.9%
    take the longest option                                43.3%
    take the middle-length option                          43.2%
    chance                                                 33.3%

The first row is the one that matters and it was not closed by
fix_drill_length_cue.py, which balanced length while leaving the padding that
makes the ranking readable in the first place. Deleting the padding on its own
makes it WORSE (59.9%), because the padding is what stops the key being
longest. Length and prose have to be fixed together, by rewriting the option
set short — which is authoring, not text manipulation. See
scripts/rewrite_drill_options.py.

THE RULES below are derived from question_bank.json, not invented; --bank
scores that file and every rule passes on it.
"""

from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re
import statistics

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEYS = ("A", "B", "C")

# Abbreviations the curriculum genuinely writes in capitals. Anything else in
# capitals is the generator shouting, which CFA Institute never does -- it uses
# "least likely" where this corpus writes "NOT".
ACRONYMS = set("""
CFA IPS GIPS ESG BPV PVBP SWF TAA SAA GDP CDS AUM USD EUR GBP JPY CHF AUD CAD
CNY SEK NOK DKK HKD SGD KRW INR BRL MXN ZAR TRY RUB PLN CZK HUF THB IDR PHP
IPO VWAP TWAP ETF ETN ATM OTM ITM MVO MSCI VIX OTC NAV YTM MNPI ERM TRS KRD
IRR FTSE RFP LDI CAPM VCV POD CME GFC CTD REIT TIPS OAS CPPI SOFR LIBOR MRR
TWR MWR NPV WACC ROE ROA EPS SPV CDX CTA SEC IMF OECD ABS MBS CMBS RMBS CLO
CDO FRA OIS NDF CPI PPI IRS NYSE LSE EAFE ACWI GICS FCFE FCFF EBIT EBITDA LBO
SPAC GNMA FNMA FHLMC ISDA CSA LCR NSFR RWA IFRS GAAP FASB IASB EMH APT CAL CML
SML LOS ERISA PBO ABO HNW UHNW LLC LLP ETFS PPP RBSA SBSA SMA UMA CIO COO CFO
CEO ESOP RSU NQSO DAF CRT CLT GRAT QTIP TOD POA AMT NIIT FIFO LIFO DCF EV
PME IRRS SPX RUT DJIA NASDAQ UCITS SICAV OEIC AIFMD MIFID PRIIPS KIID SRI PRI
UNPRI TCFD SASB CDP GRI
""".split())
ROMAN = re.compile(r"^[IVXLCDM]+$")
CAPS_WORD = re.compile(r"\b[A-Z]{3,}\b")


def _dictionary() -> set:
    """Ordinary English words, so that shouting can be told from an abbreviation.

    "SPP", "QUINCO" and "GVC" are entities the item defines; the case bank does
    the same thing and it reads fine. "NOT", "HIGHER", "SHORT" are the generator
    raising its voice, which CFA Institute never does -- it writes "least
    likely" in italics and leaves it there.
    """
    for path in ("/usr/share/dict/words", "/usr/dict/words"):
        try:
            with open(path) as fh:
                return {w.strip().lower() for w in fh if len(w.strip()) >= 3}
        except OSError:
            continue
    return set("""not and the all only same may long short risk return capital tax
        higher lower like based increase decrease portfolio insurance financial
        personal disclose trace must never always both each more less than with
        from into over under before after when where which what who how why""".split())


WORDS = _dictionary()
BOILERPLATE = re.compile(
    r"That specification would be used as-is"
    r"|That approach would be applied without further adjustment", re.I)
# "U.S.", "e.g.", "i.e.", "vs." must not look like sentence ends.
ABBREV = re.compile(r"\b(?:[A-Za-z]\.){2,}|\b(?:e\.g|i\.e|vs|No|Mr|Ms|Dr|St|Inc|Co)\.")
ARITH = re.compile(r"[×÷]|\s[x*/]\s|(?<=\d)\s*[-−+]\s*(?=\d)")

MAX_OPTION_CHARS = 120      # case bank p90 is 62; this is a generous ceiling


def sentence_count(text: str) -> int:
    masked = ABBREV.sub("@", text)
    return len([s for s in re.split(r"(?<=[.!?])\s+", masked.strip()) if s])


def emphasis_caps(text: str) -> list:
    """All-capital words that are ordinary English, i.e. emphasis, not an acronym."""
    return [w for w in CAPS_WORD.findall(text)
            if w not in ACRONYMS and not ROMAN.match(w) and w.lower() in WORDS]


def lint_option(text: str) -> list:
    """Every rule this one option breaks."""
    bad = []
    if BOILERPLATE.search(text):
        bad.append("boilerplate")
    if sentence_count(text) > 1:
        bad.append("multi_sentence")
    if "=" in text:
        bad.append("equation")
    elif len(ARITH.findall(text)) > 1:
        bad.append("arithmetic")
    if len(text) > MAX_OPTION_CHARS:
        bad.append("too_long")
    if emphasis_caps(text):
        bad.append("shouting")
    return bad


def lint_question(q: dict) -> list:
    """Rules that are about the option SET or the stem, not one option.

    There is deliberately no "make the three options the same length" rule.
    The case bank breaks that constantly ("Chile." against "Singapore and
    Sweden.") and reads perfectly, because length only leaks the answer when it
    CORRELATES with the key across the corpus. That is measured below by
    no_reading_scores(), which is the real test; a per-question ratio is not.
    """
    bad = []
    opts = q["options"]
    # All three options must open the same way. One lowercase continuation among
    # two capitalised sentences points at the odd one out, and in this corpus the
    # odd one out used to be the key 95% of the time.
    starts = {v[:1].islower() for v in opts.values() if v}
    if len(starts) > 1:
        bad.append("inconsistent_case")
    stem = q.get("stem") or ""
    if "=" in stem:
        bad.append("equation_in_stem")
    if emphasis_caps(stem):
        bad.append("shouting_stem")
    return bad


def load_drills(pattern: str) -> list:
    out = []
    for p in sorted(glob.glob(os.path.join(ROOT, f"CFAL3/Resources/{pattern}.json"))):
        data = json.load(open(p))
        for drill in data.get("drills", []):
            for q in drill.get("questions", []):
                if isinstance(q.get("options"), dict) and q.get("correct") in KEYS:
                    q["_file"] = os.path.basename(p)
                    out.append(q)
    return out


def load_bank() -> list:
    data = json.load(open(os.path.join(ROOT, "CFAL3/Resources/question_bank.json")))

    def walk(o):
        if isinstance(o, dict):
            if isinstance(o.get("options"), dict):
                yield o
            for v in o.values():
                yield from walk(v)
        elif isinstance(o, list):
            for v in o:
                yield from walk(v)
    return [q for q in walk(data) if q.get("correct") in KEYS]


def no_reading_scores(qs: list) -> dict:
    """How well you do on these items without reading a word of the stem."""
    def score(fn):
        return sum(1 for q in qs if fn(q) == q["correct"]) / len(qs) * 100

    def longest(q, pool=None):
        o = q["options"]
        pool = pool or list(o)
        return max(pool, key=lambda k: len(o[k]))

    def drop_multi(q):
        o = q["options"]
        live = [k for k, v in o.items() if sentence_count(v) == 1] or list(o)
        return live[0] if len(live) == 1 else longest(q, live)

    def drop_boiler(q):
        o = q["options"]
        live = [k for k, v in o.items() if not BOILERPLATE.search(v)] or list(o)
        return live[0] if len(live) == 1 else longest(q, live)

    return {
        "drop two-sentence option, then longest": score(drop_multi),
        "drop boilerplate option, then longest": score(drop_boiler),
        "longest option": score(longest),
        "middle-length option": score(
            lambda q: sorted(q["options"], key=lambda k: -len(q["options"][k]))[1]),
        "shortest option": score(
            lambda q: min(q["options"], key=lambda k: len(q["options"][k]))),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reading", default="los_drills_r*")
    ap.add_argument("--bank", action="store_true")
    ap.add_argument("--sample", type=int, default=0)
    args = ap.parse_args()

    qs = load_bank() if args.bank else load_drills(args.reading)
    label = "case bank" if args.bank else args.reading
    n = len(qs)
    if not n:
        print(f"no questions matched {label}")
        return 1

    per_option = collections.Counter()
    per_question = collections.Counter()
    dirty = []
    for q in qs:
        flags = set(lint_question(q))
        for k, v in q["options"].items():
            for f in lint_option(v):
                per_option[f] += 1
                flags.add(f)
        for f in flags:
            per_question[f] += 1
        if flags:
            dirty.append((q, sorted(flags)))

    lens = [len(v) for q in qs for v in q["options"].values()]
    keys = [len(q["options"][q["correct"]]) for q in qs]
    dis = [len(v) for q in qs for k, v in q["options"].items() if k != q["correct"]]

    print(f"{label}: {n} questions, {len(lens)} options\n")
    print(f"  option length   median {statistics.median(lens):5.0f}   "
          f"mean {statistics.mean(lens):5.0f}   "
          f"p90 {sorted(lens)[int(.9 * len(lens)) - 1]:5.0f}   max {max(lens)}")
    print(f"    correct       median {statistics.median(keys):5.0f}")
    print(f"    distractors   median {statistics.median(dis):5.0f}")

    print(f"\n  rule breaches           questions          options")
    for rule in ("boilerplate", "multi_sentence", "equation", "arithmetic",
                 "too_long", "shouting", "inconsistent_case",
                 "equation_in_stem", "shouting_stem"):
        qn, on = per_question[rule], per_option.get(rule, 0)
        print(f"    {rule:20} {qn:6} ({qn / n * 100:5.1f}%)   "
              + (f"{on:6} ({on / len(lens) * 100:5.1f}%)" if on else ""))

    clean = n - len(dirty)
    print(f"\n  clean questions: {clean} / {n}  ({clean / n * 100:.1f}%)")

    print("\n  answerable without reading the stem:")
    for name, pct in sorted(no_reading_scores(qs).items(), key=lambda x: -x[1]):
        print(f"    {name:40} {pct:5.1f}%")
    print(f"    {'chance':40}  33.3%")

    for q, flags in dirty[:args.sample]:
        print(f"\n  --- {q.get('id', '?')}  {','.join(flags)}")
        print(f"      {' '.join((q.get('stem') or '').split())[:160]}")
        for k, v in q["options"].items():
            mark = "*" if k == q["correct"] else " "
            print(f"    {mark} {k}. {' '.join(v.split())[:200]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
