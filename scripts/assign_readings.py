#!/usr/bin/env python3
"""Assign a reading to every question block in the study plan.

WHAT THIS DOES NOT TOUCH. Every block's date, start, minutes, kind,
question_source and commute flag are preserved exactly, and so is every day's
`hours` and the file's `total_planned_hours`. This script decides only WHICH
READING each question block carries. The plan's shape — 389 blocks, 390.7h,
128 commute legs on 64 weekdays, six mocks and their reviews, the Meldrum video
days and the February taper — was settled earlier and is not re-derived here.
Blocks that carry no reading today (mocks, paper reviews, videos, and the WEAK
blocks that are assigned from your own scores at the time) keep none.

Running it on the current plan is idempotent in shape: it rewrites assignments
from `reading_ranking.json` and nothing else.

TWO AXES, NOT ONE. `desk_need` orders the desk blocks, hardest first, so the
day runs down a difficulty gradient from 06:00. `commute_value` — a separate
judgement about whether a tired 35-minute phone review actually pays off —
chooses the evening leg. These are rated independently.

Scoring commute legs by inverted difficulty, as an earlier version did, put
Book 4 Derivatives at 91-96 and therefore never on a commute leg across fifteen
weeks, although every Derivatives reading has 70+ phone-answerable drills. The
material was always there; the selection rule could not see it.
"""

import collections
import datetime
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "CFAL3" / "Resources"
SCHEDULE = RES / "study_schedule.json"
RANKING = pathlib.Path(__file__).resolve().parent / "reading_ranking.json"

WINDOW_START = "2026-11-06"
WEIGHT = {6: 32.5, 1: 17.5, 2: 17.5, 4: 12.5, 5: 12.5, 3: 7.5}
SRC_LABEL = {"app": "App Q", "mm": "MM Q", "cfai": "CFAI Q"}
LEG_MINUTES = 35

# A reading may not take more than this share of its minutes from commute legs.
# Measured on REALIZED minutes and applied to BOTH legs. Two earlier holes:
# only the evening leg was filtered, while the morning leg mirrors the day's
# lead block and on a one-block day that lead can be an Ethics reading; and the
# test was not projective, so legs fitted under a static budget one at a time.
# Nine Ethics readings reached 70% commute — one desk hour against 140m of
# phone drills — before this was closed.
MAX_COMMUTE_SHARE = 0.55

# Days a reading sits out before it can come round again.
REST_DAYS = 2


def add_minutes(hhmm, minutes):
    t = datetime.datetime.strptime(hhmm, "%H:%M") + datetime.timedelta(minutes=minutes)
    return t.strftime("%H:%M")


def load_names():
    """Display names, read from the drill bundles rather than hard-coded."""
    names = {}
    for b in json.loads((RES / "los_drills_index.json").read_text())["bundles"]:
        data = json.loads((RES / f"{b['filename']}.json").read_text())
        for d in data["drills"]:
            if d.get("reading_name"):
                names[b["reading_id"]] = d["reading_name"]
                break
        names.setdefault(b["reading_id"], b["reading_id"])
    return names


def in_window(date):
    return date >= WINDOW_START


