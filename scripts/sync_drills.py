#!/usr/bin/env python3
"""Wire los_drills_r*.json into the app (index + Xcode) — no AI, no re-generation."""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "CFAL3/Resources"
INDEX_PATH = RESOURCES / "los_drills_index.json"

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


def reading_id_from_bundle(path: Path) -> tuple[str, int | None]:
    data = json.loads(path.read_text(encoding="utf-8"))
    reading_id = data.get("reading_id")
    if not reading_id and data.get("drills"):
        reading_id = data["drills"][0].get("reading_id")
    match = re.search(r"los_drills_r(\d+)", path.stem)
    reading_number = int(match.group(1)) if match else None
    if not reading_id and reading_number in READING_MAP:
        reading_id = READING_MAP[reading_number]
    return reading_id, reading_number


def main() -> int:
    drill_files = sorted(RESOURCES.glob("los_drills_r*.json"))
    if not drill_files:
        print("No los_drills_r*.json files found.")
        return 1

    bundles = []
    total_q = 0
    for path in drill_files:
        data = json.loads(path.read_text(encoding="utf-8"))
        n = sum(len(g["questions"]) for g in data["drills"])
        total_q += n
        reading_id, reading_number = reading_id_from_bundle(path)
        if not reading_id:
            print(f"SKIP {path.name}: cannot resolve reading_id")
            continue
        bundles.append(
            {
                "reading_id": reading_id,
                "filename": path.stem,
                "reading_number": reading_number,
            }
        )
        print(f"  {path.name}: {n} questions → {reading_id[:50]}…")

    INDEX_PATH.write_text(json.dumps({"bundles": bundles}, indent=2) + "\n", encoding="utf-8")
    print(f"\nIndex: {len(bundles)} bundles, {total_q} drill questions")

    subprocess.run(
        [sys.executable, str(ROOT / "scripts/generate_xcodeproj.py")],
        check=True,
        cwd=ROOT,
    )
    print("Xcode project regenerated. Rebuild in Xcode (⌘R).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
