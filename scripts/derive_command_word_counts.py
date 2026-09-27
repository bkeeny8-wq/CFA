#!/usr/bin/env python3
"""Count how many LOS each command word leads, using a clause-initial rule.

A command word only counts when it opens a clause: the first word of the LOS,
or the first word after a comma, semicolon, "and", "or", or "then". That keeps
"compare" in "compare the two approaches" while rejecting the "discuss" in
"...factors an analyst would discuss with the client". Each LOS contributes at
most one to a given word's count, even when it opens two clauses.

The same rule is what `command_words.json` ships as `losCount`, so `--check`
re-derives every count in that file and confirms each `workedExample.id` is a
real essay in the question bank.

Usage: scripts/derive_command_word_counts.py [word ...] [--ids] [--check]
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOS_MASTER = os.path.join(ROOT, "CFAL3/Resources/los_master.json")
QUESTION_BANK = os.path.join(ROOT, "CFAL3/Resources/question_bank.json")
COMMAND_WORDS = os.path.join(ROOT, "CFAL3/Resources/command_words.json")

CLAUSE_BREAK_WORDS = {"and", "or", "then"}


def clause_initial_words(text):
    """The lowercased words that open a clause in `text`."""
    tokens = text.split()
    opens_clause = True
    words = []
    for token in tokens:
        word = re.sub(r"^[^\w]+|[^\w]+$", "", token).lower()
        if opens_clause and word:
            words.append(word)
        opens_clause = token.endswith((",", ";", ":")) or word in CLAUSE_BREAK_WORDS
    return words


def counts(words, los_flat):
    tally = {word: 0 for word in words}
    hits = {word: [] for word in words}
    for los in los_flat:
        leading = set(clause_initial_words(los["text"]))
        for word in words:
            if word in leading:
                tally[word] += 1
                hits[word].append(los["id"])
    return tally, hits


def bank_essay_ids():
    with open(QUESTION_BANK, encoding="utf-8") as f:
        bank = json.load(f)
    return {
        question["id"]
        for topic in bank["topics"]
        for case in topic["cases"]
        for question in case["questions"]
        if question.get("type") == "essay"
    }


def check(los_flat):
    """Re-derive every shipped losCount and validate every cited example."""
    with open(COMMAND_WORDS, encoding="utf-8") as f:
        entries = json.load(f)["words"]
    words = [entry["word"] for entry in entries]
    tally, _ = counts(words, los_flat)
    essays = bank_essay_ids()
    failures = []
    for entry in entries:
        word = entry["word"]
        if entry["losCount"] != tally[word]:
            failures.append(
                f"{word}: losCount {entry['losCount']} but derivation gives {tally[word]}"
            )
        example = entry["workedExample"]
        if example["kind"] != "essay":
            failures.append(f"{word}: workedExample.kind {example['kind']} is not essay")
        elif example["id"] not in essays:
            failures.append(f"{word}: workedExample.id {example['id']} is not a bank essay")
        for other in entry["confusedWith"]:
            if other["word"] == word:
                failures.append(f"{word}: confusedWith points at itself")
            elif other["word"] not in words:
                failures.append(f"{word}: confusedWith {other['word']} has no entry")
    # ContentLoader.allCommandWords hands the file's order straight to the UI
    # and documents it as busiest verb first, so the order is an invariant.
    shipped = [entry["losCount"] for entry in entries]
    if shipped != sorted(shipped, reverse=True):
        failures.append(f"words are not ordered by descending losCount: {shipped}")
    for failure in failures:
        print(f"FAIL {failure}")
    if not failures:
        print(f"OK {len(entries)} words: counts re-derived, examples exist in the bank")
    return 1 if failures else 0


def main():
    flags = {arg for arg in sys.argv[1:] if arg.startswith("--")}
    words = [w.lower() for w in sys.argv[1:] if not w.startswith("--")] or [
        "discuss",
        "describe",
        "explain",
        "compare",
        "contrast",
    ]
    with open(LOS_MASTER, encoding="utf-8") as f:
        los_flat = json.load(f)["los_flat"]
    if "--check" in flags:
        return check(los_flat)
    tally, hits = counts(words, los_flat)
    print(f"{len(los_flat)} LOS in los_flat")
    for word in words:
        print(f"{word:12} {tally[word]:4}")
    if "--ids" in flags:
        print(json.dumps(hits, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
