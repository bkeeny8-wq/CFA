#!/usr/bin/env python3
"""restructure_six_books.py - reorganize question_bank.json topics into the
six curriculum books (matching los_master area IDs), delete empty ghost cases,
and apply clean topic names. One-time structural fix."""
import json, collections

PATH = "CFAL3/Resources/question_bank.json"

BOOKS = [
    ("asset_allocation", "Asset Allocation"),
    ("portfolio_construction", "Portfolio Construction"),
    ("performance_measurement", "Performance Measurement"),
    ("derivatives_and_risk_management", "Derivatives and Risk Management"),
    ("ethical_and_professional_standards", "Ethical and Professional Standards"),
    ("portfolio_management_pathway", "Portfolio Management Pathway"),
]

# ghost cases: zero questions, placeholder vignettes
DELETE_CASES = {
    "ldi_pm_pathway_pavonia_pavonia_ldi",
    "betty_betsy_case",
    "seeblick_cemetery_foundation",
    "vision_2020_capital_partners_case_scenario",
    "wryte_capital_management_case_scenario",
    "rayne_brokers_case_scenario",
}

# old topic id -> book (with per-case exceptions below)
TOPIC_MAP = {
    "cme_1": "asset_allocation",
    "cme_2": "asset_allocation",
    "asset_allocation": "asset_allocation",
    "derivatives": "derivatives_and_risk_management",
    "alt_investments": "portfolio_construction",
    "institutional_investors": "portfolio_construction",
    "performance_evaluation": "performance_measurement",
    "manager_selection": "performance_measurement",
    "ethics": "ethical_and_professional_standards",
    "equity": "portfolio_management_pathway",
    "fixed_income": "portfolio_management_pathway",
    "trade_strategy_execution_volume_2_of_the_pm_pathwaymod_7": "portfolio_management_pathway",
}
CASE_EXCEPTIONS = {
    # core-volume readings living inside mixed topics
    "overview_of_fi_danny_moynahan_danny": "portfolio_construction",
    "silverline_trading_pathway": "portfolio_construction",
}

bank = json.load(open(PATH))
q_before = sum(len(c["questions"]) for t in bank["topics"] for c in t["cases"])
cases_before = sum(len(t["cases"]) for t in bank["topics"])

buckets = {bid: [] for bid, _ in BOOKS}
deleted = 0
for t in bank["topics"]:
    base = TOPIC_MAP.get(t["id"])
    assert base, f"unmapped topic {t['id']}"
    for c in t["cases"]:
        if c["id"] in DELETE_CASES:
            assert not c["questions"], f"{c['id']} not empty; abort"
            deleted += 1
            continue
        bid = CASE_EXCEPTIONS.get(c["id"], base)
        c["topic_id"] = bid
        buckets[bid].append(c)

bank["topics"] = [
    {"id": bid, "name": name, "cases": buckets[bid]} for bid, name in BOOKS
]
json.dump(bank, open(PATH, "w"), indent=2, ensure_ascii=False)

# ---- assertions ----
bank = json.load(open(PATH))
q_after = sum(len(c["questions"]) for t in bank["topics"] for c in t["cases"])
cases_after = sum(len(t["cases"]) for t in bank["topics"])
print(f"topics={len(bank['topics'])} cases={cases_before}->{cases_after} "
      f"questions={q_before}->{q_after} deleted_ghost_cases={deleted}")
for t in bank["topics"]:
    print(f"  {t['id']:36s} cases={len(t['cases']):2d} "
          f"q={sum(len(c['questions']) for c in t['cases'])}")
assert len(bank["topics"]) == 6
assert deleted == 6 and cases_after == cases_before - 6
assert q_after == q_before, "questions lost"
ids = [q["id"] for t in bank["topics"] for c in t["cases"] for q in c["questions"]]
assert len(ids) == len(set(ids)), "duplicate ids introduced"
for t in bank["topics"]:
    for c in t["cases"]:
        assert c["topic_id"] == t["id"], (c["id"], c["topic_id"], t["id"])
print("OK")
