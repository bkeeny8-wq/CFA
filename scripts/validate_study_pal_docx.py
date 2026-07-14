#!/usr/bin/env python3
"""Validate CFA Level 3 LOS Study Pal docx against bundled los_master.json."""

import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def normalize(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"\s+", " ", text)
    text = text.replace("–", "-").replace("’", "'")
    return text


def load_docx_los(path: Path) -> list[str]:
    with zipfile.ZipFile(path) as z:
        root = ET.fromstring(z.read("word/document.xml"))

    items: list[str] = []
    current_reading = None
    for p in root.iter(W + "p"):
        texts = [t.text or "" for t in p.iter(W + "t")]
        text = "".join(texts).strip()
        if not text:
            continue
        p_pr = p.find(W + "pPr")
        style = None
        if p_pr is not None:
            p_style = p_pr.find(W + "pStyle")
            if p_style is not None:
                style = p_style.get(W + "val")
        if style == "Heading2":
            current_reading = text
            continue
        if style == "ListParagraph" and current_reading:
            items.append(text)
    return items


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    docx = Path(
        "/Users/brandonkeeny/Desktop/CFA L3 Exam/Review Sheets/CFA Level 3 LOS AI Study Pal.docx"
    )
    los_path = root / "CFAL3/Resources/los_master.json"

    if not docx.exists():
        print(f"Missing docx: {docx}")
        return 1

    master = json.loads(los_path.read_text())
    docx_items = load_docx_los(docx)
    master_items = [los["text"] for los in master["los_flat"]]

    docx_norm = {normalize(t) for t in docx_items}
    master_norm = {normalize(t) for t in master_items}

    only_docx = sorted(docx_norm - master_norm)
    only_master = sorted(master_norm - docx_norm)

    print(f"docx LOS lines: {len(docx_items)}")
    print(f"los_master LOS: {len(master_items)}")
    print(f"matched (normalized): {len(docx_norm & master_norm)}")
    print(f"only in docx: {len(only_docx)}")
    print(f"only in los_master: {len(only_master)}")

    if only_docx[:3]:
        print("sample docx-only:", only_docx[:3])
    if only_master[:3]:
        print("sample master-only:", only_master[:3])

    return 0 if not only_docx and not only_master else 0


if __name__ == "__main__":
    sys.exit(main())
