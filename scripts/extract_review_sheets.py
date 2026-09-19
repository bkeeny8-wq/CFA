#!/usr/bin/env python3
"""Turn the combined L3 study-notes DOCX into review_sheets.json.

Walks <w:body> in document order so tables stay where they belong, and keeps
each table's REAL column count — the notes pipeline flattened tables to one
cell per line and the app then had to guess the width, which it got wrong for
half of them. Nothing here needs guessing: the cells are in the XML.
"""
import json, re, sys, zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
SRC = "/Users/brandonkeeny/Desktop/CFA L3 Exam/Review Sheets/L3 Study Notes .docx"
OUT = sys.argv[1] if len(sys.argv) > 1 else "review_sheets.json"


def para_style(p):
    pPr = p.find(f"{W}pPr")
    if pPr is None:
        return "Normal"
    st = pPr.find(f"{W}pStyle")
    return st.get(f"{W}val") if st is not None else "Normal"


def para_text(p):
    return "".join(t.text or "" for t in p.iter(f"{W}t")).strip()


def is_numbered(p):
    pPr = p.find(f"{W}pPr")
    return pPr is not None and pPr.find(f"{W}numPr") is not None


def cell_lines(tc):
    """A cell's paragraphs, kept separate.

    Joining them with spaces ran every line of a formula box together:
    "Trend growth ≈ labor-input growth + labor-productivity growth labor
    input = labor-force growth + participation change …".
    """
    return [t for t in (para_text(p) for p in tc.findall(f"{W}p")) if t]


def table_rows(tbl):
    rows = []
    for tr in tbl.findall(f"{W}tr"):
        cells = [" ".join(cell_lines(tc)) for tc in tr.findall(f"{W}tc")]
        if any(c for c in cells):
            rows.append(cells)
    return rows


def boxed_lines(tbl):
    """A one-cell table is not a table — it is a boxed aside.

    166 of the document's 250 `w:tbl` elements are these: worked examples,
    the per-reading formula sheet, the self-test. Treating them as tables and
    then dropping anything with fewer than two rows lost every one of them.
    """
    trs = tbl.findall(f"{W}tr")
    if len(trs) != 1:
        return None
    tcs = trs[0].findall(f"{W}tc")
    if len(tcs) != 1:
        return None
    return cell_lines(tcs[0])


def slug(text):
    s = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    return s[:80]


def main():
    z = zipfile.ZipFile(SRC)
    root = ET.fromstring(z.read("word/document.xml"))
    body = root.find(f"{W}body")

    readings = []
    current = None
    bullets = []           # buffered consecutive list items

    def flush_bullets():
        nonlocal bullets
        if current is not None and bullets:
            current["blocks"].append({"kind": "bullets", "items": bullets})
        bullets = []

    seen_first_heading = False

    for child in body:
        tag = child.tag

        if tag == f"{W}tbl":
            flush_bullets()
            if current is None:
                continue
            boxed = boxed_lines(child)
            if boxed is not None:
                if boxed:
                    current["blocks"].append({"kind": "box", "lines": boxed})
                continue
            rows = table_rows(child)
            if len(rows) >= 2:
                # Square it off. A merged cell leaves a row shorter than the
                # header, and a renderer walking a ragged grid either crashes
                # or silently drops the overhang.
                width = max(len(r) for r in rows)
                if width == 1:
                    # Not a one-column table: a stack of boxed asides sharing
                    # one frame. Rendered as a table the first box became a
                    # 500-character "header" and the rest became its rows.
                    for r in rows:
                        if r[0]:
                            current["blocks"].append({"kind": "box", "lines": [r[0]]})
                    continue
                rows = [r + [""] * (width - len(r)) for r in rows]
                current["blocks"].append({
                    "kind": "table",
                    "headers": rows[0],
                    "rows": rows[1:],
                })
            elif rows:
                # A table with a header and no body is a heading in disguise;
                # keep the text rather than drop it.
                current["blocks"].append({"kind": "box", "lines": rows[0]})
            continue

        if tag != f"{W}p":
            continue

        style = para_style(child)
        text = para_text(child)

        # Front matter and the generated table of contents carry no content.
        if style in {"TOC1", "TOC2", "TOC3", "TOCHeading", "Title", "Subtitle"}:
            continue

        if style == "Heading1":
            flush_bullets()
            seen_first_heading = True
            title = re.sub(r"^Reading:\s*", "", text).strip()
            current = {
                "id": slug(title),
                "number": len(readings) + 1,
                "title": title,
                "blocks": [],
            }
            readings.append(current)
            continue

        if not seen_first_heading:
            continue        # the "Generated July 1" preamble

        if current is None or not text:
            if not text:
                flush_bullets()
            continue

        if style == "Heading2":
            flush_bullets()
            current["blocks"].append({"kind": "heading", "text": text})
            continue

        if style == "ListParagraph" or is_numbered(child):
            bullets.append(text)
            continue

        flush_bullets()
        current["blocks"].append({"kind": "paragraph", "text": text})

    flush_bullets()

    bundle = {
        "schema_version": 1,
        "source": "L3 Study Notes .docx",
        "readings": readings,
    }
    with open(OUT, "w") as f:
        json.dump(bundle, f, ensure_ascii=False, separators=(",", ":"))

    kinds = {}
    for r in readings:
        for b in r["blocks"]:
            kinds[b["kind"]] = kinds.get(b["kind"], 0) + 1
    widths = {}
    for r in readings:
        for b in r["blocks"]:
            if b["kind"] == "table":
                widths[len(b["headers"])] = widths.get(len(b["headers"]), 0) + 1

    print(f"readings: {len(readings)}")
    print(f"blocks:   {kinds}")
    print(f"table widths: {dict(sorted(widths.items()))}")
    print(f"ragged tables: "
          f"{sum(1 for r in readings for b in r['blocks'] if b['kind']=='table' and any(len(x)!=len(b['headers']) for x in b['rows']))}")
    print(f"empty readings: {[r['title'][:40] for r in readings if not r['blocks']]}")
    import os
    print(f"bytes: {os.path.getsize(OUT):,}")


if __name__ == "__main__":
    main()
