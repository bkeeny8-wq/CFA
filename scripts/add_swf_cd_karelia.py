#!/usr/bin/env python3
"""Append original SWF .c / .d essays to the Karelia Heritage Fund case.

Study items, not CFA Institute exam text. Does not retag existing stems.
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANK = os.path.join(ROOT, "CFAL3/Resources/question_bank.json")
SWF = "case_study_in_portfolio_management_institutional_swf"
CASE_ID = "karelia_heritage_fund_swf"

NEW = [
    {
        "number": 4,
        "id": "karelia_heritage_fund_swf_essay_q4",
        "stem": (
            "ANALYZE one financial risk exposure and one non-financial risk "
            "exposure in Karelia's portfolio strategy, including the proposed "
            "LNG terminal. EVALUATE whether each is material given the dual "
            "stabilization/savings mandate."
        ),
        "type": "essay",
        "options": None,
        "correct": None,
        "points": 6,
        "rationales": {
            "model_answer": (
                "FINANCIAL (any ONE, with materiality):\n"
                "• Commodity-cycle correlation: listed equity, EM local-currency "
                "debt in other exporters, and timber/energy infrastructure all "
                "fall in the same global-demand shock that cuts Karelia's "
                "royalties — just when the stabilization sleeve is drawn. "
                "MATERIAL: the dual mandate makes this worse than a pure "
                "savings SWF, because drawdowns and MTM losses arrive together.\n"
                "• Liquidity gap on unlisted timber/infrastructure when a "
                "stabilization draw is needed. MATERIAL for the stabilization "
                "sleeve; less so for the long-horizon savings sleeve.\n\n"
                "NON-FINANCIAL (any ONE, with materiality):\n"
                "• LNG terminal: methane-rule transition risk, habitat loss, "
                "protest/permit delay, and stranded-asset risk on a 25-year "
                "direct offtake. MATERIAL: a US$1.4bn concentrated real-asset "
                "exposure that the listed VaR never sees, and that is the "
                "opposite of diversification away from hydrocarbons.\n"
                "• Social-license / political risk around a coastal project in "
                "a protected estuary. MATERIAL for a public SWF whose "
                "board is already framing the loan as industrial policy.\n\n"
                "A complete answer names one of each and ties materiality to "
                "the draw-when-royalties-fall mandate, not generic 'SWFs take "
                "long-term risk.'"
            )
        },
        "candidate_los": [f"{SWF}.c"],
        "primary_reading_ids": [SWF],
        "data_quality": "complete",
        "data_quality_flags": [],
    },
    {
        "number": 5,
        "id": "karelia_heritage_fund_swf_essay_q5",
        "stem": (
            "DISCUSS two methods Karelia could use to manage the risks of the "
            "long-term LNG terminal direct investment, other than simply "
            "declining the loan."
        ),
        "type": "essay",
        "options": None,
        "correct": None,
        "points": 6,
        "rationales": {
            "model_answer": (
                "Any TWO distinct methods, each tied to this project:\n"
                "• STAGED CAPITAL / MILESTONES: fund construction in tranches "
                "released only after environmental permits and offtake "
                "conditions are met, so a protest or methane-rule change can "
                "stop further cash without a full US$1.4bn loss.\n"
                "• CONTRACTUAL PROTECTIONS: offtake, methane/ESG covenants, "
                "and step-in rights so transition and operating risk sit with "
                "the sponsor, not only with the SWF as lender.\n"
                "• RISK TRANSFER: political-risk insurance or a multilateral "
                "guarantee on expropriation/permit revocation; syndicate or "
                "co-invest the loan so Karelia does not hold the whole ticket.\n"
                "• GOVERNANCE: independent board/risk-committee approval, "
                "climate/biodiversity scenarios before commitment, and a "
                "hard limit on hydrocarbon real assets as a share of the "
                "savings sleeve.\n"
                "• STRUCTURAL DIVERSIFICATION: pair any residual exposure with "
                "unrelated long-term directs (e.g., non-energy infrastructure "
                "outside the commodity cycle) rather than adding more "
                "timber/energy.\n"
                "Do not credit 'sell listed equity' or 'raise cash' — those "
                "manage listed-book risk, not the long-term direct."
            )
        },
        "candidate_los": [f"{SWF}.d"],
        "primary_reading_ids": [SWF],
        "data_quality": "complete",
        "data_quality_flags": [],
    },
]


def counts(bank: dict) -> tuple[int, int, int]:
    qs = [q for t in bank["topics"] for c in t["cases"] for q in c["questions"]]
    mc = sum(1 for q in qs if q["type"] == "mc")
    essay = sum(1 for q in qs if q["type"] == "essay")
    return len(qs), mc, essay


def main() -> int:
    bank = json.load(open(BANK, encoding="utf-8"))
    qids = {
        q["id"]
        for t in bank["topics"]
        for c in t["cases"]
        for q in c["questions"]
    }
    target = None
    for topic in bank["topics"]:
        for case in topic["cases"]:
            if case["id"] == CASE_ID:
                target = case
                break
    if target is None:
        print("Karelia case missing", file=sys.stderr)
        return 1
    for q in NEW:
        if q["id"] in qids:
            print(f"already present {q['id']}", file=sys.stderr)
            return 1
        if any(existing["id"] == q["id"] for existing in target["questions"]):
            print(f"duplicate on case {q['id']}", file=sys.stderr)
            return 1
    before = counts(bank)
    target["questions"].extend(NEW)
    after = counts(bank)
    print("before", before, "after", after)
    assert after[0] == before[0] + 2
    assert after[1] == before[1]
    assert after[2] == before[2] + 2
    with open(BANK, "w", encoding="utf-8") as fh:
        json.dump(bank, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
