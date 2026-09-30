#!/usr/bin/env python3
"""Validate CFAL3/Resources/cycle_map.json. Run from repo root."""
import json, sys
p = 'CFAL3/Resources/cycle_map.json'
d = json.load(open(p))
errs = []
if len(d['phases']) != 5: errs.append('phase count')
if len(d['frameworks_static']) != 8: errs.append('framework count')
if len(d['assets']) != 9 or len(d['asset_chains']) != 9 or len(d['asset_traps']) != 9:
    errs.append('asset arrays')
if len(d['moves_static']) != 5: errs.append('moves_static count')
for ph in d['phases']:
    if len(ph['stances']) != 9: errs.append(ph['name'] + ': stances')
    if len(ph['mechanisms']) != 9: errs.append(ph['name'] + ': mechanisms')
    if len(ph['moves']) != 5: errs.append(ph['name'] + ': moves')
    for m in ph['moves']:
        for k in ('name','what','reading_tag','how','why'):
            if not m.get(k): errs.append(ph['name'] + ': move missing ' + k)
    fw = ph['frameworks']
    for k in ('cash','govt','credit','gk','singer_terhaar','real_estate','commodities','fx'):
        if k not in fw: errs.append(ph['name'] + ': framework ' + k)
    if any(ch not in ('OW','N','UW') for ch in ph['stances']): errs.append(ph['name'] + ': stance values')
for s in json.dumps(d):
    pass
if '\u2014' in json.dumps(d, ensure_ascii=False): errs.append('em dash present')
if errs:
    print('FAIL:', errs); sys.exit(1)
print('cycle_map.json VERIFIED: 5 phases, 8 frameworks, 9 assets, 25 moves, no em dashes.')
