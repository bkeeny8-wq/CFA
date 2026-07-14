#!/usr/bin/env python3
"""triage_report.py - machine-readable content-gap report for the v3 bank.
Run from repo root. Writes content_triage/triage_report.json."""
import json, os

BANK = "CFAL3/Resources/question_bank.json"
BUCKET_FLAGS = ["no_correct", "no_rationales", "partial_rationales",
                "rationale_mismatch", "stem_options_mismatch"]
buckets = {k: [] for k in BUCKET_FLAGS + ["empty_candidate_los"]}

bank = json.load(open(BANK))
for topic in bank["topics"]:
    for case in topic["cases"]:
        for q in case["questions"]:
            entry = {"id": q["id"], "case_id": case["id"],
                     "topic_id": topic["id"], "type": q["type"],
                     "number": q["number"], "stem": q["stem"][:120]}
            for flag in q.get("data_quality_flags", []):
                if flag in buckets:
                    buckets[flag].append(entry)
            if not q.get("candidate_los"):
                buckets["empty_candidate_los"].append(entry)

os.makedirs("content_triage", exist_ok=True)
json.dump(buckets, open("content_triage/triage_report.json", "w"),
          indent=2, ensure_ascii=False)
counts = {k: len(v) for k, v in buckets.items()}
print(counts)
expected = {"no_correct": 0, "no_rationales": 0, "partial_rationales": 0,
            "rationale_mismatch": 0, "stem_options_mismatch": 0,
            "empty_candidate_los": 0}
assert counts == expected, (counts, expected)
print("OK -> content_triage/triage_report.json")
