# Drill rewrite pass — where it stands

The corpus is `CFAL3/Resources/los_drills_r*.json`: 2,667 multiple-choice
drills across 247 LOS groups. This file records what has been rewritten, what
has been checked, and what is still outstanding, because the work ran across
several sessions in ephemeral containers and the scratchpad does not survive.

## State as of commit `ddf6616`

| | drills | rewritten | substance-audited |
|---|---|---|---|
| applied | 2,290 | yes | 2,095 (100% of the rewrites) |
| group 5 (held) | 377 | produced, not applied | no |
| total | 2,667 | 2,290 | 2,095 |

The audit of the applied rewrites is **complete, with no applied rewrite left
unaudited**. It ran in two passes whose union is exactly the 2,290 applied
rewrites, overlapping by 5 drills:

- the 200-drill sample: 6 fatal, a 3.0% rate, 5 repaired (one was a duplicate
  of a finding in the other pass)
- the full run: 210 of 210 batches, 2,095 drills, 1,878 sound, 25 fatal for a
  rate of 1.19%, and 205 style findings left alone

All 31 fatal findings are repaired: 5 in `1eaf4ea`, 16 in `ddf6616`, 9 in the
commit that added this paragraph. 36 field changes over 24 questions.

Corpus measurements, all from `scripts/drill_style_lint.py` and
`scripts/drill_ratchets.py`:

- clean questions 2,239 / 2,667 (84.0%), from 341 (12.8%) before the pass
- option median length 51 chars, from 97
- best knowledge-free strategy 0.5081, from 0.735
- keys 889 / 889 / 889; answer-position transitions 0.3463 / 0.3463 / 0.3074,
  longest run 3

## What is outstanding

**1. Group 5 — 377 drills rewritten but NOT applied.**
Every one of the 38 rewrite batches produced output, and the patch sits in the
workflow's own patch directory. It must not be applied as it stands: the
verifiers raised 157 fatal objections and all 24 repair agents died on a usage
limit, so nothing in it has been through repair. Batches 24–37 report zero
objections only because their verifiers failed too — that is the same reading
error that let 2,270 unverified rewrites through the first time, and a zero
from a dead agent means nothing.

**2. The Swift test suite has never been run.**
`CFAL3Tests/QuestionBankIntegrityTests.swift` holds every ratchet, and no
container in this work had Xcode. `scripts/drill_ratchets.py` mirrors its logic
exactly — same regexes, same sentence counting, same ASCII-only digit test —
and reports every ceiling matched, but it is a mirror I wrote, not the test.
This needs one run on macOS.

## What the audit found, and why it could not be automated away

The dominant defect was a distractor that lost the word making it false:

    before   C. "Trailing-earnings weighting only."     false
    after    C. "Trailing-earnings weighting."          TRUE

Every mechanical check passes on that change. The key never moves, no negation
or antonym flips, the options stay distinct, and the house-style counts improve.
Only the answer is wrong. Three deterministic detectors were built to find this
class without an LLM, and all three were measured against the 16 known defects:

| detector | candidates | recall | precision |
|---|---|---|---|
| `drill_rewrite_drift.py` (antonyms, negation, numbers) | 2,760 | 5/16 | 0.2% |
| `drill_lost_limiter.py` (limiting word deleted) | 1,276 | 7/16 | 0.6% |
| `drill_orphan_rebuttal.py` (rationale rebuts a claim the option dropped) | 84 | 4/16 | 4.8% |
| limiter ∪ orphan | 1,319 | 8/16 | — |
| limiter ∩ orphan | 41 | 3/16 | 7.3% |

Best precision 7%, best recall 50%. The drift detector flags 1,581 of the
2,095 questions, which is 75% of the corpus, so its 5/16 is close to what
flagging everything would give — it is not a filter at all.

I then read all 41 candidates in the then-unaudited region by hand and cleared
every one. The audit later found a fatal defect among them, and the lesson is
worth recording because it is about reading rather than tooling:

    stem    "Performance-based fees are most likely:"
    option  B  "based on total return rather than on return relative to a
                benchmark."

I judged B false, reading "rather than" as an exclusivity claim the curriculum
contradicts. But "most likely" turns the option into a claim about the typical
case, and hedge fund and private equity performance fees commonly ARE charged
on total return, so B was defensible and the item was double-keyed. The
detector flagged it correctly; I cleared it wrongly. So a hand pass over a
candidate list does not substitute for the audit either, and specifically: an
option has to be tested against the modality the stem gives it, not only
against whether its words are literally false.

## Resuming

Both workflows are resumable, and resume replays finished agents from cache, so
only the agents the limit killed are re-run.

Audit of the remaining 815 (82 batches of the original 210):

    Workflow({
      scriptPath: '<session>/workflows/scripts/drill-verify-audit.js',
      resumeFromRunId: 'wf_eb075168-d39',
      args: {batch: 10, count: 2095, sample: '<scratchpad>/verify/full.json'}
    })

Group 5 verify + repair:

    Workflow({
      scriptPath: '<session>/workflows/scripts/drill-rewrite-pass-wf_41cb7cdc-43f.js',
      resumeFromRunId: 'wf_7b793acb-2b4',
      args: {batch: 10, count: 377, group: 5}
    })

Both read files from a session scratchpad that a new container will not have.
`scratchpad/verify/full.json` is rebuildable from `git show 1eaf4ea` against the
pre-rewrite corpus at `HEAD~1` of the rewrite commits; group 5's source and
patch directory are not, so if that scratchpad is gone, group 5 has to be
rewritten from scratch.

## Repairing a defect the audit reports

`scripts/drill_repair.py` applies a JSON list of
`{id, field, old, new, why}` records, where `field` is `stem`, `opt.A` or
`rat.B`. It aborts the whole run if any `old` does not match the corpus
exactly, so a repair cannot land on a question that moved under it. The two
repair sets applied so far are kept as the record of what was changed and on
what grounds:

- `docs/drill_repairs_audit.json` — 36 field changes over 24 questions
- `docs/drill_audit_complete_2095.json` — the full audit findings they answer
- `docs/drill_audit_sample_200.json` — the earlier sample run
