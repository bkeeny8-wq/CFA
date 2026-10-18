# Instrument playbook: groundwork

Pro/con, when-to-recommend and exam-cue content for every instrument the
curriculum covers. **Not built.** This folder is the grounding only.

## What `grounding.json` is

37 instruments across six families, extracted from the app's own bundled
content so any authoring is anchored rather than invented:

- `notesEvidence[]` sentences from `reading_notes.json` mentioning the
  instrument, each tagged with its reading id (723 sentences in total)
- `los[]` learning outcome statements naming it
- `essayStems[]` bank essay prompts that use it

Depth is very uneven and that is the point: `futures` has 154 note sentences,
`currency_swap` and `total_return_swap` have 1 each. Nothing is empty.

Regenerate with the extraction in the session transcript, or re-derive from
`reading_notes.json`, `los_master.json` and `question_bank.json`.

## The agreed shape of an entry

Decided with the owner before authoring began:

- `summary` one sentence, what it is
- `pros[]` / `cons[]` each `{text, source}` where source is a reading id or
  `"curriculum"` for standard material not in the notes
- `whenToRecommend[]` / `whenNotTo[]` conditions phrased as vignette situations
- `pitfalls[]` the specific mistakes that lose marks
- `cues[]` `{signal, implication}` the highest-value field: the constraint a
  vignette plants and what it rules in or out. The owner's example: "worries
  about counterparties" implies no OTC, so futures and listed options rather
  than forwards and swaps.
- `comparesWith[]` sibling keys, driving a compare selector in the UI

## The approach agreed

Extract what the notes already say, then amplify to asset-class level where the
notes are thin, marking amplified material `"curriculum"` so the two are
distinguishable. Every claim verified adversarially for CFA correctness,
grounding against the notes, and exam usefulness before it ships.

## Open question the owner should settle

This is **generated** exam content, unlike everything else in the app (the notes
DOCX, the Meldrum PDFs, the cycle map JSON all came authored and approved). It
should be reviewed before being studied as fact. The `confidence` and
`uncertain` fields in the schema exist so the author has to declare doubt rather
than bury it.
