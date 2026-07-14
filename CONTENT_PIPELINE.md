# CFAL3 — Content Batch Protocol

Standing Cursor procedure for applying content-pipeline batches mechanically.
The content pipeline (Claude) authors every substantive change — answer keys,
rationales, distractors, LOS tags — and delivers each batch as a JSON patch
file plus updated test pins. Cursor applies batches with this protocol and
**never** authors, edits, or "improves" CFA content itself.

## Batch format

`content_batches/<name>.json`:

```json
{
  "target": "question_bank" | "drills",
  "description": "distractor batch 1 - r13 institutional",
  "replacements": [
    {
      "id": "<question id>",
      "options": { "A": "...", "B": "...", "C": "..." },
      "correct": "B",
      "rationales": {},
      "candidate_los": [],
      "data_quality": "complete",
      "data_quality_flags": []
    }
  ],
  "expected": { "applied": 40 },
  "pin_updates": { "ungradeable_mc": 24 }
}
```

Each provided field **replaces** the existing value wholesale (never merges).

## Application procedure (per batch)

1. Place the delivered file under `content_batches/` and commit it unmodified.
2. Run `python3 scripts/apply_content_batch.py content_batches/<file>`.
   It must print the expected applied count and `OK`. On assertion failure:
   `git checkout` the content files and report — never hand-edit toward the numbers.
3. If the batch carries `pin_updates`, update exactly those constants in
   `QuestionBankIntegrityTests` and nothing else.
4. Run the full test suite; run `python3 scripts/triage_report.py` and commit
   the refreshed queue.
5. Commit with the batch description as the message.

## Scheduled batches (content pipeline authors; Cursor applies)

- **Distractor batch(es):** 181 queue items from P1, then ~965 length-imbalanced
  drills — batched by reading, target `drills`.
- **Key-verification batch:** autland q5/q6 + vitting q5 after CFAI/Deep 3
  cross-check — target `question_bank`; may flip a correct key and clear
  `rationale_mismatch` flags.
- **Answer-key batch(es):** the 29 `no_correct` MCs — keys + full rationales;
  clears `no_correct` flags and lowers the ungradeable-MC pin via `pin_updates`.
- **Rationale backfill:** 25 partial + 17 `no_rationales` (incl. arthur_camme q1/q6).
- **LOS tagging:** the 55 empty `candidate_los` ethics MCs →
  `guidance_standard_*` / `code_and_standards`.
- Separately, outside this protocol: R1–R7 study-note rebuilds are `.docx`
  deliverables and never touch the repo.

## Out of scope for Cursor — always

Writing, rewording, or completing any CFA content. If a batch file looks wrong,
report; do not fix.
