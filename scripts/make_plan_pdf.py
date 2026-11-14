#!/usr/bin/env python3
"""Render the study plan as a printable month-grid PDF.

    python3 scripts/make_plan_pdf.py [-o OUT]

Five pages, US Letter landscape: a cover, then November, December, January and
February. Weeks start Monday. Every block in the plan appears in its day's
cell, commute legs shaded.

Rendered through headless Chrome, because this machine has no PDF library
(no reportlab, fpdf, wkhtmltopdf or poppler) but does have Chrome, and a
browser is a better typesetter than any of them anyway.
"""

import argparse
import calendar
import collections
import datetime
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEDULE = ROOT / "CFAL3" / "Resources" / "study_schedule.json"
MM_REVIEW = ROOT / "CFAL3" / "Resources" / "mm_review.json"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

MONTHS = [(2026, 11), (2026, 12), (2027, 1), (2027, 2)]

BOOK_TINT = {1: "#7A8B6F", 2: "#8A7A5E", 3: "#6E7F8A", 4: "#9A6A5A",
             5: "#7E6F8A", 6: "#2C5A4F"}
BANK_LABEL = {"app": "App", "mm": "MM", "cfai": "CFAI"}

# Without this every Ethics cell reads "Guidance for Standard ..." and the
# seven of them are indistinguishable at 5.8pt. Longest first so a prefix
# never shadows a more specific rule.
SHORTEN = [
    ("Guidance for Standard VII: Responsibilities as a CFA Institute Member or CFA Candidate", "Std VII: Member resp"),
    ("Guidance for Standard V: Investment Analysis, Recommendations, and Actions", "Std V: Inv analysis"),
    ("Guidance for Standard II: Integrity of Capital Markets", "Std II: Mkt integrity"),
    ("Guidance for Standard VI: Conflicts of Interest", "Std VI: Conflicts"),
    ("Guidance for Standard IV: Duties to Employers", "Std IV: Employers"),
    ("Guidance for Standard III: Duties to Clients", "Std III: Clients"),
    ("Guidance for Standard I: Professionalism", "Std I: Professionalism"),
    ("Capital Market Expectations, Part 1: Framework and Macro Considerations", "CME 1: Framework"),
    ("Capital Market Expectations, Part 2: Forecasting Asset Class Returns", "CME 2: Forecasting"),
    ("Case Study in Portfolio Management: Institutional (Endowment)", "Case: Endowment"),
    ("Case Study in Portfolio Management: Institutional (SWF)", "Case: SWF"),
    ("Code of Ethics and Standards of Professional Conduct", "Code & Standards"),
    ("Application of the Code and Standards: Level III", "Applying the Code"),
    ("Asset Manager Code of Professional Conduct", "Asset Manager Code"),
    ("Overview of the Global Investment Performance Standards", "GIPS overview"),
    ("Fixed-Income Active Management: Credit Strategies", "FI active: credit"),
    ("Overview of Fixed-Income Portfolio Management", "FI portfolio mgmt"),
    ("Portfolio Management for Institutional Investors", "PM for institutions"),
    ("Active Equity Investing: Portfolio Construction", "Active eq: constr"),
    ("Active Equity Investing: Strategies", "Active eq: strategies"),
    ("Liability-Driven and Index-Based Strategies", "LDI & index-based"),
    ("Asset Allocation with Real-World Constraints", "AA with constraints"),
    ("Asset Allocation to Alternative Investments", "AA to alternatives"),
    ("An Overview of Private Wealth Management", "Private wealth"),
    ("Overview of Equity Portfolio Management", "Equity PM"),
    ("Swaps, Forwards, and Futures Strategies", "Swaps/fwds/futures"),
    ("Trading Costs and Electronic Markets", "Trading costs"),
    ("Currency Management: An Introduction", "Currency mgmt"),
    ("Index-Based Equity Strategies", "Index-based eq"),
    ("Portfolio Performance Evaluation", "Performance eval"),
    ("Principles of Asset Allocation", "AA principles"),
    ("Investment Manager Selection", "Manager selection"),
    ("Overview of Asset Allocation", "AA overview"),
    ("Trade Strategy and Execution", "Trade strategy"),
    ("Yield Curve Strategies", "Yield curve"),
    ("finish remaining Meldrum material", "finish Meldrum videos"),
    ("Options Strategies", "Options"),
]

