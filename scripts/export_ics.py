#!/usr/bin/env python3
"""Export the study plan as an iCalendar file.

    python3 scripts/export_ics.py [-o OUT] [--from YYYY-MM-DD] [--alarms]

One VEVENT per block, plus an all-day event for each rest day and for the exam.

TIMES ARE FLOATING — no timezone and no trailing Z. A floating time means
"06:00 wherever you are", which is what a study plan actually wants: the plan
was written against a commute, not against a UTC offset, and pinning it to
America/New_York would shift every block by an hour the moment you opened it
somewhere else. Apple Calendar, Google Calendar and Outlook all accept this.

UIDs are stable and match the app's own `resultKey(on:)` — "<date>|<start>" —
so re-importing after the plan is regenerated UPDATES each event rather than
duplicating it. Re-export and re-import as often as the plan changes.
"""

import argparse
import json
import pathlib
import datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEDULE = ROOT / "CFAL3" / "Resources" / "study_schedule.json"
MM_REVIEW = ROOT / "CFAL3" / "Resources" / "mm_review.json"

BOOK = {
    1: "Asset Allocation",
    2: "Portfolio Construction",
    3: "Performance Measurement",
    4: "Derivatives & Risk Management",
    5: "Ethics",
    6: "PM Pathway",
}
BANK = {"app": "Daybook", "mm": "MarkMeldrum", "cfai": "CFA Institute"}


def learning_modules():
    """reading_id → (book name, module number, first page, last page, file).

    The module number is the reading's POSITION in its book, because the data
    carries no explicit number — mm_review.json is an ordered list of modules
    per book, which is exactly how the MM Review tab presents them ("Book →
    learning module → the page it starts on"). Counting from the list keeps
    the calendar and the app saying the same thing.
    """
    out = {}
    for book in json.loads(MM_REVIEW.read_text())["books"]:
        for number, module in enumerate(book["modules"], 1):
            rid = module.get("readingID")
            if rid:
                out[rid] = (book["name"], number, module["startPage"],
                            module["endPage"], book["fileName"])
    return out


def escape(text):
    """RFC 5545 TEXT escaping. Backslash first, or it escapes its own output."""
    return (text.replace("\\", "\\\\")
                .replace(";", "\\;")
                .replace(",", "\\,")
                .replace("\n", "\\n"))


def fold(line):
    """RFC 5545 caps a content line at 75 OCTETS, not characters.

    Folding on characters splits multi-byte UTF-8 mid-codepoint and the event
    silently fails to parse in some clients. Measure the encoded length.
    """
    raw = line.encode("utf-8")
    if len(raw) <= 75:
        return line
    out, start = [], 0
    limit = 75
    while start < len(raw):
        end = min(start + limit, len(raw))
        # Do not split a codepoint: back off to a lead byte.
        while end > start and end < len(raw) and (raw[end] & 0xC0) == 0x80:
            end -= 1
        out.append(raw[start:end].decode("utf-8"))
        start = end
        limit = 74  # continuation lines carry a leading space
    return "\r\n ".join(out)


def strip_code(label):
    """Drop the bank prefix the plan writes: "MM Q: B6 Liability-Driven…"."""
    for prefix in ("MM Q:", "App Q:", "CFAI Q:", "MM Video:", "MOCK:", "REVIEW:",
                   "WEAK:", "Commute out:", "Commute back:"):
        if label.startswith(prefix):
            rest = label[len(prefix):].strip()
            # "B6 Liability-Driven…" → "Liability-Driven…"
            if rest[:1] == "B" and rest[1:2].isdigit():
                rest = rest[2:].strip()
            return rest
    return label


def leg_of(block):
    low = block["label"].lower()
    if "commute out" in low:
        return "out"
    if "commute back" in low:
        return "back"
    return None


def where(block, modules):
    """"B6 LM4" — the book and learning module, leading the title.

    This goes FIRST because calendar titles truncate from the right, and in a
    month view you may only see the first dozen characters. Which book and
    module a reading sits in is the thing you cannot work out from the reading
    name, so it is the part that has to survive truncation.
    """
    book = block.get("book")
    rid = block.get("reading_id")
    mod = modules.get(rid) if rid else None
    if book and mod:
        return f"B{book} LM{mod[1]}"
    if book:
        # Application of the Code has no Meldrum module of its own.
        return f"B{book}"
    return ""


def summarise(block, modules):
    """The line you read in a week view."""
    title = strip_code(block["label"])
    leg = leg_of(block)
    place = where(block, modules)
    kind = block["kind"]

    if kind == "mock":
        return f"Mock exam · {title}"
    if kind == "review":
        return f"Paper review · {title}"
    if kind == "video":
        return f"Meldrum video · {title}"
    if not block.get("reading_id"):
        # The February taper: assigned from your own scores on the day.
        return "Drills · weakest reading (pick on the day)"

    bank = BANK.get(block.get("question_source"), "")
    lead = f"{place} · " if place else ""
    if leg:
        # The arrow carries the direction the words used to: → out, ← home.
        # The start time implies it too, but not in a list view sorted by
        # anything other than time.
        return f"🚆{'→' if leg == 'out' else '←'} {lead}{title}"
    return f"{lead}{title}" + (f" ({bank})" if bank else "")


