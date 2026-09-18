#!/usr/bin/env python3
"""Insert original SWF (.a/.b/.e) and Endowment (.d/.e) case questions.

Study items, not CFA Institute exam text. Do not retag existing stems.
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANK = os.path.join(ROOT, "CFAL3/Resources/question_bank.json")

SWF = "case_study_in_portfolio_management_institutional_swf"
END = "case_study_in_portfolio_management_institutional_endowment"

KARELIA = {
    "id": "karelia_heritage_fund_swf",
    "topic_id": "portfolio_construction",
    "title": "Karelia Heritage Fund (SWF)",
    "vignette": (
        "The Karelia Heritage Fund is a US$62 billion sovereign wealth fund "
        "owned by a commodity-exporting republic. Its legal mandate is dual: "
        "a stabilization sleeve that can be drawn when hydrocarbon royalties "
        "fall below a five-year average, and a savings sleeve intended to "
        "convert a depleting resource into financial wealth for future "
        "budgets. The current policy mix is 45% listed global equity, 20% "
        "investment-grade government and corporate bonds, 15% emerging-market "
        "local-currency debt, 12% timberland and energy infrastructure, and "
        "8% cash.\n\n"
        "The savings sleeve's listed equity and the timber/infrastructure "
        "sleeve are both highly correlated with global industrial demand. The "
        "emerging-market debt sleeve is concentrated in other commodity "
        "exporters, so a drop in Karelia's own export price typically arrives "
        "alongside mark-to-market losses on that sleeve — just when the "
        "stabilization sleeve is most likely to be drawn. The fund has no "
        "defined-benefit payroll and is not a bank; it does not hold "
        "regulatory capital against CET1 ratios.\n\n"
        "The board has asked staff to underwrite a US$1.4 billion construction "
        "loan and 25-year offtake for a coastal LNG terminal in a protected "
        "estuary. Independent ecology advice flags habitat loss and a high "
        "likelihood of protest, permit delay, and stranded-asset risk if "
        "importing countries tighten methane rules. The contractor would post "
        "letters of credit; those credits are not the board's stated reason "
        "for the project. The headquarters campus sits well above the "
        "historical flood plain.\n\n"
        "Enterprise risk management sits with a chief risk officer who reports "
        "to the chief investment officer. The only official risk metric is "
        "one-day 95% VaR on listed holdings. There is no independent risk "
        "committee, no climate or biodiversity scenario, and limit breaches "
        "are waived in writing by the CIO. A documented strength is that "
        "VaR is computed daily on the listed book and reported to the board "
        "pack, and cash for the stabilization sleeve is ring-fenced from the "
        "savings sleeve."
    ),
    "questions": [
        {
            "number": 1,
            "id": "karelia_heritage_fund_swf_q1",
            "stem": (
                "Which financial risk is *most* inherent in Karelia's current "
                "portfolio strategy?"
            ),
            "options": {
                "A": (
                    "Equity-market and commodity-cycle risks that rise and fall "
                    "with the sponsor's fiscal surplus."
                ),
                "B": (
                    "Funding-liquidity risk from a monthly pension payroll the "
                    "fund is legally unable to defer."
                ),
                "C": (
                    "Regulatory capital risk from a bank-style CET1 floor on "
                    "the fund's listed equity sleeve."
                ),
            },
            "type": "mc",
            "correct": "A",
            "rationales": {
                "A": (
                    "Correct. The strategy pairs a draw-when-royalties-fall "
                    "stabilization mandate with risk assets (listed equity, "
                    "commodity-exporter EM debt, timber/energy infrastructure) "
                    "that lose value in the same global-demand shock that "
                    "shrinks the sponsor's surplus. That correlation is a "
                    "financial risk of *this* institutional strategy."
                ),
                "B": (
                    "Incorrect. Karelia is a sovereign wealth fund with no "
                    "defined-benefit payroll. Inventing a pension-payment "
                    "constraint describes a different institution's liability, "
                    "not this strategy's financial risk."
                ),
                "C": (
                    "Incorrect. The fund is not a bank and is not bound by "
                    "CET1. Bank regulatory-capital risk is not a financial "
                    "risk of this SWF strategy."
                ),
            },
            "candidate_los": [f"{SWF}.a"],
            "primary_reading_ids": [SWF],
            "data_quality": "complete",
            "data_quality_flags": [],
        },
        {
            "number": 2,
            "id": "karelia_heritage_fund_swf_q2",
            "stem": (
                "The LNG terminal proposal *most clearly* introduces which "
                "environmental or social risk into the portfolio strategy?"
            ),
            "options": {
                "A": (
                    "Physical flood damage to headquarters from a 1-in-100-year "
                    "river event on the historical flood plain."
                ),
                "B": (
                    "Transition and social-license risk from financing "
                    "high-carbon infrastructure in a sensitive habitat."
                ),
                "C": (
                    "Counterparty credit risk on the construction contractor's "
                    "letters of credit for the terminal."
                ),
            },
            "type": "mc",
            "correct": "B",
            "rationales": {
                "A": (
                    "Incorrect. Physical flood risk at headquarters is not "
                    "what the proposal introduces; the campus sits above the "
                    "historical flood plain, and the new exposure is the "
                    "project itself."
                ),
                "B": (
                    "Correct. Underwriting a long-dated LNG terminal in a "
                    "protected estuary adds methane-rule transition risk, "
                    "habitat-loss environmental risk, and protest/permit "
                    "social-license risk to the strategy — the E&S risks of "
                    "this institutional allocation, not generic office-flood "
                    "or contractor-credit risk."
                ),
                "C": (
                    "Incorrect. Contractor letters of credit are a financial "
                    "counterparty exposure. The board's proposal is framed as "
                    "an environmental/social project choice; credit on the LC "
                    "is not the E&S risk the LOS asks you to discuss."
                ),
            },
            "candidate_los": [f"{SWF}.b"],
            "primary_reading_ids": [SWF],
            "data_quality": "complete",
            "data_quality_flags": [],
        },
        {
            "number": 3,
            "id": "karelia_heritage_fund_swf_essay_q3",
            "stem": (
                "EVALUATE two strengths and two weaknesses of Karelia's "
                "enterprise risk management system and RECOMMEND one "
                "improvement for each weakness."
            ),
            "type": "essay",
            "options": None,
            "correct": None,
            "points": 6,
            "rationales": {
                "model_answer": (
                    "STRENGTHS (any TWO):\n"
                    "• Daily 95% VaR is computed on listed holdings and "
                    "included in the board pack, so market risk on the "
                    "observable book is at least measured and reported.\n"
                    "• Stabilization cash is ring-fenced from the savings "
                    "sleeve, which separates drawdown liquidity from "
                    "long-horizon risk capital.\n\n"
                    "WEAKNESSES (any TWO) + a matching improvement:\n"
                    "• The CRO reports to the CIO, and the CIO can waive "
                    "limit breaches — risk is not independent of the people "
                    "taking it. IMPROVE: CRO reports to the board or an "
                    "independent risk committee; waivers require that "
                    "committee, not the CIO.\n"
                    "• VaR is one-day 95% on listed holdings only — it "
                    "misses timber/infrastructure, EM-debt gaps, "
                    "stabilization draws, and climate/biodiversity. IMPROVE: "
                    "add multi-horizon stress and climate/biodiversity "
                    "scenarios that cover unlisted sleeves and the "
                    "royalty-draw correlation.\n"
                    "• No independent risk committee. IMPROVE: constitute "
                    "one with authority over limits, waivers, and new "
                    "project underwriting (including the LNG loan)."
                )
            },
            "candidate_los": [f"{SWF}.e"],
            "primary_reading_ids": [SWF],
            "data_quality": "complete",
            "data_quality_flags": [],
        },
    ],
}

RIDGEWOOD = {
    "id": "ridgewood_college_endowment",
    "topic_id": "portfolio_management_pathway",
    "title": "Ridgewood College Endowment",
    "vignette": (
        "Ridgewood College's endowment is US$1.8 billion. The spending rule "
        "is 5% of a twelve-quarter market average. Policy weights are 55% "
        "public equity, 15% investment-grade bonds, 12% private equity, 8% "
        "real assets, and 10% cash and T-bills. After a cluster of PE "
        "capital calls, public equity has drifted to 48% and cash is thin.\n\n"
        "The investment committee is replacing a long-only global equity "
        "manager. Two finalists remain.\n\n"
        "Manager A is a former colleague of the CIO. During the RFP, A's "
        "marketing director offers the CIO a pair of World Cup final tickets "
        "and presents a ten-year return stream labeled as the strategy's "
        "composite. The composite silently drops a sleeve that was closed "
        "after two poor years; including it would cut the advertised annual "
        "return by 140 basis points. Manager B is independent of the staff, "
        "declines entertainment, and presents a GIPS-compliant composite "
        "that retains terminated sleeves.\n\n"
        "Separately, staff want the public-equity weight back at 55% this "
        "week without selling PE on the secondary market (indicative bid is "
        "a 12% discount to NAV). Three implementation notes:\n"
        "1. Buying the physical equity basket takes about three trading days "
        "and roughly 18 bp round-trip, and would require selling IG bonds "
        "or waiting for inflows.\n"
        "2. Listed equity-index futures can be sized the same day, with "
        "transaction costs well below 18 bp, but they require daily "
        "variation margin in cash.\n"
        "3. A PE secondary sale would fund physical equities with unlevered "
        "cash but would lock in the 12% discount."
    ),
    "questions": [
        {
            "number": 1,
            "id": "ridgewood_college_endowment_essay_q1",
            "stem": (
                "For EACH item below, IDENTIFY the Standard of Professional "
                "Conduct most clearly implicated in Ridgewood's manager "
                "selection and RECOMMEND the action the selection committee "
                "should take.\n\n"
                "i. The World Cup tickets offered to the CIO.\n"
                "ii. Manager A's composite, which drops the terminated sleeve."
            ),
            "type": "essay",
            "options": None,
            "correct": None,
            "points": 6,
            "rationales": {
                "model_answer": (
                    "i. TICKETS — Standard I(B) Independence and Objectivity "
                    "(also I(A) if local gift rules are tighter). A gift of "
                    "this size from a manager in an active RFP reasonably "
                    "compromises, or appears to compromise, the CIO's "
                    "objectivity in hiring. ACTION: decline the tickets, "
                    "document the offer, recuse the CIO from scoring Manager "
                    "A if the offer was not immediately refused, and tell "
                    "Manager A that entertainment during a search is "
                    "prohibited.\n\n"
                    "ii. DROPPED SLEEVE — Standard I(C) Misrepresentation "
                    "(and III(D) Performance Presentation to the extent the "
                    "committee is a client of the search). Omitting a fired "
                    "sleeve from a 'composite' offered as the strategy's "
                    "record misstates performance. ACTION: reject the "
                    "advertised track record, require a composite that keeps "
                    "terminated accounts, and do not hire on the inflated "
                    "numbers. Manager B's full composite is the record that "
                    "can actually be compared."
                )
            },
            "candidate_los": [f"{END}.d"],
            "primary_reading_ids": [END],
            "data_quality": "complete",
            "data_quality_flags": [],
        },
        {
            "number": 2,
            "id": "ridgewood_college_endowment_q2",
            "stem": (
                "To restore the 55% public-equity exposure this week WITHOUT "
                "locking in a private-equity secondary discount, the *most* "
                "appropriate choice is to:"
            ),
            "options": {
                "A": (
                    "Redeem investment-grade bonds and buy the physical equity "
                    "basket over several days, because listed futures cannot "
                    "establish an asset-class exposure."
                ),
                "B": (
                    "Sell private-equity interests on the secondary market at "
                    "a double-digit discount so public equity is funded with "
                    "unlevered cash."
                ),
                "C": (
                    "Buy equity-index futures as an overlay, establishing the "
                    "asset-class exposure immediately at lower transaction "
                    "cost while accepting variation-margin liquidity needs."
                ),
            },
            "type": "mc",
            "correct": "C",
            "rationales": {
                "A": (
                    "Incorrect. Futures *can* establish the asset-class "
                    "exposure. Cash equities work but are slower and more "
                    "expensive than the overlay, and the claim that futures "
                    "cannot do the job is false."
                ),
                "B": (
                    "Incorrect. A 12% NAV discount is the cost the committee "
                    "wants to avoid. Secondaries fund cash equities but fail "
                    "the 'without locking in the discount' constraint."
                ),
                "C": (
                    "Correct. Relative to cash-market purchases, listed "
                    "equity futures restore the 55% exposure the same day at "
                    "much lower transaction cost. The trade-off is "
                    "variation-margin cash — a liquidity cost of derivatives "
                    "versus cash, which is exactly the comparison the LOS "
                    "requires. PE secondaries are cash-market but fail the "
                    "discount constraint."
                ),
            },
            "candidate_los": [f"{END}.e"],
            "primary_reading_ids": [END],
            "data_quality": "complete",
            "data_quality_flags": [],
        },
    ],
}


def counts(bank: dict) -> tuple[int, int, int]:
    qs = [q for t in bank["topics"] for c in t["cases"] for q in c["questions"]]
    mc = sum(1 for q in qs if q["type"] == "mc")
    essay = sum(1 for q in qs if q["type"] == "essay")
    return len(qs), mc, essay


def main() -> int:
    bank = json.load(open(BANK, encoding="utf-8"))
    titles = {c["title"] for t in bank["topics"] for c in t["cases"]}
    ids = {c["id"] for t in bank["topics"] for c in t["cases"]}
    qids = {
        q["id"]
        for t in bank["topics"]
        for c in t["cases"]
        for q in c["questions"]
    }
    for case in (KARELIA, RIDGEWOOD):
        if case["title"] in titles:
            print(f"title exists {case['title']}", file=sys.stderr)
            return 1
        if case["id"] in ids:
            print(f"case id exists {case['id']}", file=sys.stderr)
            return 1
        for q in case["questions"]:
            if q["id"] in qids:
                print(f"question id exists {q['id']}", file=sys.stderr)
                return 1
            if q["type"] == "essay":
                assert q.get("points") in (4, 6, 8)
                assert (q.get("rationales") or {}).get("model_answer")

    before = counts(bank)
    placed = set()
    for topic in bank["topics"]:
        if topic["id"] == "portfolio_construction":
            topic["cases"].append(KARELIA)
            placed.add("swf")
        elif topic["id"] == "portfolio_management_pathway":
            topic["cases"].append(RIDGEWOOD)
            placed.add("end")
    if placed != {"swf", "end"}:
        print({"placed": placed}, file=sys.stderr)
        return 1

    after = counts(bank)
    print("before", before, "after", after)
    assert after[0] == before[0] + 5
    assert after[1] == before[1] + 3
    assert after[2] == before[2] + 2

    with open(BANK, "w", encoding="utf-8") as fh:
        json.dump(bank, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
