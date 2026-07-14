#!/usr/bin/env python3
"""remove_inflection_dup.py - delete the duplicate inflection q2 and
renumber the remaining MCs. One-time content-integrity fix."""
import json

PATH = "CFAL3/Resources/question_bank.json"
CASE = "inflection_capital_case_scenario_derek_mulaney"
DROP = CASE + "_q2"

bank = json.load(open(PATH))
case = next(c for t in bank["topics"] for c in t["cases"]
            if c["id"] == CASE)

before = len(case["questions"])
q1 = next(q for q in case["questions"] if q["id"] == CASE + "_q1")
q2 = next(q for q in case["questions"] if q["id"] == DROP)
assert q1["stem"].strip() == q2["stem"].strip(), "not duplicates; abort"
assert q1["options"] == q2["options"], "not duplicates; abort"

case["questions"] = [q for q in case["questions"] if q["id"] != DROP]

# Renumber remaining MCs 1..n in order; essays keep their numbers.
n = 0
for q in case["questions"]:
    if q["type"] == "mc":
        n += 1
        q["number"] = n

json.dump(bank, open(PATH, "w"), indent=2, ensure_ascii=False)

# ---- assertions ----
bank = json.load(open(PATH))
tot = mc = 0
ids = set()
for t in bank["topics"]:
    for c in t["cases"]:
        for q in c["questions"]:
            tot += 1; ids.add(q["id"])
            if q["type"] == "mc": mc += 1
case = next(c for t in bank["topics"] for c in t["cases"]
            if c["id"] == CASE)
nums = [q["number"] for q in case["questions"]]
print(f"total={tot} mc={mc} case_questions={len(case['questions'])}")
print("case numbers:", nums)
assert tot == 490 and mc == 267
assert DROP not in ids
assert len(case["questions"]) == before - 1 == 7
assert nums == [1, 2, 3, 5, 6, 7, 8]
print("OK")