def describe(block, day, modules):
    lines = []
    if block.get("book"):
        lines.append(f"Book {block['book']} — {BOOK[block['book']]}")
    mod = modules.get(block.get("reading_id") or "")
    if mod:
        _, number, first, last, filename = mod
        lines.append(f"Learning module {number} — pages {first}–{last} of {filename}"
                     + f" ({last - first + 1} pages)")
    if block.get("question_source"):
        lines.append(f"Answer in: {BANK.get(block['question_source'], block['question_source'])}")
    if leg_of(block):
        lines.append("On the phone, no calculator — these drills are classified "
                     "as needing neither calculator nor scratch working.")
    desk = sum(b["minutes"] for b in day["blocks"] if not b.get("commute"))
    travel = sum(b["minutes"] for b in day["blocks"] if b.get("commute"))
    lines.append(f"Day total {day['hours']:.2f}h — {desk}m at the desk"
                 + (f", {travel}m commuting" if travel else ""))
    if day.get("note"):
        lines.append(f"Note: {day['note']}")
    return "\\n".join(escape(line) for line in lines)


def categories(block):
    cats = ["CFA L3"]
    cats.append("Commute" if block.get("commute") else "Desk")
    cats.append({"mock": "Mock", "review": "Review", "video": "Video"}
                .get(block["kind"], "Drills"))
    if block.get("book"):
        cats.append(BOOK[block["book"]])
    return ",".join(escape(c) for c in cats)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default=str(ROOT / "CFA_L3_plan.ics"))
    ap.add_argument("--from", dest="start", default="2026-11-06",
                    help="first date to export (default: the rebuilt plan's start)")
    ap.add_argument("--alarms", action="store_true",
                    help="add a 10-minute reminder to every block (off by "
                         "default: 389 of them is a lot of buzzing)")
    args = ap.parse_args()

    data = json.loads(SCHEDULE.read_text())
    modules = learning_modules()
    days = [d for d in data["days"] if d["date"] >= args.start]

    out = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//CFAL3 Daybook//Study plan//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:CFA Level III plan",
        f"X-WR-CALDESC:{escape('Study plan to the 20 February 2027 exam. Times are local.')}",
    ]

    stamp = "20261112T000000Z"  # fixed, so re-exports diff cleanly
    blocks = 0

    for day in days:
        date = day["date"]
        compact = date.replace("-", "")

        if not day["blocks"]:
            nxt = (datetime.date.fromisoformat(date)
                   + datetime.timedelta(days=1)).isoformat().replace("-", "")
            out += [
                "BEGIN:VEVENT",
                f"UID:{date}-rest@cfal3",
                f"DTSTAMP:{stamp}",
                f"DTSTART;VALUE=DATE:{compact}",
                f"DTEND;VALUE=DATE:{nxt}",
                f"SUMMARY:{escape('Rest day' + (' — ' + day['note'] if day.get('note') else ''))}",
                "CATEGORIES:CFA L3,Rest",
                "TRANSP:TRANSPARENT",
                "END:VEVENT",
            ]
            continue

        for block in day["blocks"]:
            h, m = (int(x) for x in block["start"].split(":"))
            begin = datetime.datetime(2000, 1, 1, h, m)
            finish = begin + datetime.timedelta(minutes=block["minutes"])
            # Nothing in the plan runs past midnight — the latest any block
            # ends is 17:50, the evening commute leg — so DTEND carries the
            # same date as DTSTART. If a future plan ever schedules past
            # midnight this would emit a backwards event, so it is checked.
            if finish.day != 1:
                raise SystemExit(
                    f"{date} {block['start']} runs {block['minutes']}m past "
                    "midnight; DTEND needs to roll to the next date")
            out += [
                "BEGIN:VEVENT",
                f"UID:{date}|{block['start']}@cfal3",
                f"DTSTAMP:{stamp}",
                f"DTSTART:{compact}T{begin:%H%M}00",
                f"DTEND:{compact}T{finish:%H%M}00",
                f"SUMMARY:{escape(summarise(block, modules))}",
                f"DESCRIPTION:{describe(block, day, modules)}",
                f"CATEGORIES:{categories(block)}",
                "TRANSP:OPAQUE",
            ]
            if args.alarms:
                out += ["BEGIN:VALARM", "ACTION:DISPLAY",
                        "DESCRIPTION:Reminder", "TRIGGER:-PT10M", "END:VALARM"]
            out.append("END:VEVENT")
            blocks += 1

    exam = data["exam_date"]
    nxt = (datetime.date.fromisoformat(exam)
           + datetime.timedelta(days=1)).isoformat().replace("-", "")
    out += [
        "BEGIN:VEVENT",
        f"UID:{exam}-exam@cfal3",
        f"DTSTAMP:{stamp}",
        f"DTSTART;VALUE=DATE:{exam.replace('-', '')}",
        f"DTEND;VALUE=DATE:{nxt}",
        "SUMMARY:CFA Level III exam",
        "CATEGORIES:CFA L3,Exam",
        "TRANSP:OPAQUE",
        "END:VEVENT",
        "END:VCALENDAR",
    ]

    text = "\r\n".join(fold(line) for line in out) + "\r\n"
    path = pathlib.Path(args.out)
    path.write_text(text, encoding="utf-8")

    rest = len([d for d in days if not d["blocks"]])
    print(f"wrote {path}")
    print(f"  {blocks} study blocks over {len(days) - rest} days, "
          f"{rest} rest days, 1 exam")
    print(f"  {len(text.encode('utf-8')) // 1024} KB, times are floating local")


if __name__ == "__main__":
    main()
