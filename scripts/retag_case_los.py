#!/usr/bin/env python3
"""Narrow spray-tagged case-bank `candidate_los` to the 1–3 LOS the stem
actually tests.

Does not author CFA content. Each question is scored against existing LOS
statements plus the drill bank already tagged to that LOS (one LOS per drill).
Questions that already have 1–3 tags (ethics batch_14 and similar) are left
alone. `primary_reading_ids` is reduced to the readings of the kept LOS so
coverage stats stop crediting readings the stem never tested.

Writes content_batches/batch_16_case_los_narrow.json and applies it with
apply_content_batch.py's replacement rules (whole-field, never merge).
"""
from __future__ import annotations

import collections
import glob
import json
import math
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANK = os.path.join(ROOT, "CFAL3/Resources/question_bank.json")
MASTER = os.path.join(ROOT, "CFAL3/Resources/los_master.json")
BATCH = os.path.join(ROOT, "content_batches/batch_16_case_los_narrow.json")
APPLY = os.path.join(ROOT, "scripts/apply_content_batch.py")

STOP = set(
    """the a an of to and for in on or is are be as by with from that this which
    than most likely least appropriate correct incorrect following statements
    about each should would could may into its their they them his her you your
    when where what how why who will been being were was has have had not but
    also only more less such other any all both between among over under after
    before during without within per via using used use case scenario exhibit
    given based question determine discuss explain calculate identify compare
    evaluate recommend justify describe state select indicate closest""".split()
)


def tokens(text: str) -> list[str]:
    text = (text or "").replace("\u00a0", " ")
    return [
        w
        for w in re.findall(r"[a-z0-9]+", text.lower())
        if len(w) > 3 and w not in STOP
    ]


def tfidf_vec(toks: list[str], df: collections.Counter, n_docs: int) -> dict[str, float]:
    tf = collections.Counter(toks)
    return {
        t: (1 + math.log(c)) * math.log((n_docs + 1) / (df[t] + 1))
        for t, c in tf.items()
    }


def cosine(a: dict[str, float], b: dict[str, float]) -> float:
    if not a or not b:
        return 0.0
    keys = set(a) & set(b)
    num = sum(a[k] * b[k] for k in keys)
    da = math.sqrt(sum(v * v for v in a.values()))
    db = math.sqrt(sum(v * v for v in b.values()))
    if da == 0 or db == 0:
        return 0.0
    return num / (da * db)


def blob_for(question: dict, case_title: str) -> str:
    parts = [case_title, question.get("stem") or ""]
    options = question.get("options") or {}
    if isinstance(options, dict):
        parts.extend(str(v) for v in options.values())
    rats = question.get("rationales") or {}
    if isinstance(rats, dict):
        parts.extend(str(v) for v in rats.values())
    return " ".join(parts)


def build_profiles(master: dict) -> tuple[
    dict[str, dict[str, float]],
    dict[str, list],
    dict[str, dict],
    collections.Counter,
    int,
]:
    los_by_id = {item["id"]: item for item in master["los_flat"]}
    los_by_reading: dict[str, list] = collections.defaultdict(list)
    for area in master["areas"]:
        for reading in area["readings"]:
            los_by_reading[reading["id"]] = reading["los"]

    profile: dict[str, list[str]] = collections.defaultdict(list)
    for path in glob.glob(os.path.join(ROOT, "CFAL3/Resources/los_drills_r*.json")):
        bundle = json.load(open(path))
        for group in bundle["drills"]:
            lid = group["los_id"]
            profile[lid].extend(tokens(group.get("los_text") or ""))
            for q in group["questions"]:
                profile[lid].extend(tokens(q.get("stem") or ""))
                for value in (q.get("options") or {}).values():
                    profile[lid].extend(tokens(str(value)))
                for value in (q.get("rationales") or {}).values():
                    profile[lid].extend(tokens(str(value))[:40])

    for los in master["los_flat"]:
        profile[los["id"]].extend(tokens(los["text"]) * 3)

    df: collections.Counter = collections.Counter()
    for toks in profile.values():
        df.update(set(toks))
    n_docs = max(len(profile), 1)
    vectors = {lid: tfidf_vec(toks, df, n_docs) for lid, toks in profile.items()}
    return vectors, los_by_reading, los_by_id, df, n_docs