def main():
    data = json.loads(SCHEDULE.read_text())
    names = load_names()
    ranking = json.loads(RANKING.read_text())
    book_of = {r["reading_id"]: r["book"] for r in ranking}

    # Two axes if the ranking carries them, one if it does not. The single-axis
    # file is the older format, where `load` is morning-worthiness and there is
    # no separate judgement about the ride home. Falling back to -load for the
    # evening leg reproduces the DEFECT this script exists to fix — Book 4
    # scores 91-96, so it can never be picked, and Derivatives never reaches a
    # commute leg although every one of its readings has 70+ phone-answerable
    # drills. The fallback keeps the script runnable against a historical
    # ranking; it is not the intended mode, so it says so.
    two_axis = all("desk_need" in r and "commute_value" in r for r in ranking)
    if two_axis:
        desk_need = {r["reading_id"]: r["desk_need"] for r in ranking}
        commute_value = {r["reading_id"]: r["commute_value"] for r in ranking}
    else:
        desk_need = {r["reading_id"]: r["load"] for r in ranking}
        commute_value = {r["reading_id"]: 100 - r["load"] for r in ranking}
        print("WARNING: single-axis ranking — commute_value is being inferred as\n"
              "         100 - load, which cannot put a hard reading on a commute\n"
              "         leg. Re-rate on two axes before trusting the leg placement.\n")

    by_book = collections.defaultdict(list)
    for rid, bk in book_of.items():
        by_book[bk].append(rid)

    days = [d for d in data["days"] if in_window(d["date"])]

    # Minutes available to readings: question blocks that carry one today.
    total_min = sum(b["minutes"] for d in days for b in d["blocks"] if b.get("reading_id"))
    target_min = {}
    for bk, rids in by_book.items():
        share = WEIGHT[bk] / 100 * total_min
        for rid in rids:
            target_min[rid] = share / len(rids)

    remaining = dict(target_min)
    placed = collections.defaultdict(float)
    commute_min = collections.defaultdict(float)
    last_used, last_evening = {}, {}

    def under_cap(rid):
        """Would this reading still be under the cap WITH one more leg?

        Projective: a leg raises the numerator and the denominator, so the
        honest test is commute + 35 <= 0.55 * (placed + 35). For a reading
        holding one 60m desk block that settles at two legs, 70 of 130
        minutes. Measuring against the budget instead let a reading bank legs
        it had no desk time to justify.
        """
        return (commute_min[rid] + LEG_MINUTES
                <= MAX_COMMUTE_SHARE * (placed[rid] + LEG_MINUTES))

    def short_by(rid):
        """How far behind its own budget a reading is, as a FRACTION.

        Ranking by absolute minutes remaining is what made the starvation gate
        non-monotonic: the ten Ethics readings share one book's weight, so each
        has a target about a third the size of a Pathway reading's and a
        correspondingly small absolute shortfall. Sorted on raw minutes they
        lose every tie to a big-target reading and finish proportionally short,
        and which of them finishes short depends on the order days happened to
        fall. Fractions make the comparison fair across target sizes, so a
        reading that is 20% behind outranks one that is 20 minutes behind.
        """
        return remaining[rid] / target_min[rid] if target_min[rid] else 0

    def pick_desk(di, n, exclude):
        """n distinct readings, furthest behind their budget first, rested."""
        for rest in (REST_DAYS, 1, 0):
            pool = [r for r in remaining
                    if r not in exclude and remaining[r] > 0
                    and di - last_used.get(r, -99) > rest]
            pool.sort(key=lambda r: (-short_by(r), last_used.get(r, -99)))
            if len(pool) >= n:
                return pool[:n]
        pool = [r for r in remaining if r not in exclude]
        pool.sort(key=lambda r: (-short_by(r), last_used.get(r, -99)))
        return pool[:n]

    def pick_evening(di, exclude):
        """The ride home: best commute_value first, never over the cap.

        The cap is a hard filter at every level of relaxation. Ten Ethics
        readings cannot legally supply all 2,240 minutes of evening legs, so
        the pool has to widen — and with commute_value rated independently it
        widens into material that is genuinely worth reviewing rather than
        merely the least difficult.
        """
        for rest in (REST_DAYS, 1, 0):
            pool = [r for r in remaining
                    if r not in exclude and remaining[r] > 0 and under_cap(r)
                    and di - last_used.get(r, -99) > rest
                    and di - last_evening.get(r, -99) > rest]
            pool.sort(key=lambda r: (-commute_value[r], -short_by(r)))
            if pool:
                return pool[0]
        pool = [r for r in remaining if r not in exclude]
        compliant = [r for r in pool if under_cap(r)]
        if compliant:
            pool = compliant
        pool.sort(key=lambda r: (not under_cap(r), -commute_value[r], -short_by(r)))
        return pool[0]

    def assign(block, rid):
        block["book"] = book_of[rid]
        block["reading_id"] = rid
        if block.get("commute"):
            leg = "out" if "commute out" in block["label"].lower() else "back"
            block["label"] = f"Commute {leg}: {names[rid]}"
        else:
            src = block.get("question_source")
            block["label"] = f"{SRC_LABEL.get(src, 'Q')}: B{book_of[rid]} {names[rid]}"
        remaining[rid] -= block["minutes"]
        placed[rid] += block["minutes"]
        if block.get("commute"):
            commute_min[rid] += block["minutes"]

    for di, day in enumerate(days):
        desk = [b for b in day["blocks"] if not b.get("commute") and b.get("reading_id")]
        legs = [b for b in day["blocks"] if b.get("commute")]

        chosen = []
        if desk:
            chosen = pick_desk(di, len(desk), exclude=set())
            # Hardest first: the day runs down the difficulty gradient.
            chosen.sort(key=lambda r: -desk_need[r])
            for block, rid in zip(sorted(desk, key=lambda b: b["start"]), chosen):
                assign(block, rid)
                last_used[rid] = di

        if legs:
            out_leg = next((b for b in legs if "commute out" in b["label"].lower()), None)
            back_leg = next((b for b in legs if "commute back" in b["label"].lower()), None)

            # The morning leg mirrors the day's lead block so the hard topic
            # gets a second pass — but not past the lead's commute cap. On a
            # one-block day that lead can be an Ethics reading, and mirroring
            # it unconditionally is how those readings collected a fourth leg
            # against a single desk hour.
            lead = chosen[0] if chosen else None
            if lead is not None and not under_cap(lead):
                alts = [r for r in chosen[1:] if under_cap(r)]
                lead = max(alts, key=lambda r: desk_need[r]) if alts else lead
            if lead is None:
                lead = pick_desk(di, 1, exclude=set())[0]
                if not under_cap(lead):
                    free = [r for r in remaining if under_cap(r)]
                    if free:
                        lead = max(free, key=lambda r: (remaining[r], desk_need[r]))
                last_used[lead] = di
            if out_leg is not None:
                assign(out_leg, lead)

            if back_leg is not None:
                evening = pick_evening(di, exclude=set(chosen) | {lead})
                assign(back_leg, evening)
                last_used[evening] = di
                last_evening[evening] = di

    gate(data, names, desk_need, commute_value, book_of, placed, target_min, commute_min)
    SCHEDULE.write_text(json.dumps(data, indent=2) + "\n")
    report(data, desk_need, commute_value, placed, commute_min)


