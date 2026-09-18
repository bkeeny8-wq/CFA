#!/usr/bin/env python3
"""P1 case coverage: unpark ethics primary_reading_ids, then human-retag the
known stem misses now that 2027 letters are stable.

Does not cosine-retag. Primary readings follow candidate_los in first-seen
order. Cap remains 3 LOS.

Usage:
    python3 scripts/apply_p1_case_coverage.py --dry-run
    python3 scripts/apply_p1_case_coverage.py
"""
from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANK = os.path.join(ROOT, "CFAL3/Resources/question_bank.json")
MASTER = os.path.join(ROOT, "CFAL3/Resources/los_master.json")
CODE = "code_and_standards"

# Stem tests this LOS (or these LOS), not the cosine-neighbor letters.
RETAGS: dict[str, list[str]] = {
    # Minkoff calendar spread — official calendar LOS is .g after the spine repair.
    "options_duane_armitage_duane_q2": ["options_strategies.g"],
    "options_duane_armitage_duane_essay_q6": ["options_strategies.g"],
    # Traditional vs risk-factor opportunity set — official alts .c.
    "elbe_society_the_elbe_society_q3": [
        "asset_allocation_to_alternative_investments.c"
    ],
    "elbe_society_the_elbe_society_essay_q6": [
        "asset_allocation_to_alternative_investments.c"
    ],
    "gambier_advisory_lucas_thompson_q2": [
        "asset_allocation_to_alternative_investments.c"
    ],
    "gambier_advisory_lucas_thompson_essay_q6": [
        "asset_allocation_to_alternative_investments.c"
    ],
    # Inflation / deflation implications for cash, bonds, equity, real estate.
    "cme_foundation_the_united_states_q1": [
        "capital_market_expectations_part_1_framework_and_macro_considerations.g"
    ],
    "cme_foundation_the_united_states_essay_q8": [
        "capital_market_expectations_part_1_framework_and_macro_considerations.g"
    ],
    # Singer–Terhaar / US real estate expected return — CME2 real-estate LOS.
    "cme_foundation_the_united_states_q3": [
        "capital_market_expectations_part_2_forecasting_asset_class_returns.e"
    ],
    "cme_foundation_the_united_states_essay_q5": [
        "capital_market_expectations_part_2_forecasting_asset_class_returns.e"
    ],
    # Implementation shortfall + execution-cost components; drop VWAP .b.
    "silverline_trading_pathway_essay_q2": [
        "trading_costs_and_electronic_markets.c",
        "trading_costs_and_electronic_markets.a",
    ],
    # Define Active Share vs active risk.
    "active_equity_investing_construction_lisette_langham_lisette_essay_q9": [
        "active_equity_investing_portfolio_construction.c"
    ],
    # FI mandate labels in a presentation, not LDI pathway.
    "overview_of_fi_danny_moynahan_danny_q1": [
        "overview_of_fixed_income_portfolio_management.a"
    ],
    # Athena IPO allocation: AMC consistency + Standard III(B) Fair Dealing.
    "athena_investment_services_case_scenario_essay_q7": [
        "asset_manager_code_of_professional_conduct.c",
        "guidance_standard_iii_duties_to_clients.a",
    ],
    # Ava Chan — liquidity / transparency / monitoring / IPS / suitability.
    "ava_chan_ava_chan_q1": ["asset_allocation_to_alternative_investments.g"],
    "ava_chan_ava_chan_q2": ["asset_allocation_to_alternative_investments.d"],
    "ava_chan_ava_chan_q4": ["asset_allocation_to_alternative_investments.h"],
    "ava_chan_ava_chan_essay_q5": [
        "case_study_in_portfolio_management_institutional_endowment.b",
        "asset_allocation_to_alternative_investments.g",
        "asset_allocation_to_alternative_investments.e",
    ],
    "ava_chan_ava_chan_essay_q6": ["asset_allocation_to_alternative_investments.d"],
    "ava_chan_ava_chan_essay_q7": ["an_overview_of_private_wealth_management.e"],
    "ava_chan_ava_chan_essay_q8": ["asset_allocation_to_alternative_investments.e"],
    # Ptolemy — Singer–Terhaar equity expected return is CME2, not CME1 growth.
    "ptolemy_foundation_the_ptolemy_foundation_q4": [
        "capital_market_expectations_part_2_forecasting_asset_class_returns.c"
    ],
    "ptolemy_foundation_the_ptolemy_foundation_essay_q7": [
        "capital_market_expectations_part_2_forecasting_asset_class_returns.c"
    ],
    "ptolemy_foundation_the_ptolemy_foundation_essay_q8": [
        "capital_market_expectations_part_2_forecasting_asset_class_returns.c",
        "capital_market_expectations_part_2_forecasting_asset_class_returns.d",
    ],
    # Epsilon — Active Share vs active risk is construction .c; ADV/size is .f.
    "active_equity_investing_construction_the_epsilon_institute_t_q3": [
        "active_equity_investing_portfolio_construction.c"
    ],
    "active_equity_investing_construction_the_epsilon_institute_t_q4": [
        "active_equity_investing_portfolio_construction.c"
    ],
    "active_equity_investing_construction_the_epsilon_institute_t_q5": [
        "active_equity_investing_portfolio_construction.f"
    ],
    "active_equity_investing_construction_the_epsilon_institute_t_essay_q8": [
        "active_equity_investing_portfolio_construction.c"
    ],
    "active_equity_investing_construction_the_epsilon_institute_t_essay_q9": [
        "active_equity_investing_portfolio_construction.c"
    ],
    "active_equity_investing_construction_the_epsilon_institute_t_essay_q10": [
        "active_equity_investing_portfolio_construction.f"
    ],
    # Gambier — governance / monitoring of an alts program is .h.
    "gambier_advisory_lucas_thompson_essay_q8": [
        "asset_allocation_to_alternative_investments.h"
    ],
    # Vitting — which AA approach Black suggested is the three-way compare.
    "vitting_teddy_brealer_q2": ["overview_of_asset_allocation.c"],
    # Roy's safety-first / shortfall vs a 5% target, not MVO recommend.
    "vitting_teddy_brealer_q5": ["principles_of_asset_allocation.h"],
    "vitting_teddy_brealer_essay_q10": ["principles_of_asset_allocation.h"],
    # Additional allocation issues → Monte Carlo / scenario robustness.
    "vitting_teddy_brealer_q6": ["principles_of_asset_allocation.e"],
    # Underfunded amount is an economic-balance-sheet calculation.
    "vitting_teddy_brealer_essay_q7": ["overview_of_asset_allocation.b"],
    # Heavy FI is implementation; 5% TAA bands are rebalancing.
    "vitting_teddy_brealer_essay_q9": [
        "overview_of_asset_allocation.i",
        "overview_of_asset_allocation.j",
    ],
    # Ptolemy — cycle phase for equities; Taylor's rule is monetary policy.
    "ptolemy_foundation_the_ptolemy_foundation_q3": [
        "capital_market_expectations_part_1_framework_and_macro_considerations.f"
    ],
    "ptolemy_foundation_the_ptolemy_foundation_essay_q6": [
        "capital_market_expectations_part_1_framework_and_macro_considerations.h"
    ],
    # Data-quality / forecast-challenge stems, not the CME framework row.
    "minglu_li_redd_partners_essay_q5": [
        "capital_market_expectations_part_1_framework_and_macro_considerations.b"
    ],
    "ted_rogers_ted_rogers_q2": [
        "capital_market_expectations_part_1_framework_and_macro_considerations.b"
    ],
    "ted_rogers_ted_rogers_essay_q5": [
        "capital_market_expectations_part_1_framework_and_macro_considerations.b"
    ],
    "ted_rogers_ted_rogers_essay_q6": [
        "capital_market_expectations_part_1_framework_and_macro_considerations.b"
    ],
    "ted_rogers_ted_rogers_essay_q7": [
        "capital_market_expectations_part_1_framework_and_macro_considerations.b",
        "capital_market_expectations_part_1_framework_and_macro_considerations.e",
    ],
    # Heights — equity overlay vs IR hedge vs variance-swap tail hedge.
    "swaps_heights_case_ford_tyron_q2": [
        "swaps_forwards_and_futures_strategies.c"
    ],
    "swaps_heights_case_ford_tyron_q3": [
        "swaps_forwards_and_futures_strategies.d"
    ],
    "swaps_heights_case_ford_tyron_q4": [
        "swaps_forwards_and_futures_strategies.c"
    ],
    "swaps_heights_case_ford_tyron_essay_q5": [
        "swaps_forwards_and_futures_strategies.a"
    ],
    "swaps_heights_case_ford_tyron_essay_q7": [
        "swaps_forwards_and_futures_strategies.d"
    ],
    "swaps_heights_case_ford_tyron_essay_q8": ["options_strategies.i"],
    # Silverline — recommend a strategy / best-execution policy, not VWAP.
    "silverline_trading_pathway_essay_q1": [
        "trade_strategy_and_execution.d",
        "trading_costs_and_electronic_markets.a",
    ],
    "silverline_trading_pathway_essay_q4": [
        "trade_strategy_and_execution.i"
    ],
    # Moynahan liquidity statements are the Overview-of-FI liquidity LOS.
    "overview_of_fi_danny_moynahan_danny_q3": [
        "overview_of_fixed_income_portfolio_management.c"
    ],
    "overview_of_fi_danny_moynahan_danny_essay_q9": [
        "overview_of_fixed_income_portfolio_management.c"
    ],
    # Liability-based vs total-return is describe-LDI, not cash-flow matching.
    "overview_of_fi_danny_moynahan_danny_essay_q10": [
        "overview_of_fixed_income_portfolio_management.g",
        "liability_driven_and_index_based_strategies.d",
    ],
    # Elbe PE impact is alts roles; drop the SWF risk tag on a society case.
    "elbe_society_the_elbe_society_q1": [
        "asset_allocation_to_alternative_investments.a"
    ],
    "elbe_society_the_elbe_society_essay_q8": [
        "asset_allocation_to_alternative_investments.e",
        "asset_allocation_to_alternative_investments.a",
    ],
    # Gambier FI→RE is roles + risk-mitigator, not monitoring.
    "gambier_advisory_lucas_thompson_q1": [
        "asset_allocation_to_alternative_investments.a",
        "asset_allocation_to_alternative_investments.b",
    ],
    "gambier_advisory_lucas_thompson_essay_q5": [
        "asset_allocation_to_alternative_investments.a",
        "asset_allocation_to_alternative_investments.b",
    ],
    # Nonventure PE / direct lending — type-specific considerations, not SWF.
    "gambier_advisory_lucas_thompson_essay_q7": [
        "asset_allocation_to_alternative_investments.d"
    ],
    # Characterize the model, don't also recommend it.
    "remington_preston_remington_q3": ["principles_of_asset_allocation.a"],
    # TAA value-added, not GMP / economic balance sheet.
    "olivinia_oliviniacase_q5": [
        "asset_allocation_with_real_world_constraints.d"
    ],
    "olivinia_oliviniacase_essay_q7": [
        "asset_allocation_with_real_world_constraints.d"
    ],
    "olivinia_oliviniacase_essay_q8": ["overview_of_asset_allocation.a"],
    # Teamwork style return / benchmark type.
    "teamwork_advisory_teamwork_advisory_q1": [
        "portfolio_performance_evaluation.j"
    ],
    "teamwork_advisory_teamwork_advisory_q2": [
        "portfolio_performance_evaluation.h"
    ],
    # Duane spreads: structure/breakeven is .f; skew-and-objective is .h+.i.
    "options_duane_armitage_duane_essay_q5": [
        "options_strategies.f",
        "options_strategies.i",
    ],
    "options_duane_armitage_duane_essay_q7": ["options_strategies.f"],
    "options_duane_armitage_duane_essay_q8": [
        "options_strategies.h",
        "options_strategies.i",
    ],
    # Lisette diversified multi-factor is Active Share vs active risk.
    "active_equity_investing_construction_lisette_langham_lisette_q4": [
        "active_equity_investing_portfolio_construction.c"
    ],
    "active_equity_investing_construction_lisette_langham_lisette_essay_q8": [
        "active_equity_investing_portfolio_construction.b"
    ],
}


