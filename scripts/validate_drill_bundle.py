#!/usr/bin/env python3
"""Validate los_drills_rN.json against schema and los_master."""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOS_MASTER = ROOT / "CFAL3/Resources/los_master.json"
READING_NOTES = ROOT / "CFAL3/Resources/reading_notes.json"

READING_MAP = {
    1: "capital_market_expectations_part_1_framework_and_macro_considerations",
    2: "capital_market_expectations_part_2_forecasting_asset_class_returns",
    3: "overview_of_asset_allocation",
    4: "principles_of_asset_allocation",
    5: "asset_allocation_with_real_world_constraints",
    6: "overview_of_equity_portfolio_management",
    7: "overview_of_fixed_income_portfolio_management",
    8: "asset_allocation_to_alternative_investments",
    9: "an_overview_of_private_wealth_management",
    10: "portfolio_management_for_institutional_investors",
    11: "trading_costs_and_electronic_markets",
    12: "case_study_in_portfolio_management_institutional_swf",
    13: "portfolio_performance_evaluation",
    14: "investment_manager_selection",
    15: "overview_of_the_global_investment_performance_standards",
    16: "options_strategies",
    17: "swaps_forwards_and_futures_strategies",
    18: "currency_management_an_introduction",
    19: "index_based_equity_strategies",
    20: "active_equity_investing_strategies",
    21: "active_equity_investing_portfolio_construction",
    22: "liability_driven_and_index_based_strategies",
    23: "yield_curve_strategies",
    24: "fixed_income_active_management_credit_strategies",
    25: "trade_strategy_and_execution",
    26: "case_study_in_portfolio_management_institutional_endowment",
    27: "code_and_standards",
    28: "guidance_standard_i_professionalism",
    29: "guidance_standard_ii_integrity_capital_markets",
    30: "guidance_standard_iii_duties_to_clients",
    31: "guidance_standard_iv_duties_to_employers",
    32: "guidance_standard_v_investment_analysis",
    33: "guidance_standard_vi_conflicts_of_interest",
    34: "guidance_standard_vii_responsibilities",
    35: "application_of_code_and_standards_l3",
}


def reading_number_for_id(reading_id: str) -> int | None:
    notes = json.loads(READING_NOTES.read_text(encoding="utf-8"))
    for entry in notes["readings"]:
        if entry["reading_id"] == reading_id:
            return entry["reading_number"]
    for num, rid in READING_MAP.items():
        if rid == reading_id:
            return num
    return None


def file_reading_number(path: Path) -> int | None:
    match = re.search(r"los_drills_r(\d+)", path.stem)
    return int(match.group(1)) if match else None


def validate(path: Path) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    los = json.loads(LOS_MASTER.read_text(encoding="utf-8"))
    los_by_id = {item["id"]: item for item in los["los_flat"]}

    errors = []
    warnings = []
    if data.get("schema_version") != 2:
        errors.append("schema_version must be 2")

    drills = data.get("drills", [])
    if not drills:
        errors.append("no drills")

    reading_id = data.get("reading_id") or (drills[0].get("reading_id") if drills else None)
    file_num = file_reading_number(path)
    content_num = reading_number_for_id(reading_id) if reading_id else None
    if file_num and content_num and file_num != content_num:
        errors.append(
            f"filename is R{file_num} but reading_id '{reading_id}' is app R{content_num} "
            f"({READING_MAP.get(content_num, reading_id)}) — rename to los_drills_r{content_num}.json"
        )
    if file_num and reading_id and READING_MAP.get(file_num) and READING_MAP[file_num] != reading_id:
        warnings.append(
            f"READING_MAP expects R{file_num}={READING_MAP[file_num]} but bundle has {reading_id}"
        )

    for group in drills:
        los_id = group.get("los_id")
        if los_id not in los_by_id:
            errors.append(f"unknown los_id: {los_id}")
        qs = group.get("questions", [])
        if not qs:
            errors.append(f"{los_id}: no questions")
        for q in qs:
            for field in ("id", "stem", "options", "correct", "rationales", "primary_los", "type"):
                if field not in q:
                    errors.append(f"{q.get('id', '?')}: missing {field}")
            if q.get("type") != "mc":
                errors.append(f"{q['id']}: type must be mc")
            if set(q.get("options", {})) != {"A", "B", "C"}:
                errors.append(f"{q['id']}: options must be A/B/C")
            if q.get("correct") not in {"A", "B", "C"}:
                errors.append(f"{q['id']}: invalid correct answer")
            if q.get("primary_los") != los_id:
                errors.append(f"{q['id']}: primary_los mismatch")

    if warnings:
        for w in warnings:
            print("WARN:", w)

    if errors:
        for e in errors:
            print("ERROR:", e)
        return 1

    total = sum(len(g["questions"]) for g in drills)
    print(f"OK: {path.name} — {len(drills)} LOS groups, {total} questions")
    return 0


if __name__ == "__main__":
    paths = [Path(p) for p in sys.argv[1:]] or sorted((ROOT / "CFAL3/Resources").glob("los_drills_r*.json"))
    code = 0
    for p in paths:
        code |= validate(p)
    sys.exit(code)
