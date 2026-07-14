#!/usr/bin/env python3
"""Extract CFA L3 Archive.zip and sync bundled app resources."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "CFAL3/Resources"
DEFAULT_ARCHIVE = Path("/Users/brandonkeeny/Desktop/CFA L3 Exam/Archive.zip")
FALLBACK_NOTES = Path("/Users/brandonkeeny/Desktop/CFA L3 Exam/Review Sheets")

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


def extract_archive(archive: Path) -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="cfal3_archive_"))
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(tmp)
    return tmp


def find_notes_dir(root: Path) -> Path | None:
    docx = sorted(root.rglob("CFA_L3_Notes_R*.docx"))
    if not docx:
        return None
    return docx[0].parent


def find_drill_files(root: Path) -> list[Path]:
    return sorted(root.rglob("los_drills_r*.json"))


def find_json_files(root: Path, name: str) -> list[Path]:
    return sorted(root.rglob(name))


def copy_drills(files: list[Path]) -> list[str]:
    copied: list[str] = []
    for src in files:
        dest = RESOURCES / src.name
        shutil.copy2(src, dest)
        copied.append(src.stem)
        print(f"  drill bundle ← {src.name}")
    return copied


def build_drill_index(drill_stems: list[str]) -> None:
    bundles = []
    for stem in sorted(drill_stems):
        path = RESOURCES / f"{stem}.json"
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        reading_id = data.get("reading_id")
        if not reading_id and data.get("drills"):
            reading_id = data["drills"][0].get("reading_id")
        match = re.search(r"los_drills_r(\d+)", stem)
        reading_number = int(match.group(1)) if match else None
        if not reading_id and reading_number in READING_MAP:
            reading_id = READING_MAP[reading_number]
        if not reading_id:
            print(f"  WARNING: could not resolve reading_id for {stem}")
            continue
        bundles.append(
            {
                "reading_id": reading_id,
                "filename": stem,
                "reading_number": reading_number,
            }
        )

    index_path = RESOURCES / "los_drills_index.json"
    index_path.write_text(
        json.dumps({"bundles": bundles}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"  los_drills_index.json → {len(bundles)} bundle(s)")


def copy_bank_json(files: list[Path], dest_name: str) -> bool:
    if not files:
        return False
    src = max(files, key=lambda p: p.stat().st_mtime)
    dest = RESOURCES / dest_name
    shutil.copy2(src, dest)
    print(f"  {dest_name} ← {src}")
    return True


def convert_notes(notes_dir: Path) -> None:
    script = ROOT / "scripts/convert_reading_notes.py"
    subprocess.run(
        [sys.executable, str(script), "--source-dir", str(notes_dir)],
        check=True,
    )


def inventory(root: Path) -> dict[str, list[str]]:
    return {
        "notes_docx": [p.name for p in sorted(root.rglob("CFA_L3_Notes_R*.docx"))],
        "drill_json": [p.name for p in find_drill_files(root)],
        "question_bank": [p.name for p in find_json_files(root, "question_bank.json")],
        "los_master": [p.name for p in find_json_files(root, "los_master.json")],
        "topics": [p.name for p in find_json_files(root, "topics.json")],
    }


def main() -> int:
    archive = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_ARCHIVE
    if not archive.exists():
        print(f"Archive not found: {archive}")
        return 1

    print(f"Extracting {archive} …")
    extract_root = extract_archive(archive)
    try:
        items = inventory(extract_root)
        print("\nArchive inventory:")
        for key, names in items.items():
            print(f"  {key}: {len(names)}")
            for name in names[:5]:
                print(f"    - {name}")
            if len(names) > 5:
                print(f"    … +{len(names) - 5} more")

        notes_dir = find_notes_dir(extract_root)
        if notes_dir is None and FALLBACK_NOTES.exists():
            print(f"\nNo notes in archive; using {FALLBACK_NOTES}")
            notes_dir = FALLBACK_NOTES

        if notes_dir:
            print(f"\nConverting reading notes from {notes_dir} …")
            convert_notes(notes_dir)
        else:
            print("\nWARNING: no reading notes found")

        drill_files = find_drill_files(extract_root)
        if drill_files:
            print(f"\nCopying {len(drill_files)} drill bundle(s) …")
            stems = copy_drills(drill_files)
            build_drill_index(stems)
        else:
            print("\nNo los_drills_*.json in archive (existing bundles kept)")
            existing = sorted(RESOURCES.glob("los_drills_r*.json"))
            build_drill_index([p.stem for p in existing])

        for src_name, dest_name in [
            ("question_bank.json", "question_bank.json"),
            ("los_master.json", "los_master.json"),
            ("topics.json", "topics.json"),
        ]:
            files = find_json_files(extract_root, src_name)
            if files:
                copy_bank_json(files, dest_name)

        print("\nRegenerating Xcode project …")
        subprocess.run(
            [sys.executable, str(ROOT / "scripts/generate_xcodeproj.py")],
            check=True,
            cwd=ROOT,
        )
        print("\nDone.")
        return 0
    finally:
        shutil.rmtree(extract_root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