def candidates_for(question: dict, los_by_reading: dict, los_by_id: dict) -> list[dict]:
    seen = set()
    out = []
    for reading_id in question.get("primary_reading_ids") or []:
        for los in los_by_reading.get(reading_id, []):
            if los["id"] not in seen:
                seen.add(los["id"])
                out.append(los)
    for lid in question.get("candidate_los") or []:
        if lid not in seen and lid in los_by_id:
            seen.add(lid)
            out.append(los_by_id[lid])
    return out


def pick_los(
    vectors: dict[str, dict[str, float]],
    cands: list[dict],
    q_vec: dict[str, float],
    fallback: list[str],
) -> list[str]:
    if not cands:
        return fallback[:1]
    scored = sorted(
        (
            cosine(q_vec, vectors.get(los["id"], {})),
            los["id"],
        )
        for los in cands
    )
    scored.reverse()
    top = scored[0][0]
    picked: list[str] = []
    for score, lid in scored:
        if len(picked) >= 3:
            break
        if not picked:
            picked.append(lid)
            continue
        if top > 0 and score >= 0.55 * top:
            picked.append(lid)
        else:
            break
    return picked or [scored[0][1]]


def readings_for(los_ids: list[str], los_by_id: dict, fallback: list[str]) -> list[str]:
    seen: list[str] = []
    for lid in los_ids:
        los = los_by_id.get(lid)
        if not los:
            continue
        rid = los.get("reading_id")
        if rid and rid not in seen:
            seen.append(rid)
    return seen or list(fallback)


def main() -> int:
    master = json.load(open(MASTER))
    bank = json.load(open(BANK))
    vectors, los_by_reading, los_by_id, df, n_docs = build_profiles(master)

    replacements = []
    for topic in bank["topics"]:
        for case in topic["cases"]:
            title = case.get("title") or ""
            for question in case["questions"]:
                current = question.get("candidate_los") or []
                if 1 <= len(current) <= 3:
                    continue
                q_vec = tfidf_vec(tokens(blob_for(question, title)), df, n_docs)
                cands = candidates_for(question, los_by_reading, los_by_id)
                picked = pick_los(vectors, cands, q_vec, current)
                readings = readings_for(
                    picked, los_by_id, question.get("primary_reading_ids") or []
                )
                if (
                    picked == current
                    and readings == (question.get("primary_reading_ids") or [])
                ):
                    continue
                replacements.append(
                    {
                        "id": question["id"],
                        "candidate_los": picked,
                        "primary_reading_ids": readings,
                    }
                )

    batch = {
        "target": "question_bank",
        "description": (
            "Narrow spray-tagged case questions to 1–3 candidate LOS. "
            "Tags are chosen by cosine similarity of the stem/options/key "
            "against each LOS statement plus that LOS's existing drill bank. "
            "Already-narrow tags (≤3) are left unchanged. primary_reading_ids "
            "follows the kept LOS so coverage does not credit untested readings."
        ),
        "replacements": replacements,
        "expected": {"applied": len(replacements)},
    }
    os.makedirs(os.path.dirname(BATCH), exist_ok=True)
    with open(BATCH, "w", encoding="utf-8") as fh:
        json.dump(batch, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print({"wrote": BATCH, "replacements": len(replacements)})

    result = subprocess.run(
        [sys.executable, APPLY, BATCH], cwd=ROOT, check=False
    )
    if result.returncode != 0:
        return result.returncode

    bank = json.load(open(BANK))
    known = {item["id"] for item in master["los_flat"]}
    counts = []
    empty = []
    unknown = []
    wide = []
    missing_reading = []
    for topic in bank["topics"]:
        for case in topic["cases"]:
            for question in case["questions"]:
                tags = question.get("candidate_los") or []
                counts.append(len(tags))
                if not tags:
                    empty.append(question["id"])
                if len(tags) > 3:
                    wide.append((question["id"], len(tags)))
                for lid in tags:
                    if lid not in known:
                        unknown.append(f"{question['id']} -> {lid}")
                if not (question.get("primary_reading_ids") or []):
                    missing_reading.append(question["id"])
    assert not empty, empty[:10]
    assert not unknown, unknown[:10]
    assert not wide, wide[:10]
    assert not missing_reading, missing_reading[:10]
    assert max(counts) <= 3
    print(
        {
            "questions": len(counts),
            "median_los": sorted(counts)[len(counts) // 2],
            "max_los": max(counts),
            "share_le3": round(sum(1 for c in counts if c <= 3) / len(counts), 3),
        }
    )
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
