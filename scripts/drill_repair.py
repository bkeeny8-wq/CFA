#!/usr/bin/env python3
"""Apply targeted repairs to drills the audit found broken.

Each repair names the question, the field, the exact text as it stands and the
replacement. A mismatch on the old text aborts the whole run, so a repair can
never land on a question that has moved under it.

Each entry of the spec carries a "why" naming the audit rule it answers, so the
record of what was repaired and on what grounds travels with the repair itself.

    python3 -I scripts/drill_repair.py repairs.json [--dry-run]
"""
import glob
import json
import os
import sys

ROOT = "/home/user/CFA/CFAL3/Resources"


def main():
    spec = json.load(open(sys.argv[1]))
    dry = "--dry-run" in sys.argv

    # index every question to its file
    where = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "los_drills_r*.json"))):
        for group in json.load(open(path)).get("drills", []):
            for q in group.get("questions", []):
                where[q["id"]] = path

    planned = {}
    for r in spec:
        qid, field, old, new = r["id"], r["field"], r["old"], r["new"]
        path = where.get(qid)
        if path is None:
            sys.exit(f"ABORT {qid}: not in corpus")
        data = planned.setdefault(path, json.load(open(path)))
        found = None
        for group in data.get("drills", []):
            for q in group.get("questions", []):
                if q["id"] == qid:
                    found = q
        if found is None:
            sys.exit(f"ABORT {qid}: not in {path}")

        if field == "stem":
            cur, setter = found.get("stem"), lambda v: found.__setitem__("stem", v)
        elif field.startswith("opt."):
            L = field[4:]
            cur = found["options"].get(L)
            setter = lambda v, L=L, f=found: f["options"].__setitem__(L, v)
        elif field.startswith("rat."):
            L = field[4:]
            cur = (found.get("rationales") or {}).get(L)
            setter = lambda v, L=L, f=found: f["rationales"].__setitem__(L, v)
        else:
            sys.exit(f"ABORT {qid}: unknown field {field}")

        if cur != old:
            sys.exit(f"ABORT {qid} {field}: text does not match\n"
                     f"  expected {old!r}\n  found    {cur!r}")
        setter(new)
        print(f"ok  {qid:26} {field:8} -> {new[:70]!r}")

    if dry:
        print(f"\ndry run: {len(spec)} repairs matched, {len(planned)} files untouched")
        return
    for path, data in planned.items():
        with open(path, "w") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
    print(f"\nwrote {len(planned)} files, {len(spec)} repairs")


if __name__ == "__main__":
    main()
