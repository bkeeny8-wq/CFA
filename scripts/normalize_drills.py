#!/usr/bin/env python3
"""normalize_drills.py - remove giveaway formatting from LOS drill options.
Run from repo root. Edits CFAL3/Resources/los_drills_r*.json in place and
writes content_triage/drill_distractor_queue.json + drill_trim_audit.csv."""
import json, glob, re, os, csv

FILES = sorted(glob.glob("CFAL3/Resources/los_drills_r*.json"))
PAT_VALUE_DASH = re.compile(
    r"^\s*([-+]?[$\u20ac\u00a3\u00a5]?\s?[\d,]+\.?\d*\s*(?:%|bps|x|million|billion)?\.?)"
    r"\s*[\u2014\u2013-]{1,2}\s+(.{20,})$", re.S)
PAT_TRAILING = re.compile(
    r"(?:\u2248|=|\u2192)\s*([-+]?[$\u20ac\u00a3\u00a5]?\s?[\d,]+\.?\d*"
    r"\s*(?:%|bps|x|million|billion)?)[^\d%]*$")

def clause_cut(text):
    for pat in ["; ", " \u2014 ", " \u2013 ", ": "]:
        i = text.find(pat, 25)
        if i != -1:
            return i
    i = text.find(". ", 25)
    return i + 1 if i != -1 else -1

def is_giveaway(opts, corr):
    lc = len(opts[corr])
    lo = [len(v) for k, v in opts.items() if k != corr]
    return lc > 120 and lc > 3 * max(lo)

stats = {"A": 0, "B": 0, "C": 0}
queue, audit = [], []
for path in FILES:
    bundle = json.load(open(path))
    changed = False
    for group in bundle["drills"]:
        for q in group["questions"]:
            opts = q.get("options") or {}
            corr = q.get("correct")
            if corr not in opts or len(opts) != 3 or not is_giveaway(opts, corr):
                continue
            text = opts[corr]
            rats = q.setdefault("rationales", {})
            m = PAT_VALUE_DASH.match(text)
            if m:
                value, deriv = m.group(1).strip(), m.group(2).strip()
                opts[corr] = value if value.endswith(".") else value + "."
                rats[corr] = (deriv + "\n\n" + rats.get(corr, "")).strip()
                stats["A"] += 1; changed = True
                audit.append((q["id"], "A", text, opts[corr]))
                continue
            m2 = PAT_TRAILING.search(text)
            if m2 and len(m2.group(1).strip()) >= 2:
                value = m2.group(1).strip()
                opts[corr] = value if value.endswith(".") else value + "."
                rats[corr] = (text + "\n\n" + rats.get(corr, "")).strip()
                stats["A"] += 1; changed = True
                audit.append((q["id"], "A", text, opts[corr]))
                continue
            cut = clause_cut(text)
            trimmed = text[:cut].rstrip(" ;:\u2014\u2013-") if cut >= 25 else ""
            if len(trimmed) >= 20:
                opts[corr] = trimmed if trimmed.endswith(".") else trimmed + "."
                rats[corr] = ("Full statement: " + text + "\n\n"
                              + rats.get(corr, "")).strip()
                stats["B"] += 1; changed = True
                audit.append((q["id"], "B", text, opts[corr]))
            else:
                stats["C"] += 1
                queue.append({"id": q["id"], "reading_id": q["reading_id"],
                              "correct": corr, "options": dict(opts)})
    if changed:
        json.dump(bundle, open(path, "w"), indent=2, ensure_ascii=False)

os.makedirs("content_triage", exist_ok=True)
json.dump(queue, open("content_triage/drill_distractor_queue.json", "w"),
          indent=2, ensure_ascii=False)
with open("content_triage/drill_trim_audit.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["id", "tier", "original_option", "new_option"])
    w.writerows(audit)
print(stats)
assert stats == {"A": 46, "B": 1921, "C": 181}, stats
print("OK")