PREFIX = re.compile(r"^(MM Q|App Q|CFAI Q|MM Video|MOCK|REVIEW|WEAK|"
                    r"Commute out|Commute back):\s*")


def esc(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def learning_modules():
    """reading_id → learning-module number, counted by position in its book.

    mm_review.json carries no explicit number; the MM Review tab presents the
    modules as an ordered list per book ("Book → learning module → the page it
    starts on"), so the ordinal is the number, and counting it here keeps the
    print-out saying what the app says.
    """
    out = {}
    for book in json.loads(MM_REVIEW.read_text())["books"]:
        for number, module in enumerate(book["modules"], 1):
            if module.get("readingID"):
                out[module["readingID"]] = number
    return out


def title_of(block):
    label = PREFIX.sub("", block["label"])
    label = re.sub(r"^B\d+\s+", "", label)
    for long, short in SHORTEN:
        if long in label:
            return short
    return label


def minutes_label(minutes):
    """190 is "3h10", not "3.17h" — a reader converts the decimal anyway."""
    hours, rest = divmod(minutes, 60)
    if hours and rest:
        return f"{hours}h{rest:02d}"
    if hours:
        return f"{hours}h"
    return f"{rest}m"


def leg_of(block):
    low = block["label"].lower()
    if "commute out" in low:
        return "out"
    if "commute back" in low:
        return "back"
    return None


def day_cell(day, date, exam_date, modules):
    """One day. `day` is None when the plan has no row for that date."""
    classes = ["day"]
    if date.isoformat() == exam_date:
        classes.append("exam")
    if date.isoformat() > exam_date:
        return '<td class="day blank"><div class="num">%d</div>' \
               '<div class="after">after the exam</div></td>' % date.day

    bits = [f'<div class="head"><span class="num">{date.day}</span>']
    if day and day["blocks"]:
        bits.append(f'<span class="hrs">{minutes_label(sum(b["minutes"] for b in day["blocks"]))}</span>')
    bits.append("</div>")

    if date.isoformat() == exam_date:
        bits.append('<div class="examline">CFA Level III</div>')
    elif day is None:
        pass
    elif not day["blocks"]:
        note = day.get("note") or "Rest"
        bits.append(f'<div class="rest">{esc(note)}</div>')
    else:
        for b in day["blocks"]:
            leg = leg_of(b)
            cls = "blk leg" if leg else "blk"
            bank = BANK_LABEL.get(b.get("question_source"), "")
            tint = BOOK_TINT.get(b.get("book"), "#6B645C")
            badge = (f'<span class="bank" style="background:{tint}">{bank}</span>'
                     if bank else "")
            # The badge's colour already says which book; this says which
            # learning module inside it, which is the part you cannot work out
            # from the reading's name.
            lm = modules.get(b.get("reading_id"))
            tag = f'<span class="lm">LM{lm}</span>' if lm else ""
            arrow = {"out": "&#8594;&#8201;", "back": "&#8592;&#8201;"}.get(leg, "")
            bits.append(
                f'<div class="{cls}"><span class="t">{b["start"]}</span>'
                f'{badge}{tag}<span class="n">{arrow}{esc(title_of(b))}</span></div>')
        if day.get("note"):
            bits.append(f'<div class="note">{esc(day["note"])}</div>')

    return f'<td class="{" ".join(classes)}">' + "".join(bits) + "</td>"


def month_page(year, month, by_date, exam_date, modules):
    cal = calendar.Calendar(firstweekday=0)  # Monday
    weeks = cal.monthdatescalendar(year, month)

    in_month = [d for w in weeks for d in w if d.month == month]
    rows = [by_date.get(d.isoformat()) for d in in_month]
    desk = sum(b["minutes"] for r in rows if r for b in r["blocks"] if not b.get("commute"))
    travel = sum(b["minutes"] for r in rows if r for b in r["blocks"] if b.get("commute"))

    head = (f'<div class="mhead"><h2>{calendar.month_name[month]} {year}</h2>'
            f'<span class="tot"><b>{desk/60:.1f}h</b> desk'
            + (f' &middot; <b>{travel/60:.1f}h</b> commute' if travel else "")
            + f' &middot; <b>{(desk+travel)/60:.1f}h</b> total</span></div>')

    out = [f'<section class="page">{head}<table><thead><tr>']
    for name in ("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"):
        out.append(f"<th>{name}</th>")
    out.append("</tr></thead><tbody>")
    for week in weeks:
        out.append("<tr>")
        for date in week:
            if date.month != month:
                out.append('<td class="day out"></td>')
            else:
                out.append(day_cell(by_date.get(date.isoformat()), date, exam_date, modules))
        out.append("</tr>")
    out.append("</tbody></table></section>")
    return "".join(out)


def cover_page(data, days, exam_date):
    blocks = [b for d in days for b in d["blocks"]]
    desk = sum(b["minutes"] for b in blocks if not b.get("commute"))
    travel = sum(b["minutes"] for b in blocks if b.get("commute"))
    legs = len([b for b in blocks if b.get("commute")])
    study_days = len([d for d in days if d["blocks"]])

    per_reading = collections.Counter()
    for b in blocks:
        if b.get("reading_id"):
            per_reading[title_of(b)] += b["minutes"]

    first = min(d["date"] for d in days if d["blocks"])
    rows = "".join(
        f"<li><span>{esc(name)}</span><b>{minutes_label(mins)}</b></li>"
        for name, mins in sorted(per_reading.items(), key=lambda kv: -kv[1]))

    return f"""<section class="page cover">
  <h1>CFA Level&nbsp;III</h1>
  <p class="sub">{first} to the exam on {exam_date}</p>
  <div class="stats">
    <div><b>{(desk+travel)/60:.1f}h</b><span>planned</span></div>
    <div><b>{desk/60:.1f}h</b><span>at the desk</span></div>
    <div><b>{travel/60:.1f}h</b><span>commuting</span></div>
    <div><b>{len(blocks)}</b><span>sittings</span></div>
    <div><b>{study_days}</b><span>study days</span></div>
    <div><b>{legs}</b><span>commute legs</span></div>
  </div>
  <div class="legendrow">
    <span class="k"><i class="sw legk"></i>shaded row = commute leg, phone, no calculator</span>
    <span class="k"><i class="sw bk1"></i>Asset allocation</span>
    <span class="k"><i class="sw bk2"></i>Portfolio constr.</span>
    <span class="k"><i class="sw bk3"></i>Perf. measurement</span>
    <span class="k"><i class="sw bk4"></i>Derivatives</span>
    <span class="k"><i class="sw bk5"></i>Ethics</span>
    <span class="k"><i class="sw bk6"></i>PM pathway</span>
  </div>
  <p class="note2">Day totals read like <b>2h10</b>, not 2.17h — the app shows the decimal.</p>
  <h3>Hours per reading</h3>
  <ul class="cov">{rows}</ul>
</section>"""


CSS = """
@page { size: letter landscape; margin: 9mm; }
* { box-sizing: border-box; }
body { margin:0; font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
       color:#1A1614; background:#F3EEE6; -webkit-print-color-adjust: exact;
       print-color-adjust: exact; }
.page { width: 100%; height: 187mm; page-break-after: always; overflow: hidden; }
.page:last-child { page-break-after: auto; }
.mhead { display:flex; align-items:baseline; justify-content:space-between;
         margin: 0 0 4px; }
h2 { font-family: Georgia, serif; font-size: 15pt; margin:0; }
.tot { font-size: 7.5pt; color:#6B645C; }
table { width:100%; border-collapse: collapse; table-layout: fixed; }
th { font-size: 6pt; letter-spacing:.08em; color:#6B645C; text-align:left;
     padding: 2px 3px; font-weight:600; }
td.day { border:.5pt solid #DDD5C8; vertical-align: top; height: 29mm;
         padding: 2px 3px; background:#FCF9F4; overflow:hidden; }
td.day.out { background:#F3EEE6; border-color:#EDE6DA; }
td.day.blank { background:#F3EEE6; }
td.day.exam { background:#2C5A4F; }
td.day.exam .num, td.day.exam .examline { color:#FCF9F4; }
.head { display:flex; justify-content:space-between; align-items:baseline; }
.num { font-size: 8pt; font-weight:700; }
.hrs { font-size: 5.6pt; color:#6B645C; }
.after { font-size:5.6pt; color:#B5ADA0; font-style:italic; margin-top:3px; }
.rest { font-size:6pt; color:#6B645C; font-style:italic; margin-top:4px; }
.examline { font-family:Georgia,serif; font-size:7.5pt; margin-top:6px; }
.blk { font-size:5.8pt; line-height:1.28; display:flex; gap:2px;
       align-items:baseline; margin-top:1.5px; white-space:nowrap;
       overflow:hidden; }
.blk .t { color:#6B645C; flex:0 0 auto; }
.blk .n { overflow:hidden; text-overflow:ellipsis; }
.blk.leg { background:#F6EDE4; border-radius:2px; padding:0 2px; margin-left:-2px; }
.lm { color:#6B645C; font-size:4.6pt; flex:0 0 auto; letter-spacing:-.01em; }
.bank { color:#FCF9F4; font-size:4.4pt; padding:0 2px; border-radius:2px;
        flex:0 0 auto; position:relative; top:-.4pt; }
.note { font-size:5.4pt; color:#C47A4A; margin-top:2px; }
/* cover */
.cover h1 { font-family:Georgia,serif; font-size:30pt; margin:6mm 0 0; }
.sub { color:#6B645C; margin:2px 0 7mm; font-size:9pt; }
.stats { display:flex; gap:12mm; margin-bottom:7mm; }
.stats div { display:flex; flex-direction:column; }
.stats b { font-family:Georgia,serif; font-size:17pt; }
.stats span { font-size:7pt; color:#6B645C; }
.legendrow { display:flex; flex-wrap:wrap; gap:5mm; margin-bottom:3mm; }
.k { font-size:6.6pt; color:#6B645C; display:flex; align-items:center; gap:3px; }
.sw { width:8px; height:8px; border-radius:2px; display:inline-block; }
.legk { background:#F6EDE4; border:.5pt solid #D8C9B6; }
.bk1{background:#7A8B6F}.bk2{background:#8A7A5E}.bk3{background:#6E7F8A}
.bk4{background:#9A6A5A}.bk5{background:#7E6F8A}.bk6{background:#2C5A4F}
.note2 { font-size:6.6pt; color:#6B645C; margin:0 0 5mm; }
h3 { font-family:Georgia,serif; font-size:10pt; margin:0 0 2mm; }
.cov { list-style:none; margin:0; padding:0; columns:4; column-gap:7mm;
       font-size:6.4pt; }
.cov li { display:flex; justify-content:space-between; gap:4px;
          break-inside:avoid; padding:1px 0; border-bottom:.4pt solid #E7DFD2; }
.cov li span { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.cov li b { color:#2C5A4F; flex:0 0 auto; }
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default=str(ROOT / "calendar" / "CFA_L3_plan.pdf"))
    ap.add_argument("--keep-html", action="store_true")
    args = ap.parse_args()

    if not pathlib.Path(CHROME).exists():
        sys.exit(f"Chrome not found at {CHROME}; this script renders through it.")

    data = json.loads(SCHEDULE.read_text())
    exam = data["exam_date"]
    days = [d for d in data["days"] if d["date"] >= "2026-11-06"]
    by_date = {d["date"]: d for d in days}

    pages = [cover_page(data, days, exam)]
    modules = learning_modules()
    pages += [month_page(y, m, by_date, exam, modules) for y, m in MONTHS]
    html = (f"<!doctype html><meta charset='utf-8'><title>CFA L3 plan</title>"
            f"<style>{CSS}</style>" + "".join(pages))

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="cfaplan-"))
    html_path = tmp / "plan.html"
    html_path.write_text(html, encoding="utf-8")

    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--no-pdf-header-footer",
         f"--print-to-pdf={out}", f"file://{html_path}"],
        check=True, capture_output=True)

    if args.keep_html:
        shutil.copy(html_path, out.with_suffix(".html"))
    shutil.rmtree(tmp, ignore_errors=True)

    blocks = sum(len(d["blocks"]) for d in days)
    size = out.stat().st_size // 1024
    print(f"wrote {out} ({size} KB)")
    print(f"  cover + {len(MONTHS)} month grids, {blocks} sittings")


if __name__ == "__main__":
    main()
