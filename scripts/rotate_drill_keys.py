#!/usr/bin/env python3
import json, glob, collections
FILES = sorted(glob.glob("CFAL3/Resources/los_drills_r*.json"))
KEYS = ["A", "B", "C"]
dist_before, dist_after = collections.Counter(), collections.Counter()
rotated = total = 0
for path in FILES:
    bundle = json.load(open(path))
    counter = 0
    changed = False
    for group in bundle["drills"]:
        for q in group["questions"]:
            opts, corr = q.get("options") or {}, q.get("correct")
            if corr not in opts or sorted(opts) != KEYS: continue
            total += 1
            dist_before[corr] += 1
            target = KEYS[counter % 3]; counter += 1
            dist_after[target] += 1
            if target == corr: continue
            rats = q.get("rationales") or {}
            others = [k for k in KEYS if k != corr]
            slots = [k for k in KEYS if k != target]
            new_opts, new_rats = {}, {}
            new_opts[target] = opts[corr]
            if corr in rats: new_rats[target] = rats[corr]
            for old_k, new_k in zip(others, slots):
                new_opts[new_k] = opts[old_k]
                if old_k in rats: new_rats[new_k] = rats[old_k]
            q["options"] = {k: new_opts[k] for k in KEYS}
            if rats: q["rationales"] = {k: new_rats[k] for k in KEYS if k in new_rats}
            q["correct"] = target
            rotated += 1; changed = True
    if changed:
        json.dump(bundle, open(path, "w"), indent=2, ensure_ascii=False)
print("total:", total, "rotated:", rotated)
print("before:", dict(dist_before))
print("after: ", dict(dist_after))
assert total == 2625 and dist_after["A"] == dist_after["B"] == dist_after["C"] == 875
print("OK")
