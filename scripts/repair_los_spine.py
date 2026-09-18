#!/usr/bin/env python3
"""Normalize los_master to the 2027 PM-pathway outline and remap IDs.

P0: merge wrap splits, drop phantom last-letter duplicates, restore full
command-word text, add Asset Manager Code, remap drills/flashcards/cases.
Does not author new drills. Does not cosine-retag cases.
"""

from __future__ import annotations

import json
import string
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "CFAL3/Resources"

LETTERS = string.ascii_lowercase

WRAPS = {
    "capital_market_expectations_part_2_forecasting_asset_class_returns": ("e", "f"),
    "overview_of_asset_allocation": ("i", "j"),
    "asset_allocation_to_alternative_investments": ("a", "b"),
    "options_strategies": ("f", "g"),
    "active_equity_investing_portfolio_construction": ("e", "f"),
    "case_study_in_portfolio_management_institutional_endowment": ("d", "e"),
}

PHANTOMS = {
    "capital_market_expectations_part_1_framework_and_macro_considerations": "k",
    "overview_of_asset_allocation": "l",
    "portfolio_management_for_institutional_investors": "i",
    "trading_costs_and_electronic_markets": "k",
    "swaps_forwards_and_futures_strategies": "g",
    "asset_allocation_to_alternative_investments": "j",
}

MERGED_TEXT = {
    (
        "capital_market_expectations_part_2_forecasting_asset_class_returns",
        "e",
    ): (
        "explain how economic and competitive factors can affect "
        "expectations for real estate investment markets and sector returns"
    ),
    (
        "overview_of_asset_allocation",
        "i",
    ): (
        "discuss strategic implementation choices in asset allocation, "
        "including passive/active choices and vehicles for implementing "
        "passive and active mandates"
    ),
    (
        "asset_allocation_to_alternative_investments",
        "a",
    ): "explain the roles that alternative investments play in multi-asset portfolios",
    (
        "options_strategies",
        "f",
    ): (
        "discuss the investment objective(s), structure, payoffs, risk(s), "
        "value at expiration, profit, maximum profit, maximum loss, and "
        "breakeven underlying price at expiration of the following option "
        "strategies: bull spread, bear spread, straddle, and collar"
    ),
    (
        "active_equity_investing_portfolio_construction",
        "e",
    ): (
        "discuss risk measures that are incorporated in equity portfolio "
        "construction and describe how limits set on these measures affect "
        "portfolio construction"
    ),
    (
        "case_study_in_portfolio_management_institutional_endowment",
        "d",
    ): (
        "demonstrate the application of the Code of Ethics and Standards of "
        "Professional Conduct regarding the actions of individuals involved "
        "in manager selection"
    ),
}

AMC_READING_ID = "asset_manager_code_of_professional_conduct"
AMC_NAME = "Asset Manager Code of Professional Conduct"
AMC_AREA = "ethical_and_professional_standards"
AMC_LOS = [
    "explain the purpose of the Asset Manager Code and the benefits that may accrue to a firm that adopts the Code",
    "explain the ethical and professional responsibilities required by the six General Principles of Conduct of the Asset Manager Code",
    "determine whether an asset manager's practices and procedures are consistent with the Asset Manager Code",
    "recommend practices and procedures designed to prevent violations of the Asset Manager Code",
]

# Old letter → new letter for the four shifted drill bundles.
# Options / construction already sit on official letters; keep them.
# Alts is semantic (not a one-step slide). PWM is a different 5-LOS scheme.
DRILL_LETTER_OVERRIDE = {
    "options_strategies": {ch: ch for ch in "abcdefghij"},
    "active_equity_investing_portfolio_construction": {ch: ch for ch in "abcdefgh"},
    "asset_allocation_to_alternative_investments": {
        "a": "a",
        "b": "c",
        "c": "d",
        "d": "e",
        "e": "f",
        "f": "f",
        "g": "g",
        "h": "g",
        "i": "d",
        "j": "h",
    },
    "an_overview_of_private_wealth_management": {
        "a": "e",
        "b": "e",
        "c": "b",
        "d": "e",
        "e": "d",
    },
}


def cleanup(text: str) -> str:
    return text.replace(",and", ", and").replace("--", "–")


