#!/usr/bin/env python3
"""Strip unrendered markdown from all LOS drill stems and options.

The drill generator emitted *emphasis* markdown that the app renders as
literal asterisks (2,615 of 2,625 stems affected). This converts
*text* -> text in every stem and option across los_drills_r*.json,
leaves everything else byte-identical, and reports per-file counts.

Run from repo root:  python3 scripts/fix_drills_markdown.py
"""
import json, glob, re, sys

PAT = re.compile(r'\*([^*\n]+)\*')

def clean(s: str) -> str:
    prev = None
    while prev != s:
        prev = s
        s = PAT.sub(r'\1', s)
    return s

total = files = 0
for path in sorted(glob.glob('CFAL3/Resources/los_drills_r*.json')):
    d = json.load(open(path))
    changed = 0
    for g in d['drills']:
        for q in g['questions']:
            new_stem = clean(q['stem'])
            if new_stem != q['stem']:
                q['stem'] = new_stem; changed += 1
            for k, v in list(q['options'].items()):
                nv = clean(v)
                if nv != v:
                    q['options'][k] = nv; changed += 1
            if 'rationale' in q and isinstance(q['rationale'], str):
                q['rationale'] = clean(q['rationale'])
    if changed:
        json.dump(d, open(path, 'w'), indent=1, ensure_ascii=False)
        files += 1; total += changed
        print(f"{path.split('/')[-1]}: {changed} fields cleaned")
print(f"\nDONE: {total} fields across {files} files")
if total == 0:
    sys.exit("Nothing changed — verify the files are present.")
