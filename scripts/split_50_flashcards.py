#!/usr/bin/env python3
"""Split remaining 50-word flashcard backs. Keep original ids on first atoms.

Original study cards (not CFA Institute exam items). Targeted: only cards
whose backs are still 50 words. Do not re-run the full atomizer.
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "CFAL3/Resources/flashcards.json")

# id -> ordered atoms after the first (which keeps the original id).
# Each entry is (authoring_note, back). The note labels the atom for whoever
# edits this table; fronts are numbered positionally instead.
SPLITS: dict[str, list[tuple[str, str]]] = {
    "fc_trade_strategy_and_execution_014_p4": [
        (
            "Best execution and the factors that set the approach",
            "• The other required trade-policy elements: the meaning of best execution, and the factors setting the optimal execution approach (urgency, security characteristics, venue characteristics, strategy objectives, rationale for the trade).",
        ),
        (
            "Trade errors, eligible brokers, and monitoring",
            "Treatment of TRADE ERRORS (disclosed to compliance and logged), a list of eligible brokers/venues, and a process to monitor execution arrangements.",
        ),
    ],
    "fc_trade_strategy_and_execution_009": [
        (
            "EQUITY — market structure",
            "• EQUITY — exchanges (lit: pre- and post-trade transparency) plus dark pools/ATS/MTF (post-trade only); most technologically advanced, mostly electronic and algorithmic.",
        ),
        (
            "EQUITY — large urgent vs non-urgent",
            "Large urgent, especially illiquid small caps → high-touch broker RISK (principal) trade; large non-urgent → algorithms in liquid large caps, high-touch AGENCY in illiquid names; small liquid → electronic.",
        ),
    ],
    "fc_principles_of_asset_allocation_008": [
        (
            "Monte Carlo — what it produces",
            "• Monte Carlo: thousands of simulated paths → the full DISTRIBUTION of outcomes through time (percentile wealth paths, maximum drawdowns, probability of meeting a goal).",
        ),
        (
            "Monte Carlo — when it is required",
            "It handles the multi-period problems MVO cannot: withdrawals, the interaction of rebalancing with taxes and trading costs, glide paths, annuities, human capital, non-normal multivariate returns.",
        ),
    ],
    "fc_portfolio_management_for_institutional_investors_013": [
        (
            "Equity-duration terms",
            "• D*E = modified duration of shareholders' equity capital; D*A and D*L = modified durations of assets and liabilities; A ÷ E = leverage (the inverse of the equity-to-assets ratio); Δi ÷ Δy = sensitivity of liability yields to asset yields.",
        ),
        (
            "Percent change in equity value",
            "Percent change in equity value ≈ −D*E × Δy.",
        ),
    ],
    "fc_overview_of_the_global_investment_performance_standards_013_p9": [
        (
            "Minimum asset level — add and remove",
            "Minimum asset level: permitted; the firm must document how portfolios falling below are treated (e.g., add at $1m, remove only below $900,000); changes to the minimum must NOT be applied retroactively.",
        ),
        (
            "Removed portfolios stay in history",
            "A removed portfolio's prior performance stays in the composite and the firm must check whether it fits another composite.",
        ),
    ],
    "fc_overview_of_fixed_income_portfolio_management_011_p6": [
        (
            "Pass-through vehicles",
            "Vehicle matters: with pass-through treatment (US mutual funds) realized fund gains are taxed to investors in the year they arise; without it (UK) gains raise NAV and are taxed only when shares are sold.",
        ),
        (
            "Separately managed accounts",
            "In a separately managed account the investor is taxed on gains as the manager realizes them.",
        ),
    ],
    "fc_investment_manager_selection_005_p4": [
        (
            "When style analysis is useful",
            "• Use: style analysis is most useful for strategies holding publicly traded, frequently priced securities; track results over time.",
        ),
        (
            "Style drift vs an unrepeatable process",
            "Exposures out of line with the stated style signal STYLE DRIFT, and results inconsistent with the stated philosophy and process suggest the process is not repeatable or is inconsistently implemented.",
        ),
    ],
    "fc_guidance_standard_v_investment_analysis_006_p6_p2": [
        (
            "Records cannot leave without consent",
            "Records cannot be taken to a new employer without express consent; work from a previous firm cannot be used if the supporting documentation is unavailable, and records must be recreated at the new firm.",
        ),
        (
            "Recreating records from a prior employer",
            "Those new records cannot be recreated from sources obtained at the previous employer WITHOUT THAT EMPLOYER'S PERMISSION.",
        ),
    ],
    "fc_guidance_standard_iv_duties_to_employers_003": [
        (
            "When the employment relationship ends",
            "The relationship ends only when you are no longer paid and no longer have responsibilities — a resignation letter does not end it.",
        ),
        (
            "give her new contact information",
            "BEFORE the relationship ends, with notice given, she MAY name her new employer, but must NOT (without the current employer's permission):\n\n• give her new contact information;",
        ),
    ],
    "fc_guidance_standard_iii_duties_to_clients_003_p3": [
        (
            "Choosing who gets the initial recommendation",
            "• Choosing which clients receive an initial recommendation based on suitability and known interest — never on preferred or favored status.",
        ),
        (
            "Differentiated service must be disclosed",
            "Required of any differentiated service: disclosed to all clients and prospects, and available to everyone — never offered selectively.",
        ),
        (
            "When a difference becomes a violation",
            "A difference becomes a violation once it disadvantages or negatively affects other clients.",
        ),
    ],
    "fc_guidance_standard_i_professionalism_007_p5": [
        (
            "Abusing I(D) to settle private disputes",
            "• Separate caution (not itself labeled an I(D) violation): individuals sometimes try to abuse the Professional Conduct Program by seeking enforcement of I(D) to settle personal, political, or other disputes unrelated to professional ethics.",
        ),
        (
            "How CFA Institute handles that misuse",
            "CFA Institute has disciplinary policies, procedures, and enforcement mechanisms in place to address that misuse.",
        ),
    ],
    "fc_case_study_in_portfolio_management_institutional_swf_004_p4": [
        (
            "Transition — stranded assets",
            "• Portfolio impact: massive disruption in electricity generation (renewables now cost-competitive with coal) and autos (ICE to EV), producing stranded assets.",
        ),
        (
            "Inevitable Policy Response",
            "The PRI's Inevitable Policy Response forecasts a response by 2025 that is forceful, abrupt and disorderly because action was delayed, and argues markets have inefficiently priced this risk.",
        ),
    ],
    "fc_capital_market_expectations_part_1_framework_and_macro_considerations_010_p4": [
        (
            "SLOWDOWN — rates, curve, credit",
            "• SLOWDOWN: economy decelerating toward the peak, especially vulnerable to a shock; inflation often still rising. Short rates high and peaking; bond yields TOP OUT and may fall sharply; curve may INVERT; credit spreads widen (weaker credits most).",
        ),
        (
            "SLOWDOWN — equities that hold up",
            "Stocks may fall — interest-sensitive (utilities) and \"quality\" stable-earnings stocks do best.",
        ),
    ],
    "fc_active_equity_investing_strategies_009_p5": [
        (
            "Sell when price passes the target",
            "• Sell triggers: the price rises past the analyst's target price, so the stock is reclassified from undervalued to overvalued; OR the target price is revised down below the current market price.",
        ),
        (
            "Stop-loss as a sell trigger",
            "OR a pre-defined stop-loss point is touched, which caps the loss on any holding and limits behavioral bias.",
        ),
    ],
}


def next_atom_id(base: str, used: set[str]) -> str:
    n = 2
    while True:
        candidate = f"{base}_p{n}"
        if candidate not in used:
            return candidate
        n += 1


def stem_front(front: str) -> str:
    return front.split("\n\n", 1)[0].rstrip()


def stats(cards: list[dict]) -> dict:
    words = sorted(len(c["back"].split()) for c in cards)
    n = len(words)
    return {
        "n": n,
        "median_words": words[n // 2] if words else 0,
        "p90_words": words[int(n * 0.9)] if words else 0,
        "max_words": words[-1] if words else 0,
        "at_50": sum(1 for w in words if w == 50),
        "over_49": sum(1 for w in words if w > 49),
    }


def main() -> int:
    bundle = json.load(open(PATH, encoding="utf-8"))
    cards = bundle["cards"]
    before = stats(cards)
    by_id = {c["id"]: i for i, c in enumerate(cards)}
    missing = [i for i in SPLITS if i not in by_id]
    if missing:
        print({"missing": missing}, file=sys.stderr)
        return 1

    used = {c["id"] for c in cards}
    out: list[dict] = []
    split = 0
    new_atoms = 0
    for card in cards:
        pieces = SPLITS.get(card["id"])
        if not pieces:
            out.append(card)
            continue
        for head, back in pieces:
            if len(back.split()) > 49:
                print(f"atom still long {card['id']}: {len(back.split())}", file=sys.stderr)
                return 1
        split += 1
        front = stem_front(card["front"])
        for i, (_head, back) in enumerate(pieces):
            atom = dict(card)
            atom["back"] = back
            # The authoring head names the atom for review here; it must not
            # reach the front, where it would spoil the card's own answer.
            atom["front"] = f"{front}\n\npart {i + 1} of {len(pieces)}"
            if i == 0:
                atom["id"] = card["id"]
            else:
                atom["id"] = next_atom_id(card["id"], used)
                used.add(atom["id"])
                new_atoms += 1
            out.append(atom)

    # Fold leftover "BOTH" onto the TCFD-tool sibling if it is still a tail.
    for card in out:
        if card["id"] == "fc_case_study_in_portfolio_management_institutional_swf_004_p5":
            back = card["back"].strip()
            if not back.lower().startswith("both"):
                card["back"] = (
                    "BOTH physical and transition risk. " + back.lstrip("• ").strip()
                )
                if not card["back"].startswith("•"):
                    card["back"] = "• " + card["back"]

    after = stats(out)
    ids = [c["id"] for c in out]
    assert len(ids) == len(set(ids)), "duplicate ids"
    kept = {c["id"] for c in cards}
    assert kept <= set(ids), "dropped original ids"
    print("before", before)
    print("after", after)
    print("cards split", split)
    print("new atoms", new_atoms)
    if after["over_49"]:
        print("still over 49", file=sys.stderr)
        return 1

    bundle["cards"] = out
    with open(PATH, "w", encoding="utf-8") as fh:
        json.dump(bundle, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
