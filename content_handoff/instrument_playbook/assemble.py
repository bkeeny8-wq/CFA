#!/usr/bin/env python3
"""Assemble CFAL3/Resources/instrument_playbook.json from the repaired per-entry
files in final/, and refuse to write a bundle that would fail the app's tests.

The playbook is the first GENERATED content in the app, so this script is
deliberately a gate rather than a convenience: every constraint that
InstrumentPlaybookTests asserts at runtime is checked here first, and the
provenance of each entry (how much survived the repair pass, what was deleted,
what the author was still unsure of) is written out alongside as REVIEW.md so a
claim can always be traced back before it is studied as fact.

Run from the repo root:  python3 -I content_handoff/instrument_playbook/assemble.py
"""

import difflib
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HANDOFF = ROOT / "content_handoff" / "instrument_playbook"
FINAL = HANDOFF / "final"
GROUNDING = HANDOFF / "grounding.json"
OUT = ROOT / "CFAL3" / "Resources" / "instrument_playbook.json"
LEDGER = HANDOFF / "REVIEW.md"

# Curriculum order, not file order: the page reads top to bottom as the exam
# bundles the material.
FAMILY_ORDER = [
    "Derivatives: options",
    "Derivatives: swaps & futures",
    "Fixed income",
    "Equity",
    "Alternatives",
    "Currency",
]

LIST_FIELDS = ("pros", "cons", "whenToRecommend", "whenNotTo", "pitfalls", "cues")
MINIMUMS = {"pros": 4, "cons": 4, "whenToRecommend": 3, "whenNotTo": 3, "pitfalls": 3, "cues": 4}
EM_DASH = "—"


def reading_ids():
    """Valid `source` values, read from los_master so this never drifts from the
    set the app's provenance test checks against."""
    master = json.loads((ROOT / "CFAL3" / "Resources" / "los_master.json").read_text())
    return {r["id"] for area in master["areas"] for r in area["readings"]}


def strings_in(entry):
    """Every user-facing string in an entry, for the em dash sweep."""
    out = [entry["name"], entry["summary"]]
    out += [p["text"] for p in entry["pros"] + entry["cons"]]
    out += entry["whenToRecommend"] + entry["whenNotTo"] + entry["pitfalls"]
    out += [s for c in entry["cues"] for s in (c["signal"], c["implication"])]
    return out


