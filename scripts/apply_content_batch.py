#!/usr/bin/env python3
"""apply_content_batch.py - apply a delivered content batch to the bundled
content files. Batches are authored in the content pipeline (Claude) and
applied here mechanically. Usage:
    python3 scripts/apply_content_batch.py content_batches/<batch>.json
"""
import json, sys, glob

batch = json.load(open(sys.argv[1]))
target = batch["target"]              # "question_bank" | "drills"
replacements = {r["id"]: r for r in batch["replacements"]}
expected = batch["expected"]          # e.g. {"applied": 40}

applied = 0
def patch(q):
    global applied
    r = replacements.get(q["id"])
    if not r:
        return
    for field, value in r.items():
        if field == "id":
            continue
        q[field] = value              # whole-field replacement, never merge
    applied += 1

if target == "question_bank":
    path = "CFAL3/Resources/question_bank.json"
    bank = json.load(open(path))
    for t in bank["topics"]:
        for c in t["cases"]:
            for q in c["questions"]:
                patch(q)
    json.dump(bank, open(path, "w"), indent=2, ensure_ascii=False)
elif target == "drills":
    for path in sorted(glob.glob("CFAL3/Resources/los_drills_r*.json")):
        bundle = json.load(open(path))
        before = applied
        for g in bundle["drills"]:
            for q in g["questions"]:
                patch(q)
        if applied != before:
            json.dump(bundle, open(path, "w"), indent=2, ensure_ascii=False)
else:
    sys.exit(f"unknown target {target}")

print({"applied": applied})
assert applied == expected["applied"], (applied, expected)
assert applied == len(replacements), \
    "some replacement IDs were not found in the target files"
print("OK")