def readings_from_los(los_ids: list[str], los_by_id: dict) -> list[str]:
    seen: list[str] = []
    for lid in los_ids:
        los = los_by_id.get(lid)
        if not los:
            continue
        rid = los.get("reading_id")
        if rid and rid not in seen:
            seen.append(rid)
    return seen


def is_parked_ethics(question: dict, los_by_id: dict) -> bool:
    prim = question.get("primary_reading_ids") or []
    if prim != [CODE]:
        return False
    readings = readings_from_los(question.get("candidate_los") or [], los_by_id)
    return any(rid != CODE for rid in readings)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    master = json.load(open(MASTER, encoding="utf-8"))
    los_by_id = {item["id"]: item for item in master["los_flat"]}
    known = set(los_by_id)

    for lid in (x for tags in RETAGS.values() for x in tags):
        if lid not in known:
            print(f"unknown retag LOS {lid}", file=sys.stderr)
            return 1

    bank = json.load(open(BANK, encoding="utf-8"))
    by_id: dict[str, dict] = {}
    for topic in bank["topics"]:
        for case in topic["cases"]:
            for question in case["questions"]:
                by_id[question["id"]] = question

    missing = [qid for qid in RETAGS if qid not in by_id]
    if missing:
        print({"missing_retag_ids": missing}, file=sys.stderr)
        return 1

    parked_before = [
        q["id"]
        for q in by_id.values()
        if is_parked_ethics(q, los_by_id)
    ]

    ethics_primary = 0
    for qid in parked_before:
        q = by_id[qid]
        readings = readings_from_los(q.get("candidate_los") or [], los_by_id)
        if not readings:
            print(f"parked {qid} has no resolvable readings", file=sys.stderr)
            return 1
        q["primary_reading_ids"] = readings
        ethics_primary += 1

    retagged = 0
    retag_details = []
    for qid, tags in RETAGS.items():
        q = by_id[qid]
        if len(tags) > 3:
            print(f"{qid} has {len(tags)} tags", file=sys.stderr)
            return 1
        before = list(q.get("candidate_los") or [])
        before_prim = list(q.get("primary_reading_ids") or [])
        q["candidate_los"] = list(tags)
        q["primary_reading_ids"] = readings_from_los(tags, los_by_id)
        retagged += 1
        retag_details.append(
            {
                "id": qid,
                "los_before": before,
                "los_after": list(tags),
                "prim_before": before_prim,
                "prim_after": q["primary_reading_ids"],
            }
        )

    parked_after = [
        q["id"]
        for q in by_id.values()
        if is_parked_ethics(q, los_by_id)
    ]

    # Coverage sanity: Standard I–VII readings now have case questions.
    coverage: dict[str, int] = {}
    empty = []
    wide = []
    unknown = []
    missing_reading = []
    for q in by_id.values():
        tags = q.get("candidate_los") or []
        if not tags:
            empty.append(q["id"])
        if len(tags) > 3:
            wide.append(q["id"])
        for lid in tags:
            if lid not in known:
                unknown.append(f"{q['id']} -> {lid}")
        prim = q.get("primary_reading_ids") or []
        if not prim:
            missing_reading.append(q["id"])
        for rid in prim:
            coverage[rid] = coverage.get(rid, 0) + 1

    standards = [
        "guidance_standard_i_professionalism",
        "guidance_standard_ii_integrity_capital_markets",
        "guidance_standard_iii_duties_to_clients",
        "guidance_standard_iv_duties_to_employers",
        "guidance_standard_v_investment_analysis",
        "guidance_standard_vi_conflicts_of_interest",
        "guidance_standard_vii_responsibilities",
        "asset_manager_code_of_professional_conduct",
    ]
    std_counts = {rid: coverage.get(rid, 0) for rid in standards}

    print(
        {
            "parked_before": len(parked_before),
            "ethics_primary_updated": ethics_primary,
            "parked_after": len(parked_after),
            "retagged": retagged,
            "standard_case_coverage": std_counts,
        }
    )
    for row in retag_details:
        print(
            f"  {row['id']}\n"
            f"    los {row['los_before']} -> {row['los_after']}\n"
            f"    prim {row['prim_before']} -> {row['prim_after']}"
        )

    assert not empty, empty[:10]
    assert not wide, wide[:10]
    assert not unknown, unknown[:10]
    assert not missing_reading, missing_reading[:10]
    assert len(parked_after) == 0, parked_after
    # First pass unparked 47; later passes find none still parked.
    assert ethics_primary in (0, 47), ethics_primary
    assert retagged == len(RETAGS)
    for rid, n in std_counts.items():
        assert n > 0, rid

    if args.dry_run:
        print("dry-run; not writing")
        return 0

    with open(BANK, "w", encoding="utf-8") as fh:
        json.dump(bank, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