def gate(data, names, desk_need, commute_value, book_of, placed, target_min, commute_min):
    """Refuse to write a plan that breaks an invariant."""
    errors = []
    window = [d for d in data["days"] if in_window(d["date"])]

    for day in window:
        starts = [b["start"] for b in day["blocks"]]
        if len(set(starts)) != len(starts):
            errors.append(f"{day['date']}: two blocks share a start time")
        if abs(sum(b["minutes"] for b in day["blocks"]) / 60 - day["hours"]) > 0.001:
            errors.append(f"{day['date']}: blocks do not sum to hours")
        desk_ids = [b.get("reading_id") for b in day["blocks"]
                    if not b.get("commute") and b.get("reading_id")]
        if len(set(desk_ids)) != len(desk_ids):
            errors.append(f"{day['date']}: a reading appears twice at the desk")
        for b in day["blocks"]:
            if b.get("reading_id") and b["reading_id"] not in names:
                errors.append(f"{day['date']}: unknown reading {b['reading_id']}")
            if b["kind"] == "questions" and not b.get("question_source"):
                errors.append(f"{day['date']} {b['start']}: question block with no bank")
        back = [b for b in day["blocks"]
                if b.get("commute") and "commute back" in b["label"].lower()]
        for b in back:
            if b.get("reading_id") in set(desk_ids):
                errors.append(f"{day['date']}: evening leg repeats the day's desk work")

    covered = {b["reading_id"] for d in window for b in d["blocks"] if b.get("reading_id")}
    if len(covered) != 36:
        errors.append(f"only {len(covered)} of 36 readings appear")

    # Starvation, measured against peers: targets sum to the reading-bearing
    # minutes, so every reading should land near 100% of its budget.
    ratios = sorted(m / target_min[r] for r, m in placed.items() if m)
    med = ratios[len(ratios) // 2]
    for rid, mins in placed.items():
        if mins and mins / target_min[rid] < 0.75 * med:
            errors.append(f"{rid}: {mins:.0f}m is "
                          f"{mins / target_min[rid] / med:.0%} of its peers' share")
        if mins - commute_min[rid] <= 0:
            errors.append(f"{rid}: never gets a desk block")
        if mins and commute_min[rid] / mins > MAX_COMMUTE_SHARE + 1e-9:
            errors.append(f"{rid}: {commute_min[rid] / mins:.0%} of its {mins:.0f}m "
                          f"is commute, over the {MAX_COMMUTE_SHARE:.0%} cap")

    ev = [commute_value[b["reading_id"]] for d in window for b in d["blocks"]
          if b.get("commute") and "commute back" in b["label"].lower()]
    allcv = sorted(commute_value.values())
    if ev and sum(ev) / len(ev) < allcv[len(allcv) // 2]:
        errors.append("evening legs are not drawn from the better commute material")

    if errors:
        for e in errors[:15]:
            print(f"  ERROR {e}")
        sys.exit(f"\n{len(errors)} error(s): refusing to write")


def report(data, desk_need, commute_value, placed, commute_min):
    window = [d for d in data["days"] if in_window(d["date"])]
    blocks = [b for d in window for b in d["blocks"]]
    total = sum(b["minutes"] for b in blocks)
    worst = max(commute_min.get(r, 0) / m for r, m in placed.items() if m)
    print(f"{len(blocks)} blocks over {len(window)} days, {total/60:.1f}h, "
          f"file total {data['total_planned_hours']}h")
    print(f"worst realized commute share {worst*100:.0f}% (cap {MAX_COMMUTE_SHARE:.0%})")

    bm = collections.Counter()
    for b in blocks:
        if b.get("book"):
            bm[b["book"]] += b["minutes"]
    bt = sum(bm.values())
    print(f"\nbook  weight   hours   share    gap")
    for bk in sorted(WEIGHT, key=lambda k: -WEIGHT[k]):
        s = bm[bk] / bt * 100
        print(f"B{bk}     {WEIGHT[bk]:4.1f}%  {bm[bk]/60:6.1f}  {s:5.1f}%  {s-WEIGHT[bk]:+5.1f}")

    def mean(v):
        return sum(v) / len(v) if v else float("nan")
    first, last, out, ev = [], [], [], []
    for d in window:
        desk = [b for b in d["blocks"] if not b.get("commute") and b.get("reading_id")]
        if desk:
            first.append(desk_need[desk[0]["reading_id"]])
            last.append(desk_need[desk[-1]["reading_id"]])
        for b in d["blocks"]:
            if not b.get("commute"):
                continue
            if "commute out" in b["label"].lower():
                out.append(desk_need[b["reading_id"]])
            else:
                ev.append(commute_value[b["reading_id"]])
    print(f"\ndesk_need — 06:00 block {mean(first):.0f} · last desk block {mean(last):.0f} "
          f"· morning leg {mean(out):.0f}")
    print(f"commute_value on the ride home: {mean(ev):.0f} "
          f"(all readings median {sorted(commute_value.values())[len(commute_value)//2]})")

    seen = collections.Counter()
    for d in window:
        for rid in {b["reading_id"] for b in d["blocks"] if b.get("reading_id")}:
            seen[rid] += 1
    print(f"each reading appears on {min(seen.values())}-{max(seen.values())} separate days")

    books_on_legs = collections.Counter()
    for d in window:
        for b in d["blocks"]:
            if b.get("commute"):
                books_on_legs[b["book"]] += 1
    print(f"commute legs by book: {dict(sorted(books_on_legs.items()))}")


if __name__ == "__main__":
    main()