def main():
    if not FINAL.is_dir():
        sys.exit(f"no repaired entries: {FINAL} does not exist")

    grounding = json.loads(GROUNDING.read_text())
    readings = reading_ids()
    files = sorted(FINAL.glob("*.json"))
    if not files:
        sys.exit(f"no repaired entries in {FINAL}")

    entries, reviews, errors, warnings = [], {}, [], []

    for path in files:
        try:
            entry = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            errors.append(f"{path.name}: not valid JSON ({exc})")
            continue

        key = entry.get("key") or path.stem
        if key != path.stem:
            errors.append(f"{path.name}: declares key '{key}'")
        if key not in grounding:
            errors.append(f"{key}: not an instrument in the grounding pack")
            continue

        reviews[key] = entry.pop("_review", {}) or {}

        missing = [f for f in ("name", "family", "summary", *LIST_FIELDS,
                               "comparesWith", "confidence") if f not in entry]
        if missing:
            errors.append(f"{key}: missing field(s) {', '.join(missing)}")
            continue

        # The family is the taxonomy, not the author's choice.
        expected = grounding[key]["family"]
        if entry["family"] != expected:
            warnings.append(f"{key}: family '{entry['family']}' corrected to '{expected}'")
            entry["family"] = expected

        for field in LIST_FIELDS:
            if not entry[field]:
                errors.append(f"{key}: {field} is empty, the card would render as a bug")
            elif len(entry[field]) < MINIMUMS[field]:
                warnings.append(f"{key}: {field} has {len(entry[field])}, below the target "
                                f"{MINIMUMS[field]}")

        for point in entry["pros"] + entry["cons"]:
            if not point.get("text", "").strip():
                errors.append(f"{key}: a blank point")
            source = point.get("source", "")
            if source != "curriculum" and source not in readings:
                errors.append(f"{key}: point cites '{source}', which is not a reading")

        for cue in entry["cues"]:
            if not cue.get("signal", "").strip() or not cue.get("implication", "").strip():
                errors.append(f"{key}: a half-empty cue")

        for text in strings_in(entry):
            if EM_DASH in text:
                errors.append(f"{key}: em dash in \"{text[:60]}\"")

        if entry["confidence"].lower() not in {"high", "medium", "low"}:
            errors.append(f"{key}: confidence '{entry['confidence']}' is not high, medium or low")
        entry["confidence"] = entry["confidence"].lower()

        entries.append(entry)

    shipped = {e["key"] for e in entries}

    # Compare links may only point at instruments that actually shipped. An entry
    # left with nothing to compare against is an error, not a warning: the test
    # asserts it, and a compare selector with no options is a dead control.
    for entry in entries:
        resolved, dropped = [], []
        for key in entry["comparesWith"]:
            if key == entry["key"] or key in dropped or key in resolved:
                continue
            (resolved if key in shipped else dropped).append(key)
        if dropped:
            warnings.append(f"{entry['key']}: compare link(s) dropped, not shipped: "
                            f"{', '.join(dropped)}")
        entry["comparesWith"] = resolved
        if not resolved:
            errors.append(f"{entry['key']}: nothing left to compare against")

    # Does the ledger tell the truth about what it removed? One adjudicator
    # caught a repair pass claiming to have deleted an item it actually shipped,
    # which makes the provenance record worse than useless. Warning rather than
    # error: a deletion note legitimately QUOTES the text it removed, and that
    # text may survive elsewhere on purpose, so a hit needs a human to read it.
    for entry in entries:
        shipped = strings_in(entry)
        for claim in reviews.get(entry["key"], {}).get("deleted") or []:
            if not isinstance(claim, str) or len(claim) < 40:
                continue
            overlap = max((difflib.SequenceMatcher(None, claim, text)
                           .find_longest_match(0, len(claim), 0, len(text)).size
                           for text in shipped), default=0)
            if overlap >= 60:
                warnings.append(f"{entry['key']}: ledger claims a deletion whose wording is "
                                f"still shipped ({overlap} chars), check it is a quotation: "
                                f"\"{claim[:70]}\"")

    links = sum(len(e["comparesWith"]) for e in entries)
    if links <= len(entries):
        errors.append(f"the compare graph is too sparse to use: {links} links "
                      f"across {len(entries)} instruments")

    families = [f for f in FAMILY_ORDER if any(e["family"] == f for e in entries)]
    for family in {e["family"] for e in entries}:
        if family not in FAMILY_ORDER:
            errors.append(f"family '{family}' is not in FAMILY_ORDER, it would never render")

    entries.sort(key=lambda e: (families.index(e["family"]) if e["family"] in families else 99,
                                list(grounding).index(e["key"])))

    for line in warnings:
        print(f"  warn  {line}")
    if errors:
        print()
        for line in errors:
            print(f"  ERROR {line}")
        sys.exit(f"\n{len(errors)} error(s): refusing to write {OUT.name}")

    bundle = {
        "version": 1,
        "source": "generated-and-repaired",
        "families": families,
        "instruments": entries,
    }
    OUT.write_text(json.dumps(bundle, indent=1, ensure_ascii=False) + "\n")

    write_ledger(entries, reviews)

    notes = sum(1 for e in entries for p in e["pros"] + e["cons"] if p["source"] != "curriculum")
    total = sum(len(e["pros"]) + len(e["cons"]) for e in entries)
    claims = sum(len(e[f]) for e in entries for f in LIST_FIELDS)
    conf = {c: sum(1 for e in entries if e["confidence"] == c) for c in ("high", "medium", "low")}
    print(f"\nwrote {OUT.relative_to(ROOT)}")
    print(f"  {len(entries)} instruments in {len(families)} families, {claims} claims")
    print(f"  provenance: {notes} of {total} points cite a reading, {total - notes} curriculum")
    print(f"  confidence: {conf['high']} high, {conf['medium']} medium, {conf['low']} low")
    print(f"  compare graph: {links} links")
    print(f"  ledger: {LEDGER.relative_to(ROOT)}")


def write_ledger(entries, reviews):
    """What was changed and what is still shaky, per entry. This is the file to
    read before trusting a claim on the page."""
    lines = [
        "# Instrument playbook: review ledger",
        "",
        "This content was GENERATED, then fact checked and repaired entry by entry.",
        "It is not curriculum text and it has not been reviewed by a human. Every",
        "claim below is defensible as far as the repair pass could establish; the",
        "residual risks are the ones to check against the curriculum first.",
        "",
        f"{len(entries)} instruments. Confidence is the author's own, and is shown in the app.",
        "",
    ]
    for entry in entries:
        review = reviews.get(entry["key"], {})
        counts = ", ".join(f"{len(entry[f])} {f}" for f in LIST_FIELDS)
        lines += [f"## {entry['name']} (`{entry['key']}`)", "",
                  f"- family: {entry['family']}",
                  f"- confidence: **{entry['confidence']}**",
                  f"- kept: {counts}"]
        if review.get("shortfall"):
            lines.append(f"- shortfall: {review['shortfall']}")
        if review.get("residualRisk"):
            lines.append(f"- **least sure of:** {review['residualRisk']}")
        for label, field in (("corrected", "corrected"), ("deleted", "deleted")):
            items = review.get(field) or []
            if items:
                lines += ["", f"<details><summary>{len(items)} {label}</summary>", ""]
                lines += [f"- {item}" for item in items]
                lines += ["", "</details>"]
        lines.append("")
    LEDGER.write_text("\n".join(lines))


if __name__ == "__main__":
    main()
