#!/usr/bin/env python3
"""apply_notes_batch.py - apply a reading-notes content batch.
Authored batches replace the 'content' field wholesale per reading_id.
Usage:
    python3 scripts/apply_notes_batch.py content_batches/<batch>.json
"""
import json, sys

BANK = "CFAL3/Resources/reading_notes.json"

batch = json.load(open(sys.argv[1]))
assert batch["target"] == "reading_notes", batch["target"]
reps = {r["reading_id"]: r for r in batch["replacements"]}
expected = batch["expected"]["applied"]

notes = json.load(open(BANK))
applied = 0
for entry in notes["readings"]:
    r = reps.get(entry["reading_id"])
    if not r:
        continue
    for field, value in r.items():
        if field == "reading_id":
            continue
        entry[field] = value  # whole-field replacement, never merge
    applied += 1

json.dump(notes, open(BANK, "w"), indent=2, ensure_ascii=False)

print({"applied": applied})
assert applied == expected, (applied, expected)
assert applied == len(reps), "some reading_ids not found in reading_notes.json"

# post-apply sanity: no reading left as a stub
notes = json.load(open(BANK))
stubs = [e["reading_id"] for e in notes["readings"] if len(e.get("content", "")) < 2000]
print({"stub_readings_remaining": len(stubs)})
assert not stubs, stubs
print("OK")