def dump(path: Path, payload, indent: int = 2) -> None:
    path.write_text(
        json.dumps(payload, indent=indent, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def rebuild_master(master: dict) -> tuple[dict, dict[str, str]]:
    old_to_new: dict[str, str] = {}
    for area in master["areas"]:
        for reading in area["readings"]:
            rid = reading["id"]
            wrap = WRAPS.get(rid)
            phantom = PHANTOMS.get(rid)
            kept = []
            old_letter_to_new: dict[str, str] = {}
            for item in reading["los"]:
                letter = item["letter"]
                if phantom and letter == phantom:
                    old_letter_to_new[letter] = "a"
                    continue
                if wrap and letter == wrap[1]:
                    continue
                kept.append(item)

            new_items = []
            for i, item in enumerate(kept):
                new_letter = LETTERS[i]
                old_letter_to_new[item["letter"]] = new_letter
                text = item["text"]
                if wrap and item["letter"] == wrap[0]:
                    text = MERGED_TEXT[(rid, wrap[0])]
                else:
                    text = cleanup(text)
                new_items.append(
                    {
                        "id": f"{rid}.{new_letter}",
                        "letter": new_letter,
                        "text": text,
                        "reading_id": rid,
                        "area_id": item["area_id"],
                    }
                )
            if wrap:
                old_letter_to_new[wrap[1]] = old_letter_to_new[wrap[0]]
            for old_letter, new_letter in old_letter_to_new.items():
                old_to_new[f"{rid}.{old_letter}"] = f"{rid}.{new_letter}"
            reading["los"] = new_items

        if area["id"] == AMC_AREA:
            amc_los = []
            for i, text in enumerate(AMC_LOS):
                letter = LETTERS[i]
                amc_los.append(
                    {
                        "id": f"{AMC_READING_ID}.{letter}",
                        "letter": letter,
                        "text": text,
                        "reading_id": AMC_READING_ID,
                        "area_id": AMC_AREA,
                    }
                )
            area["readings"].append(
                {
                    "id": AMC_READING_ID,
                    "name": AMC_NAME,
                    "area_id": AMC_AREA,
                    "los": amc_los,
                }
            )

    flat = []
    for area in master["areas"]:
        for reading in area["readings"]:
            flat.extend(reading["los"])
    master["los_flat"] = flat
    return master, old_to_new


def remap_id(old: str, table: dict[str, str]) -> str:
    return table.get(old, old)


def dedupe(seq: list[str]) -> list[str]:
    seen = set()
    out = []
    for item in seq:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def remap_cases(bank: dict, table: dict[str, str]) -> dict[str, int]:
    stats = {"questions": 0, "tags_in": 0, "tags_out": 0, "ids_changed": 0}
    for topic in bank.get("topics", []):
        for case in topic.get("cases", []):
            for q in case.get("questions", []):
                stats["questions"] += 1
                old_tags = list(q.get("candidate_los") or [])
                stats["tags_in"] += len(old_tags)
                new_tags = dedupe(remap_id(t, table) for t in old_tags)
                stats["tags_out"] += len(new_tags)
                if new_tags != old_tags:
                    stats["ids_changed"] += sum(
                        1 for a, b in zip(old_tags, [remap_id(t, table) for t in old_tags]) if a != b
                    )
                    # count replacements even when list shortens
                    stats["ids_changed"] += max(0, len(old_tags) - len(new_tags))
                    q["candidate_los"] = new_tags
    return stats


def remap_flashcards(deck: dict, table: dict[str, str]) -> int:
    changed = 0
    for card in deck.get("cards", []):
        old = card.get("los_id")
        if not old:
            continue
        new = remap_id(old, table)
        if new != old:
            card["los_id"] = new
            changed += 1
    return changed


def drill_remap_table(reading_id: str, mechanical: dict[str, str]) -> dict[str, str]:
    override = DRILL_LETTER_OVERRIDE.get(reading_id)
    if not override:
        return mechanical
    out = {}
    for old_letter, new_letter in override.items():
        out[f"{reading_id}.{old_letter}"] = f"{reading_id}.{new_letter}"
    return out


def remap_drill_bundle(bundle: dict, mechanical: dict[str, str], master_text: dict[str, str]) -> dict[str, int]:
    reading_id = None
    if bundle.get("reading"):
        reading_id = bundle["reading"].get("reading_id")
    if not reading_id and bundle.get("drills"):
        reading_id = bundle["drills"][0].get("reading_id")
    table = drill_remap_table(reading_id or "", mechanical)

    merged: dict[str, dict] = {}
    order: list[str] = []
    groups_in = len(bundle.get("drills") or [])
    q_changed = 0
    for group in bundle.get("drills") or []:
        old_id = group["los_id"]
        new_id = remap_id(old_id, table)
        letter = new_id.rsplit(".", 1)[-1]
        if new_id not in merged:
            merged[new_id] = group
            order.append(new_id)
            group["los_id"] = new_id
            group["los_letter"] = letter
            group["los_text"] = master_text[new_id]
        else:
            merged[new_id]["questions"].extend(group.get("questions") or [])
        for q in group.get("questions") or []:
            if q.get("primary_los") != new_id:
                q["primary_los"] = new_id
                q_changed += 1

    new_groups = [merged[i] for i in sorted(order, key=lambda s: s.rsplit(".", 1)[-1])]
    bundle["drills"] = new_groups
    if bundle.get("reading"):
        bundle["reading"]["los_count"] = len(new_groups)
        bundle["reading"]["question_count"] = sum(len(g.get("questions") or []) for g in new_groups)
    return {
        "groups_in": groups_in,
        "groups_out": len(new_groups),
        "questions_remapped": q_changed,
    }


def amc_flashcards() -> list[dict]:
    area = AMC_AREA
    rid = AMC_READING_ID
    return [
        {
            "id": f"fc_{rid}_001",
            "reading_id": rid,
            "area_id": area,
            "los_id": f"{rid}.a",
            "type": "concept",
            "front": "What is the purpose of the CFA Institute Asset Manager Code, and what benefits can a firm that adopts it expect?",
            "back": "Purpose: a voluntary, firm-level code of ethical and professional responsibilities for asset-management firms — distinct from the Code and Standards, which bind individual members and candidates.\nBenefits of adoption: a ready-made framework for meeting regulations that require an adviser's code of ethics; a public signal of ethical culture to clients and prospects; a consistent internal standard across loyalty to clients, the investment process, trading, compliance, performance, and disclosure.\nTrap: employing CFA charterholders does not make adoption mandatory; the Code is voluntary and applies to FIRMS, not to individuals acting alone.",
            "mnemonic": "Firm-level, voluntary, six-area playbook — not the individual Code and Standards.",
            "difficulty": "core",
        },
        {
            "id": f"fc_{rid}_002",
            "reading_id": rid,
            "area_id": area,
            "los_id": f"{rid}.b",
            "type": "concept",
            "front": "Name the six General Principles of Conduct of the Asset Manager Code and the ethical responsibility each one captures.",
            "back": "1. Loyalty to Clients — place client interests first; preserve confidentiality; refuse gifts that reasonably could affect independence.\n2. Investment Process and Actions — use reasonable care and independent judgment; have a reasonable and adequate basis; fair dealing; suitability.\n3. Trading — best execution; fair allocation of trades and opportunities (including IPOs); do not place personal trades ahead of clients.\n4. Risk Management, Compliance, and Support — a compliance officer, policies and procedures, a disaster-recovery plan, and adequate resources.\n5. Performance and Valuation — fair, accurate, complete, timely, and relevant presentation; fair valuation.\n6. Disclosures — timely disclosure of conflicts, fees, risks, and other material facts so clients can make informed decisions.",
            "mnemonic": "Loyalty, Process, Trading, Compliance, Performance, Disclosure.",
            "difficulty": "core",
        },
        {
            "id": f"fc_{rid}_003",
            "reading_id": rid,
            "area_id": area,
            "los_id": f"{rid}.c",
            "type": "pitfall",
            "front": "A firm allocates the same number of shares of an oversubscribed IPO to every client account, including accounts that never buy IPOs. Does that practice comply with the Asset Manager Code?",
            "back": "No. Equal share counts is not fair dealing. Trading/process principles require fair allocation of investment opportunities given each client's objectives, constraints, and mandate — not a mechanical headcount of shares.\nA client who does not participate in IPOs should not be padded into the allocation, and a client for whom the IPO is suitable should not be shorted so that unrelated accounts can be 'treated equally.'\nTo judge compliance, map the practice to the six principles (here: Loyalty to Clients and Trading / fair allocation) rather than asking whether a rule of thumb 'looks even.'",
            "difficulty": "core",
        },
        {
            "id": f"fc_{rid}_004",
            "reading_id": rid,
            "area_id": area,
            "los_id": f"{rid}.d",
            "type": "process",
            "front": "Recommend procedures a firm should put in place so that its practices stay consistent with the Asset Manager Code.",
            "back": "• Adopt the Code at the firm level and name a compliance officer with authority to enforce it.\n• Written policies for loyalty/confidentiality, suitability, fair dealing, best execution, trade allocation, personal trading, valuation, and performance presentation.\n• Disclose conflicts, fees, and risks to clients in a timely way; record the disclosures.\n• Fair, accurate, complete performance reporting (GIPS compliance is supportive, not a substitute).\n• Resource the compliance, risk, and disaster-recovery functions; review them.\n• Train staff and test adherence (sample allocations, IPO books, personal-trade logs) rather than relying on a one-time policy memo.",
            "mnemonic": "Policy, officer, disclose, value fairly, resource, then test.",
            "difficulty": "core",
        },
    ]


def main() -> None:
    master_path = RES / "los_master.json"
    before = json.loads(master_path.read_text(encoding="utf-8"))
    n_readings_before = sum(len(a["readings"]) for a in before["areas"])
    n_los_before = len(before["los_flat"])

    master, mechanical = rebuild_master(before)
    n_readings_after = sum(len(a["readings"]) for a in master["areas"])
    n_los_after = len(master["los_flat"])
    dump(master_path, master)
    master_text = {item["id"]: item["text"] for item in master["los_flat"]}
    known = set(master_text)

    bank_path = RES / "question_bank.json"
    bank = json.loads(bank_path.read_text(encoding="utf-8"))
    case_stats = remap_cases(bank, mechanical)
    dump(bank_path, bank)

    fc_path = RES / "flashcards.json"
    deck = json.loads(fc_path.read_text(encoding="utf-8"))
    fc_changed = remap_flashcards(deck, mechanical)
    existing_amc = any(c.get("reading_id") == AMC_READING_ID for c in deck["cards"])
    if not existing_amc:
        deck["cards"].extend(amc_flashcards())
    dump(fc_path, deck, indent=1)

    drill_stats = []
    q_remap_total = 0
    for path in sorted(RES.glob("los_drills_r*.json")):
        bundle = json.loads(path.read_text(encoding="utf-8"))
        st = remap_drill_bundle(bundle, mechanical, master_text)
        q_remap_total += st["questions_remapped"]
        drill_stats.append((path.name, st))
        dump(path, bundle)

    # Integrity pin
    pin_fail = []
    unknown_fail = []
    for path in sorted(RES.glob("los_drills_r*.json")):
        bundle = json.loads(path.read_text(encoding="utf-8"))
        seen = set()
        for g in bundle["drills"]:
            lid = g["los_id"]
            if lid in seen:
                pin_fail.append(f"{path.name} duplicate group {lid}")
            seen.add(lid)
            if lid not in known:
                unknown_fail.append(f"{path.name} {lid}")
            elif g.get("los_text") != master_text[lid]:
                pin_fail.append(f"{path.name} text pin {lid}")
            letter = lid.rsplit(".", 1)[-1]
            if g.get("los_letter") != letter:
                pin_fail.append(f"{path.name} letter {lid}")
            for q in g["questions"]:
                if q.get("primary_los") != lid:
                    pin_fail.append(f"{path.name} primary_los {q.get('id')}")

    case_unknown = []
    for topic in bank.get("topics", []):
        for case in topic.get("cases", []):
            for q in case.get("questions", []):
                for lid in q.get("candidate_los") or []:
                    if lid not in known:
                        case_unknown.append(f"{q.get('id')} -> {lid}")

    fc_unknown = [
        f"{c['id']} -> {c.get('los_id')}"
        for c in deck["cards"]
        if c.get("los_id") and c["los_id"] not in known
    ]

    print("READINGS", n_readings_before, "->", n_readings_after)
    print("LOS", n_los_before, "->", n_los_after)
    print("MECHANICAL_ID_MAP", len(mechanical))
    shifted = sum(1 for a, b in mechanical.items() if a != b)
    print("MECHANICAL_SHIFTED", shifted)
    print("CASE_QUESTIONS", case_stats["questions"])
    print("CASE_TAGS_IN", case_stats["tags_in"], "OUT", case_stats["tags_out"])
    print("CASE_ID_CHANGES", case_stats["ids_changed"])
    print("FLASHCARD_REMAPPED", fc_changed, "AMC_CARDS_ADDED", 0 if existing_amc else 4)
    print("DRILL_PRIMARY_LOS_REMAPPED", q_remap_total)
    for name, st in drill_stats:
        if st["groups_in"] != st["groups_out"] or st["questions_remapped"]:
            print(f"  {name}: groups {st['groups_in']}->{st['groups_out']} q_remap={st['questions_remapped']}")
    print("PIN_FAIL", len(pin_fail))
    for row in pin_fail[:20]:
        print(" ", row)
    print("UNKNOWN_DRILL", unknown_fail)
    print("UNKNOWN_CASE", len(case_unknown), case_unknown[:10])
    print("UNKNOWN_FC", fc_unknown)
    if n_readings_after != 36 or n_los_after != 247:
        raise SystemExit(f"count mismatch: {n_readings_after} readings / {n_los_after} LOS")
    if pin_fail or unknown_fail or case_unknown or fc_unknown:
        raise SystemExit("integrity failures")
    print("OK")


if __name__ == "__main__":
    main()
