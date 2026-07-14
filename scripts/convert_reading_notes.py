#!/usr/bin/env python3
"""Convert CFA_L3_Notes_R*.docx files into bundled reading_notes.json."""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_NOTES_DIR = Path("/Users/brandonkeeny/Desktop/CFA L3 Exam/Review Sheets")
OUT_PATH = ROOT / "CFAL3/Resources/reading_notes.json"

# R-number → los_master reading_id
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
}

FILE_PATTERNS = {
    n: f"CFA_L3_Notes_R{n:02d}_*.docx" for n in READING_MAP
}


def docx_to_text(path: Path) -> str:
    result = subprocess.run(
        ["textutil", "-convert", "txt", "-stdout", str(path)],
        capture_output=True,
        text=True,
        check=True,
    )
    text = result.stdout
    # Normalize line endings and collapse excessive blank lines
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\n{4,}", "\n\n\n", text)
    return text.strip()


def parse_header(text: str) -> tuple[str, str, str]:
    topic_area = ""
    reading_title = ""
    orientation = ""

    lines = text.split("\n")
    for i, line in enumerate(lines[:12]):
        if line.startswith("Topic Area:"):
            topic_area = line.split(":", 1)[1].strip()
        elif line.startswith("Reading:"):
            reading_title = line.split(":", 1)[1].strip()
        elif line.startswith("Orientation."):
            orientation = line.strip()
            # orientation may continue on next lines until blank or LOS
            j = i + 1
            while j < len(lines) and lines[j].strip() and not lines[j].startswith("LOS "):
                orientation += " " + lines[j].strip()
                j += 1
            break
    return topic_area, reading_title, orientation


def find_docx(notes_dir: Path, reading_num: int) -> Path | None:
    matches = sorted(notes_dir.glob(FILE_PATTERNS[reading_num]))
    return matches[0] if matches else None


def notes_dir_from_args() -> Path:
    for i, arg in enumerate(sys.argv[1:], start=1):
        if arg == "--source-dir" and i < len(sys.argv) - 1:
            return Path(sys.argv[i + 1])
    return DEFAULT_NOTES_DIR


def main() -> int:
    notes_dir = notes_dir_from_args()
    if not notes_dir.exists():
        print(f"Notes directory not found: {notes_dir}")
        return 1

    readings = []
    for num, reading_id in READING_MAP.items():
        path = find_docx(notes_dir, num)
        if path is None:
            print(f"WARNING: missing notes for R{num:02d} ({reading_id})")
            continue
        text = docx_to_text(path)
        topic_area, reading_title, orientation = parse_header(text)
        readings.append(
            {
                "reading_id": reading_id,
                "reading_number": num,
                "source_file": path.name,
                "topic_area": topic_area,
                "title": reading_title or path.stem,
                "orientation": orientation,
                "content": text,
            }
        )
        print(f"R{num:02d}: {len(text):,} chars ← {path.name}")

    payload = {
        "version": 1,
        "source": f"CFA_L3_Notes_R01–R25 ({notes_dir.name})",
        "readings": readings,
    }
    OUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nWrote {len(readings)} readings → {OUT_PATH} ({OUT_PATH.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
