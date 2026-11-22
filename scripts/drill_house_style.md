# Drill house style

The target is the style CFA Institute writes item-set questions in. You do not
have to guess at it: `CFAL3/Resources/question_bank.json` holds 270 real-format
questions in this repo, and every rule below was read off them rather than
invented. `scripts/drill_style_lint.py --bank` scores that file; 96% of its
questions break no rule. The same linter scores the LOS drills at 23%.

## What a real option looks like

```
Based on how the Taylor rule is applied by Li's team, the central bank's
estimated optimal short-term real rate is closest to:
    A. 1.5%.
    B. 2.0%.
    C. 2.8%.

Of Kumar's three points regarding interest rate linkages among countries
proposed for the new fund, she is least likely correct with respect to bond
yields in:
    A. Chile.
    B. Denmark.
    C. Singapore and Sweden.
```

Median option length in that file is **18 characters**. Mean 27. The 90th
percentile is 62. The longest option in the whole bank is 165.

Median option length in the LOS drills is **97 characters**, and the correct
option runs to 125 against the distractors' 91.

## The rules

1. **An option is the candidate answer and nothing else.** Not the reasoning,
   not the arithmetic, not a restatement of the stem. If the option explains
   why it is right, it is wrong.

2. **One sentence or fragment.** Never two. The generator's second sentence
   ("That specification would be used as-is, with no forward-looking overlay")
   appears on 901 distractors and on zero correct answers, which makes it a
   working answer key — drop the two-sentence option and take the longest of
   what is left and you score 74% without reading a word.

3. **No equations and no worked arithmetic**, in options or in stems. Not
   `=`, not `1,250 × (18² − 20²)`, not a formula name like `Settlement_T`.
   A computational item's options are the three candidate *values*:
   `A. $2,500 paid.` `B. $95,000 paid.` `C. $95,000 received.`
   The formula belongs in the rationale, where the learner reads it after
   committing to an answer.

4. **No capitals for emphasis.** Not NOT, not HIGHER, not SHORT. CFA Institute
   italicises *least likely* and stops there. Abbreviations the item defines
   are fine and ordinary — SPP, GIPS, IPS, QUINCO — the test is whether the
   word is an ordinary English word being shouted.

5. **Target under 120 characters, aim far shorter.** If three options cannot be
   said briefly, the stem is carrying too little and should carry more.

6. **All three options open the same way** — all capitalised, or all lowercase
   continuations of a stem that ends in a colon. Exactly one lowercase option
   among three used to name the correct answer here 95% of the time.

7. **The three options are parallel**: same grammatical shape, same kind of
   thing. Three durations, or three countries, or three actions. Not one
   action, one justification and one formula.

8. **The stem carries the setup and ends with the CFA qualifier** — *is most
   likely*, *is closest to*, *best describes*, *is least likely*, *is most
   appropriate*. It may hold data. It may not hold a worked calculation.

9. **Do not cite the source inside the item.** No "According to the CFA
   Institute curriculum", no "Per Example 12", no "the curriculum states".
   The learner is answering a question, not auditing a reading. Citations
   belong in the rationale.

## What must not change

- **`correct` keeps its letter.** Option B stays the answer if it was the
  answer. Scheduling history and flags are keyed to the question, and a moved
  key silently invalidates every past review.
- **The substance of each option.** The correct option makes the same claim it
  made before, said tersely. Each distractor stays wrong *for the same reason*
  it was wrong before — its rationale still has to describe it.
- **Every other field**: `id`, `number`, `primary_los`, `reading_id`,
  `area_id`, `difficulty`, `needs_calculator`, `curriculum_ref`.

## Rationales

Rationales are where the explanation goes, and they should get longer, not
shorter, as the options get shorter. Clean them of:

- `Full statement:` prefixes — a generator artefact, on 1,902 questions
- `Correct.` / `Incorrect.` openers — the app already shows which is which
- capitals for emphasis
- `Per Example 12:` and similar citations of a source the learner cannot see

Keep the formula, the arithmetic and the reasoning. That material is correct
and it is the reason the drills are worth fixing rather than discarding.
