#!/usr/bin/env python3
"""Author original drills for AMC .a–.d, PWM .a/.c, and alts .b.

IDs avoid the remapped r8/r9 question ids (r8_altaa_los_b_*, r9_pwm_los_a_*,
r9_pwm_los_c_*). Keys rotate A,B,C,A,B,C per six-item group.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "CFAL3/Resources"
KEYS = ("A", "B", "C")


def q(qid, number, stem, options, correct, rationales, primary, reading, area, ref):
    return {
        "id": qid,
        "number": number,
        "stem": stem,
        "options": options,
        "correct": correct,
        "rationales": rationales,
        "type": "mc",
        "primary_los": primary,
        "reading_id": reading,
        "area_id": area,
        "difficulty": "l3_exam",
        "curriculum_ref": ref,
        "data_quality": "complete",
        "data_quality_flags": [],
    }


def unique_longest(opts, correct):
    cl = len(opts[correct])
    others = [len(opts[k]) for k in KEYS if k != correct]
    return cl > max(others)


def unique_shortest(opts, correct):
    cl = len(opts[correct])
    others = [len(opts[k]) for k in KEYS if k != correct]
    return cl < min(others)


def balance_item(item):
    """Lengthen the shortest option with a real teaching clause until the key
    is neither uniquely longest nor uniquely shortest."""
    opts = item["options"]
    correct = item["correct"]
    tails = {
        "A": " Keep the mechanism, not the slogan, in view when you pick.",
        "B": " The item is testing that operational difference, not a label.",
        "C": " Grade the practice by what it actually does for the client.",
    }
    guard = 0
    while unique_longest(opts, correct) or unique_shortest(opts, correct):
        shortest = min(KEYS, key=lambda k: (len(opts[k]), k))
        opts[shortest] = opts[shortest].rstrip() + tails[shortest]
        guard += 1
        if guard > 8:
            raise RuntimeError(f"could not length-balance {item['id']}: { {k: len(opts[k]) for k in KEYS} }")
    item["options"] = {k: opts[k] for k in KEYS}
    return item


def group(los_id, letter, text, reading_id, reading_name, area_id, questions):
    for i, item in enumerate(questions, start=1):
        item["number"] = i
        item["primary_los"] = los_id
        item["reading_id"] = reading_id
        item["area_id"] = area_id
        balance_item(item)
    return {
        "los_id": los_id,
        "los_letter": letter,
        "los_text": text,
        "reading_id": reading_id,
        "reading_name": reading_name,
        "area_id": area_id,
        "questions": questions,
    }


AMC_RID = "asset_manager_code_of_professional_conduct"
AMC_NAME = "Asset Manager Code of Professional Conduct"
AMC_AREA = "ethical_and_professional_standards"
PWM_RID = "an_overview_of_private_wealth_management"
PWM_NAME = "An Overview of Private Wealth Management"
PWM_AREA = "portfolio_construction"
ALTS_RID = "asset_allocation_to_alternative_investments"
ALTS_NAME = "Asset Allocation to Alternative Investments"
ALTS_AREA = "portfolio_construction"

MASTER = json.loads((RES / "los_master.json").read_text(encoding="utf-8"))
TEXT = {row["id"]: row["text"] for row in MASTER["los_flat"]}


def amc_a():
    los = f"{AMC_RID}.a"
    return group(los, "a", TEXT[los], AMC_RID, AMC_NAME, AMC_AREA, [
        q("r36_amc_los_a_q1", 1,
          "Compared with the CFA Institute Code of Ethics and Standards of Professional Conduct, the Asset Manager Code is most accurately described as:",
          {
              "A": "A voluntary firm-level code a manager may adopt even if not every employee is a CFA charterholder; individual members and candidates remain bound by the Standards whether or not the firm has adopted the Code.",
              "B": "A mandatory replacement for the individual Code and Standards at any shop that employs even one charterholder, so personal duties under the Standards lapse once the firm files its adoption notice with clients.",
              "C": "An annual individual attestation that each charterholder signs; the firm itself is never the adopting party, and clients look only to each employee's personal Standards file for process rules.",
          }, "A",
          {
              "A": "Correct. The Asset Manager Code is voluntary and binds the FIRM that adopts it. The Code and Standards continue to bind individual members and candidates regardless of the firm's adoption.",
              "B": "Incorrect. Adoption is not mandatory just because the firm employs charterholders, and it does not replace personal duties under the Standards.",
              "C": "Incorrect. The adopting party is the firm. Individual attestations are not how the Asset Manager Code is taken on.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS a — firm vs individual"),
        q("r36_amc_los_a_q2", 2,
          "A benefit that may accrue to a firm that adopts the Asset Manager Code is most likely:",
          {
              "A": "A CFA Institute endorsement of the firm's composite returns, which the firm may then quote in RFPs as evidence that its track record has been certified by the Institute.",
              "B": "A documented ethical framework clients, consultants, and regulators can inspect, plus one internal standard for allocation, valuation, trading, and performance instead of desk-by-desk custom.",
              "C": "Automatic relief from Standard III(A) and Standard V(A) for every employee, because firm-level adoption is treated as a substitute for the individual Standards those employees already follow.",
          }, "B",
          {
              "A": "Incorrect. Adoption is not a performance claim and not a CFA Institute endorsement of the firm or its returns.",
              "B": "Correct. Benefits include a public, inspectable framework and internal consistency across the processes the six principles cover. It is a culture and process signal, not a return certificate.",
              "C": "Incorrect. Individual Standards still bind members and candidates. Firm adoption does not waive III(A) or V(A).",
          }, los, AMC_RID, AMC_AREA, "AMC LOS a — benefits of adoption"),
        q("r36_amc_los_a_q3", 3,
          "A marketing deck for a firm that has adopted the Asset Manager Code states that “CFA Institute has approved our returns.” Relative to the purpose of the Code, this claim is most likely:",
          {
              "A": "Consistent, because adoption is the Institute's process for certifying composites once the firm names a compliance officer and files the Code with its regulator.",
              "B": "Consistent only for GIPS-verified firms; adoption of the Asset Manager Code is the Institute's endorsement route for shops that have not yet claimed GIPS compliance.",
              "C": "Inconsistent with the purpose of the Code. Adoption is not an endorsement, not a performance guarantee, and must not be marketed as Institute approval of the firm's results.",
          }, "C",
          {
              "A": "Incorrect. There is no Institute certification of returns attached to adopting the Code.",
              "B": "Incorrect. GIPS verification and Asset Manager Code adoption are separate. Neither is an Institute endorsement of returns.",
              "C": "Correct. The Code's purpose is a voluntary firm-level ethics framework. Marketing that implies CFA Institute certified the firm's returns violates that purpose (and the spirit of Standard VII(B)).",
          }, los, AMC_RID, AMC_AREA, "AMC LOS a — not an endorsement"),
        q("r36_amc_los_a_q4", 4,
          "A boutique has two CFA charterholders and eight other investment staff who are not members or candidates. The firm wants a single public ethics framework covering IPO allocation and private-asset valuation. The most appropriate statement is:",
          {
              "A": "The firm can adopt the Asset Manager Code even though not every employee is a charterholder; the two charterholders remain personally bound by the Standards in any event.",
              "B": "The firm cannot adopt the Code until every investment employee becomes a member or candidate, because the Code only attaches through individual membership.",
              "C": "The two charterholders' personal Standard III and V duties already cover firm-level IPO allocation and Level-3 valuation, so adopting a firm code would be redundant.",
          }, "A",
          {
              "A": "Correct. Adoption is a firm act, not a headcount of charterholders. Individual Standards still bind the two members; they do not by themselves write the firm's allocation and valuation manuals.",
              "B": "Incorrect. Non-charterholder staff do not block firm-level adoption. The Code is written for the manager as an organization.",
              "C": "Incorrect. Individual Standards do not fully specify firm processes such as IPO books and private-asset valuation policy — that is a reason the firm-level Code exists.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS a — who may adopt"),
        q("r36_amc_los_a_q5", 5,
          "Which vignette is most clearly in the Asset Manager Code's lane rather than only the individual Code and Standards?",
          {
              "A": "One research analyst's working papers omit a source, raising a Standard V(C) recordkeeping issue that is confined to that analyst's files and does not describe a firm procedure.",
              "B": "How THE FIRM allocates an oversubscribed IPO across accounts, values a private holding, or writes the compliance manual that desks are required to follow.",
              "C": "A candidate's weekend social-media post about exam content, which is a Standard VII(A) issue about the individual's conduct as a candidate, not a firm investment process.",
          }, "B",
          {
              "A": "Incorrect. A single analyst's research file is individual Standards territory (typically V(C)/I(C)), not the firm-level Code.",
              "B": "Correct. The discrimination is firm vs individual. Allocation, valuation policy, and the compliance manual are firm practices the Asset Manager Code is built to judge.",
              "C": "Incorrect. Candidate exam-discussion rules are Standard VII, not the Asset Manager Code.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS a — firm vs analyst vignette"),
        q("r36_amc_los_a_q6", 6,
          "The purpose of a public, firm-wide Asset Manager Code is most likely that:",
          {
              "A": "Clients can observe every trade, valuation mark, and allocation in real time, so a published code is mainly a marketing brochure rather than a substitute for surveillance they already perform.",
              "B": "Regulators in every jurisdiction forbid a manager to operate without this specific Code, so adoption is the legal license to manage third-party assets rather than a voluntary ethics framework.",
              "C": "Clients cannot watch every trade, valuation, or allocation; a public firm-wide code is one place they can look for how the firm says it will handle loyalty, process, trading, risk, performance, and disclosure.",
          }, "C",
          {
              "A": "Incorrect. Clients generally cannot watch every decision. That opacity is why a public firm-level code has a purpose.",
              "B": "Incorrect. The Code is voluntary. Some regulators require a written code of ethics; this Code is a ready-made way to meet that expectation, not a universal license.",
              "C": "Correct. The Code exists because asset-management clients cannot monitor every internal decision. A published firm-wide commitment gives them a single framework to compare with actual procedures.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS a — why a public firm code"),
    ])


def amc_b():
    los = f"{AMC_RID}.b"
    return group(los, "b", TEXT[los], AMC_RID, AMC_NAME, AMC_AREA, [
        q("r36_amc_los_b_q1", 1,
          "The six General Principles of Conduct of the Asset Manager Code, in the usual study order, are most likely:",
          {
              "A": "Loyalty to Clients; Investment Process and Actions; Trading; Risk Management, Compliance, and Support; Performance and Valuation; Disclosures.",
              "B": "Professionalism; Integrity of Capital Markets; Duties to Clients; Duties to Employers; Investment Analysis; Conflicts of Interest — the individual Standards restated for firms.",
              "C": "Best execution; GIPS composites; personal-account pre-clearance; independent directors; custody; and cyber insurance, which together replace the six principles.",
          }, "A",
          {
              "A": "Correct. Six principles, in this order: Loyalty to Clients; Investment Process and Actions; Trading; Risk Management, Compliance, and Support; Performance and Valuation; Disclosures.",
              "B": "Incorrect. Those are the individual Standards I–VI, not the Asset Manager Code's six General Principles.",
              "C": "Incorrect. Those are controls that may support the principles; they are not the six principles themselves.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS b — six principles in order"),
        q("r36_amc_los_b_q2", 2,
          "Loyalty to Clients under the Asset Manager Code most likely requires the firm to:",
          {
              "A": "Maximize the firm's proprietary-book profit whenever a client mandate is silent, because loyalty is owed first to the firm's shareholders and only residually to advisory clients.",
              "B": "Place client interests first, preserve confidentiality of client information, and refuse gifts or entertainment that reasonably could affect independence or compete with the client's interest.",
              "C": "Treat every client identically, including identical product mixes and share counts, because loyalty is defined as sameness of outcome across the book of accounts.",
          }, "B",
          {
              "A": "Incorrect. Loyalty is the firm's duty to the client relationship, not a residual after the proprietary book is served.",
              "B": "Correct. Principle 1 is client-first, confidentiality, and no consideration that could reasonably affect independence. It parallels — but does not replace — Standard III(A) for the individual.",
              "C": "Incorrect. Fair dealing is not identical treatment. Different mandates should receive different allocations.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS b — Loyalty to Clients"),
        q("r36_amc_los_b_q3", 3,
          "Under the Trading principle, fair allocation of an oversubscribed IPO is most accurately described as:",
          {
              "A": "Giving every account, including those that never buy IPOs, the same share count so that no client can claim to have been treated worse than another on a headcount basis.",
              "B": "Filling the firm's proprietary account and favored relationships first, then allocating residual shares pro rata to advisory clients who happen to still have cash.",
              "C": "Allocating trades and opportunities — including IPOs — fairly given each client's mandate, not by mechanical headcount and not by favoring the proprietary book or selected relationships.",
          }, "C",
          {
              "A": "Incorrect. Identical share counts across unlike accounts is often the violation. Fair dealing follows mandate, not headcount.",
              "B": "Incorrect. Personal or firm trades must not be placed ahead of client trades.",
              "C": "Correct. Trading requires best execution and fair allocation by mandate. Equal counts is not the same as fair allocation.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS b — Trading / fair allocation"),
        q("r36_amc_los_b_q4", 4,
          "Risk Management, Compliance, and Support is most likely satisfied when the firm:",
          {
              "A": "Maintains a compliance program with a named officer who has authority, identifies and manages portfolio and business risk, and provides the people and systems the principles actually require.",
              "B": "Prints “Chief Compliance Officer” on one trader's business card, with no budget, no halt authority, and no surveillance systems beyond the trading desk's own blotter.",
              "C": "Outsources all compliance judgment to the portfolio manager of each strategy, on the view that the people closest to the trades are best placed to police themselves.",
          }, "A",
          {
              "A": "Correct. Principle 4 is a real program: named officer with authority, risk identification, and resources. A title without budget is not a program.",
              "B": "Incorrect. A one-person title with no authority or systems fails Principle 4.",
              "C": "Incorrect. Self-policing by the trading desk is the opposite of an independent compliance function with halt authority.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS b — compliance program"),
        q("r36_amc_los_b_q5", 5,
          "Performance and Valuation under the Asset Manager Code most likely requires the firm to:",
          {
              "A": "Present only currently live accounts and replace hard-to-value holdings with cost until a sale, so that reported results stay smooth and comparable across periods.",
              "B": "Present performance that is fair, accurate, timely, and complete, and use fair-market valuations with a documented policy — especially for illiquid holdings — without cherry-picking accounts, periods, or composites.",
              "C": "Use the last-round private-company price indefinitely after a material down round, because a documented mark would be more subjective than leaving cost on the books.",
          }, "B",
          {
              "A": "Incorrect. Dropping terminated accounts and parking illiquid names at cost is cherry-picking / stale valuation, not complete performance.",
              "B": "Correct. Principle 5 is fair, accurate, timely, complete performance and documented fair-market valuation, particularly for Level-3 assets.",
              "C": "Incorrect. Stale last-round cost after a material event is a valuation failure, not conservatism.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS b — Performance and Valuation"),
        q("r36_amc_los_b_q6", 6,
          "The Disclosures principle is most likely breached when the firm:",
          {
              "A": "Sends clients a timely, accurate description of a new performance-fee tier, the conflict it creates, and the date the change takes effect, and keeps a file of what was sent.",
              "B": "Describes risks, fees, and process in the IPS and ADV, then separately emails material changes when the investment process or fee schedule actually changes.",
              "C": "Stays silent about a conflict because the underlying trade was allocated by a written policy the firm considers fair; silence about the conflict is still a disclosure failure.",
          }, "C",
          {
              "A": "Incorrect. That is the kind of timely, complete communication Principle 6 requires.",
              "B": "Incorrect. Ongoing disclosure of material changes is consistent with the principle.",
              "C": "Correct. Principle 6 requires timely, accurate, complete communication about conflicts, fees, risks, and material changes. A fair trade does not excuse silence about the conflict.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS b — Disclosures"),
    ])


def amc_c():
    los = f"{AMC_RID}.c"
    return group(los, "c", TEXT[los], AMC_RID, AMC_NAME, AMC_AREA, [
        q("r36_amc_los_c_q1", 1,
          "A firm gives every client account 400 shares of an oversubscribed IPO, including an account whose mandate never buys IPOs. This practice is most likely:",
          {
              "A": "Inconsistent with the Code. Fair allocation follows objectives, constraints, and mandate; equal share counts that pad non-IPO accounts are not fair dealing under Trading.",
              "B": "Consistent with the Code, because identical share counts prove that no account was favored and Loyalty to Clients is defined as sameness of outcome.",
              "C": "Outside the Code's scope, because IPO allocation is solely a Standard III(B) individual-member issue and cannot be judged as a firm practice.",
          }, "A",
          {
              "A": "Correct. Equal counts is not fair allocation. Accounts that do not participate in IPOs should not be padded; suitable accounts should not be shorted to make the headcount even.",
              "B": "Incorrect. Sameness of share count across unlike mandates is often the breach, not the cure.",
              "C": "Incorrect. This is a classic firm-practice item under the Asset Manager Code (Trading / fair allocation), even though an individual could also breach III(B).",
          }, los, AMC_RID, AMC_AREA, "AMC LOS c — equal-share IPO"),
        q("r36_amc_los_c_q2", 2,
          "A year after a material down round, a private holding still sits at last-round cost; there is no documented valuation policy. This practice is most likely:",
          {
              "A": "Consistent with Performance and Valuation, because cost is more objective than a mark and leaving last-round cost avoids disputable fair-value estimates.",
              "B": "Inconsistent with Performance and Valuation. Illiquid holdings need a documented fair-value policy with timely review after material events, not stale cost.",
              "C": "A Loyalty issue only, because any stale mark is first a confidentiality failure toward the issuer rather than a performance-presentation problem.",
          }, "B",
          {
              "A": "Incorrect. Cost after a material event is not conservatism; it is an incomplete, stale valuation.",
              "B": "Correct. Map the action to Principle 5. A private holding at last-round cost a year after a down round, with no policy, is inconsistent with the Code.",
              "C": "Incorrect. The broken duty is valuation / performance presentation, not issuer confidentiality.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS c — stale private mark"),
        q("r36_amc_los_c_q3", 3,
          "The person titled compliance officer reports into the trading desk and cannot halt a trade. Relative to the Code this arrangement is most likely:",
          {
              "A": "Consistent, provided the officer's title appears in the firm's ADV and marketing, because Principle 4 is satisfied by naming someone rather than by halt authority.",
              "B": "Consistent if the trading desk documents each override, because a reporting line into trading improves speed and therefore best execution under Principle 3.",
              "C": "Inconsistent with Risk Management, Compliance, and Support. A compliance program requires a named officer who has authority, not a title that cannot stop a trade.",
          }, "C",
          {
              "A": "Incorrect. A title without authority is not a program.",
              "B": "Incorrect. Reporting into the desk that must be policed undermines independence; speed is not a substitute for halt authority.",
              "C": "Correct. Principle 4 fails when compliance cannot restrict trading or escalate. Judge the procedure as described, not the org-chart label.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS c — CO without authority"),
        q("r36_amc_los_c_q4", 4,
          "Which firm practice is most likely consistent with the Asset Manager Code?",
          {
              "A": "A written IPO/new-issue allocation policy applied by client mandate, with records retained, rather than a same-share-count rule across unlike accounts.",
              "B": "A composite that drops terminated accounts and backfills a model return for the first six months of a new strategy so that the marketed track record stays continuous.",
              "C": "Employee trades in names on the restricted list filling before the client order in the same security, provided the employee ticket is smaller than the client's.",
          }, "A",
          {
              "A": "Correct. Written allocation by mandate with records is the consistent pattern. Equal counts, dropped accounts, and employee priority are classic inconsistencies.",
              "B": "Incorrect. Dropping terminated accounts and model backfill is incomplete / cherry-picked performance.",
              "C": "Incorrect. Personal trades must not be placed ahead of client trades, regardless of ticket size.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS c — consistent allocation policy"),
        q("r36_amc_los_c_q5", 5,
          "The firm's proprietary account is filled in a name before the client order in that name is complete. This practice is most likely:",
          {
              "A": "Consistent with Trading so long as execution quality on the client remainder meets the firm's best-execution policy after the proprietary fill.",
              "B": "Inconsistent with Trading (and Loyalty). The firm must not place personal or proprietary trades ahead of client trades in the same name.",
              "C": "Outside the Code, because proprietary-book timing is a capital-structure choice for the management company and is not a client-facing procedure.",
          }, "B",
          {
              "A": "Incorrect. Best execution on the leftover does not cure front-running the client.",
              "B": "Correct. Trading forbids placing firm or personal trades ahead of client trades. The practice is inconsistent with the Code.",
              "C": "Incorrect. Proprietary priority in the same name is exactly a client-facing trading procedure the Code covers.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS c — proprietary priority"),
        q("r36_amc_los_c_q6", 6,
          "A marketed composite omits accounts that terminated during the period. Relative to the Code this presentation is most likely:",
          {
              "A": "Consistent with Performance and Valuation if the remaining accounts were valued at fair market and the composite still has more than five names.",
              "B": "Consistent because terminated accounts no longer pay fees, so including them would mix non-client results into a client composite.",
              "C": "Inconsistent with Performance and Valuation. Performance must be fair, accurate, and complete; dropping terminated accounts is a classic cherry-pick.",
          }, "C",
          {
              "A": "Incorrect. Fair marks on the survivors do not make an incomplete composite complete.",
              "B": "Incorrect. Terminated accounts belong in the history of the composite that actually included them.",
              "C": "Correct. Principle 5 requires complete presentation. Omitting terminated accounts is the inconsistent pattern.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS c — dropped terminated accounts"),
    ])


def amc_d():
    los = f"{AMC_RID}.d"
    return group(los, "d", TEXT[los], AMC_RID, AMC_NAME, AMC_AREA, [
        q("r36_amc_los_d_q1", 1,
          "After an equal-share IPO allocation, the most appropriate recommended procedure is:",
          {
              "A": "A firm-level control: put the IPO into the allocation engine by mandate, log exceptions, and require compliance sign-off before the allocation is final — not a lecture to one trader to “be fair.”",
              "B": "Remind the trader who keyed the tickets to use professional judgment next time, and leave the written policy unchanged because the Code is about individual character rather than systems.",
              "C": "Move the IPO into the proprietary book first going forward, then offer leftover shares to clients who complain, which avoids repeating an even-split across the advisory book.",
          }, "A",
          {
              "A": "Correct. Prevention is institutional. Recommend a concrete firm procedure (policy, system, record, sign-off), not a pep talk.",
              "B": "Incorrect. “Remind the analyst to be fair” is not a recommended procedure under this LOS.",
              "C": "Incorrect. Proprietary priority would add a Trading breach rather than prevent one.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS d — firm procedure not lecture"),
        q("r36_amc_los_d_q2", 2,
          "Which recommendation best prevents Principle 4 failures of the “title-only compliance officer” type?",
          {
              "A": "Add a second honorary compliance title on the CIO's card so that marketing can show two names without changing reporting lines or halt rights.",
              "B": "Name a compliance officer with authority to restrict trading and escalate to the governing body, and resource surveillance so that officer can actually halt a trade.",
              "C": "Keep compliance reporting into the trading desk for speed, but require the officer to initial the blotter at the close of each session after fills are complete.",
          }, "B",
          {
              "A": "Incorrect. Extra titles without authority do not create a program.",
              "B": "Correct. Minimum prevention: a named officer with real authority and the systems to use it. That is the firm-level control Principle 4 requires.",
              "C": "Incorrect. After-the-fact initials from a desk-reporting officer do not restrict trading in time.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS d — officer with authority"),
        q("r36_amc_los_d_q3", 3,
          "A private equity line still sits at last-round cost after a down round. The procedure most likely to prevent a repeat valuation breach is:",
          {
              "A": "Instruct the deal team to “use judgment” on marks, without a written policy, so that valuation remains flexible when information is incomplete.",
              "B": "Leave cost on the books until exit, and disclose in a footnote that private holdings are carried at cost, which the firm treats as a complete fair-value policy.",
              "C": "Adopt a fair-value policy with independent input and a stated review calendar for Level-3 / illiquid assets, then apply it when a material event occurs.",
          }, "C",
          {
              "A": "Incorrect. Unwritten judgment is not a preventive control.",
              "B": "Incorrect. A cost footnote does not turn stale cost into fair value after a material event.",
              "C": "Correct. Recommend a documented fair-value policy, independent input, and a review calendar — a firm procedure, not a hope that the deal team remembers.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS d — valuation policy"),
        q("r36_amc_los_d_q4", 4,
          "The desk has a written allocation policy that nobody follows. The most appropriate recommendation is:",
          {
              "A": "Enforcement authority and testing: sample IPO books and allocation logs, give compliance halt/escalation rights, and fix the procedure when a test fails — not another copy of the same PDF.",
              "B": "Rewrite the policy in a longer font and recirculate it annually, because a more complete document is the control even if desks ignore it.",
              "C": "Withdraw the written policy so that informal custom, if it happens to be fair this quarter, cannot be accused of diverging from a paper standard.",
          }, "A",
          {
              "A": "Correct. If a policy is ignored, the recommendation is authority and testing, not another memo. A written policy that is not followed is already inconsistent with the Code.",
              "B": "Incorrect. Lengthening the PDF does not create enforcement.",
              "C": "Incorrect. Deleting the policy removes the audit trail; it does not install a control.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS d — enforce ignored policy"),
        q("r36_amc_los_d_q5", 5,
          "Which set of firm procedures is most complete as a prevention package for Asset Manager Code breaches?",
          {
              "A": "Annual ethics training for analysts only, with no named officer, no allocation engine, and no valuation policy, on the view that trained individuals will not need firm systems.",
              "B": "Formal adoption by the governing body; a named officer with authority; written policies covering loyalty, gifts, suitability, fair dealing, best execution, IPO allocation, personal trading, valuation, and performance; timely conflict/fee/risk disclosure with a file; resources and periodic testing.",
              "C": "A one-page mission statement that the firm “puts clients first,” posted in reception, without records, surveillance, or a review calendar for illiquid marks.",
          }, "B",
          {
              "A": "Incorrect. Individual training is necessary but never sufficient — the Code is a firm code.",
              "B": "Correct. Prevention is institutional: adopt, empower, write the policies the six principles require, disclose, resource, and test.",
              "C": "Incorrect. A slogan without records or surveillance is not a recommended procedure.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS d — minimum prevention set"),
        q("r36_amc_los_d_q6", 6,
          "A recommended disclosure control that helps prevent Principle 6 breaches is most likely:",
          {
              "A": "Limit disclosure to the ADV brochure at onboarding, with no follow-up when fees or the investment process change, because onboarding documents are deemed continuing.",
              "B": "Disclose conflicts only if the related trade was later found to be unfair; fair trades need not be accompanied by conflict disclosure under the Code.",
              "C": "Disclose conflicts, fees, risks, and material process changes to clients in a timely way, and keep a file of what was disclosed and when, so a client or regulator can reconstruct the communication.",
          }, "C",
          {
              "A": "Incorrect. Material changes after onboarding still need timely communication.",
              "B": "Incorrect. Fairness of the trade does not waive the conflict disclosure.",
              "C": "Correct. Timely disclosure plus a file is a concrete firm procedure. Silence about a conflict is a disclosure failure even when the trade was otherwise fair.",
          }, los, AMC_RID, AMC_AREA, "AMC LOS d — disclosure file"),
    ])


def pwm_a():
    los = f"{PWM_RID}.a"
    return group(los, "a", TEXT[los], PWM_RID, PWM_NAME, PWM_AREA, [
        q("r9_pwm_wealth_los_a_q1", 1,
          "How individual wealth is created most likely matters because:",
          {
              "A": "The source — entrepreneurship, employment/executive awards, or inheritance — shapes concentration, liquidity, and the planning agenda more than the dollar amount alone.",
              "B": "Only the current market value of financial capital matters; source of wealth is a biographical detail that does not change IPS constraints or estate planning.",
              "C": "Inherited wealth and entrepreneurial wealth produce identical balance sheets, so advisers can skip source-of-wealth questions once net worth is known.",
          }, "A",
          {
              "A": "Correct. Entrepreneurship tends to be concentrated and illiquid; executive wealth often means employer stock; inheritance brings multi-generational governance and estate issues.",
              "B": "Incorrect. Source drives concentration, liquidity, and planning even when two clients have the same net worth.",
              "C": "Incorrect. The two sources typically imply very different liquidity and governance needs.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS a — sources of wealth"),
        q("r9_pwm_wealth_los_a_q2", 2,
          "Wealth from sale of a founder’s operating company is most likely to present as:",
          {
              "A": "A ladder of liquid public securities with no single-name risk, so diversification and liquidity events are rarely the planning priority.",
              "B": "Concentrated, often illiquid exposure tied to one business, so diversification, liquidity events, and succession/estate planning dominate the agenda.",
              "C": "Primarily a tax-deferred defined-benefit pension, so the planning problem is almost entirely required-return arithmetic on a spend-down portfolio.",
          }, "B",
          {
              "A": "Incorrect. Founder wealth is typically the opposite of a diversified public book.",
              "B": "Correct. Entrepreneurial wealth is concentrated and illiquid; that source, not just the headline net worth, sets the work.",
              "C": "Incorrect. A DB pension is employment-style, not sale-of-business wealth.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS a — entrepreneurial wealth"),
        q("r9_pwm_wealth_los_a_q3", 3,
          "Private-client segments, moving toward more customized advice, are most likely ordered:",
          {
              "A": "UHNW, then HNW, then mass affluent, then mass market — customization falls as wealth rises because large pools use only standardized products.",
              "B": "Mass affluent, UHNW, mass market, HNW — segments are regional marketing labels, not a ladder of advice intensity.",
              "C": "Mass market → mass affluent → high-net-worth (HNW) → ultra-high-net-worth (UHNW), with advice becoming more bespoke (family office, philanthropy, direct deals) at the top.",
          }, "C",
          {
              "A": "Incorrect. Customization rises with wealth; it does not fall.",
              "B": "Incorrect. The curriculum uses a wealth ladder, not an unordered set of labels.",
              "C": "Correct. Standardized products at the base; family-office, philanthropy, and complex estate/direct-deal work at the UHNW apex.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS a — segment ladder"),
        q("r9_pwm_wealth_los_a_q4", 4,
          "The global distribution of individual wealth is most accurately described as:",
          {
              "A": "Highly concentrated — a steep pyramid with a broad mass-market base and a narrow HNW/UHNW apex holding a disproportionate share — and the pattern differs across regions as emerging-market wealth is created.",
              "B": "Roughly uniform across households in each region, which is why private-wealth advice is standardized globally once a minimum account size is met.",
              "C": "Concentrated only inside a few developed markets; emerging-market wealth creation has flattened the global pyramid so that UHNW share is no longer a planning fact.",
          }, "A",
          {
              "A": "Correct. Global wealth is a steep pyramid, regionally uneven, and still shifting as new wealth is created.",
              "B": "Incorrect. The distribution is highly unequal, which is why segment and source matter.",
              "C": "Incorrect. Emerging-market wealth changes where the apex sits; it does not make the pyramid disappear.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS a — global distribution"),
        q("r9_pwm_wealth_los_a_q5", 5,
          "The private wealth management process is most likely sequenced as:",
          {
              "A": "Implementation first (buy the portfolio), then discovery, because goals can be reverse-engineered from holdings more cheaply than from a structured interview.",
              "B": "Discovery (goals, circumstances, risk, constraints) → IPS → implementation (allocation, tax-aware construction, vehicles) → monitoring and review as life and markets change.",
              "C": "IPS publication, then discovery only if the client objects, because the document is standardized and discovery is optional color.",
          }, "B",
          {
              "A": "Incorrect. Discovery precedes the IPS and implementation; you do not buy first and interview later.",
              "B": "Correct. Repeatable cycle: discovery → IPS → implementation → monitoring. Much of the value is planning, coaching, and tax/estate coordination, not only security selection.",
              "C": "Incorrect. The IPS is the output of discovery, not a substitute for it.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS a — PWM process"),
        q("r9_pwm_wealth_los_a_q6", 6,
          "Senior-executive wealth from salary, bonus, and equity awards most likely raises which planning issue first?",
          {
              "A": "A perpetual, tax-exempt institutional horizon with committee governance, because executive wealth is managed like an endowment once RSUs vest.",
              "B": "Multi-generational family-office governance as the default, even when the executive has no operating company and no heirs, because all HNW clients share that agenda.",
              "C": "Concentration in employer stock and options, which creates single-name and tax-timing problems distinct from a founder’s illiquid private operating company.",
          }, "C",
          {
              "A": "Incorrect. Executives are taxable private clients with finite horizons, not endowments.",
              "B": "Incorrect. Family-office governance is an UHNW/inheritance pattern, not automatic for every executive.",
              "C": "Correct. Employment/executive wealth often means concentrated employer equity and option tax-timing — a different source problem than entrepreneurial illiquidity or inherited stewardship.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS a — executive wealth"),
    ])


def pwm_c():
    los = f"{PWM_RID}.c"
    return group(los, "c", TEXT[los], PWM_RID, PWM_NAME, PWM_AREA, [
        q("r9_pwm_hccons_los_c_q1", 1,
          "Two 40-year-olds have similar financial assets. One is a tenured civil servant; the other is a commission salesperson in a cyclical industry. Who should hold more equity in the financial portfolio, and why?",
          {
              "A": "The civil servant. Bond-like human capital already behaves like a large bond holding, so the financial portfolio can take more equity risk to balance total-wealth risk.",
              "B": "The salesperson. Equity-like human capital should be matched with more equity in the financial portfolio so that labor income and investments rise and fall together.",
              "C": "Neither should differ. Human-capital risk character does not affect the financial-portfolio mix once age and financial-asset size are the same.",
          }, "A",
          {
              "A": "Correct. Stable, secure earnings are bond-like HC, so the financial book can hold more equity. Cyclical/commission income is equity-like HC and argues for more bonds in the financial portfolio.",
              "B": "Incorrect. Matching equity-like HC with more portfolio equity concentrates total-wealth risk rather than balancing it.",
              "C": "Incorrect. The risk character of human capital is exactly what this LOS uses to justify the portfolio tilt.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS c — bond-like vs equity-like HC"),
        q("r9_pwm_hccons_los_c_q2", 2,
          "A founder’s human capital is equity-like (variable, firm-specific). Relative to a tenured professor of the same age and financial wealth, the founder’s financial portfolio should most likely hold:",
          {
              "A": "More public equity, because entrepreneurial HC is a substitute for a diversified stock allocation and should be levered in the liquid book.",
              "B": "More bonds (or less equity beta) in the financial portfolio, because total-wealth risk already includes concentrated, equity-like labor and business income.",
              "C": "The same mix, because IPS risk objectives are set from age alone once financial capital is equal.",
          }, "B",
          {
              "A": "Incorrect. Levering the liquid book in the same risk as the business concentrates total wealth.",
              "B": "Correct. Equity-like HC → more bonds in financial capital so that total-wealth risk is not all equity-like.",
              "C": "Incorrect. Age and FC size are not a complete risk story when HC risk character differs.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS c — founder HC tilt"),
        q("r9_pwm_hccons_los_c_q3", 3,
          "Target total-wealth equity is 30%. Human capital is bond-like (contributes no equity). Early career: HC 700,000, FC 300,000. Near retirement: HC 300,000, FC 700,000. Financial-portfolio equity weights are most likely:",
          {
              "A": "30% then 30%. The financial portfolio always copies the total-wealth target, so human capital can be ignored in the weight calculation.",
              "B": "43% then 100%. The shrinking human-capital stock is treated as equity, so the financial book must start conservative and then lever up.",
              "C": "100% then about 43%. Early on, FC must supply all 300,000 of target equity; later the same 300,000 is 300,000/700,000 of a larger FC book — the glide path from holding total-wealth risk constant.",
          }, "C",
          {
              "A": "Incorrect. If HC is bond-like, the financial book must supply the equity HC does not, so the FC weight is not the total-wealth weight.",
              "B": "Incorrect. That path is backwards. Young, bond-like HC implies a high FC equity weight that declines as HC is spent.",
              "C": "Correct. w(equity in FC) = (target equity% × total wealth − equity from HC) / FC. With bond-like HC that is 100% then ~43%. That is the theoretical basis for a glide path.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS c — total-wealth glide path"),
        q("r9_pwm_hccons_los_c_q4", 4,
          "Human-capital risks the investment portfolio cannot hedge, and their usual hedges, are most likely:",
          {
              "A": "Premature death → life insurance sized to human capital at risk net of existing assets; longevity → annuities; earnings/health risk → disability and health insurance.",
              "B": "Premature death → a higher equity allocation so the estate grows faster; longevity → more concentrated stock so the surplus can fund a long life.",
              "C": "Premature death → an annuity purchased at age 30; longevity → term life insurance that expires at retirement, which is when longevity risk begins.",
          }, "A",
          {
              "A": "Correct. Portfolio beta does not replace the earner. Pair death with life insurance (HC net of assets), longevity with annuities, and earnings/health risk with disability/health cover.",
              "B": "Incorrect. More equity does not hedge death or longevity; it adds market risk on top of HC risk.",
              "C": "Incorrect. The hedges are reversed, and term life expiring at retirement is when the death-of-HC problem is smaller, not when longevity risk starts.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS c — HC hedges"),
        q("r9_pwm_hccons_los_c_q5", 5,
          "Ability to take risk is high (long horizon, ample wealth vs needs, stable HC) but the client’s stated willingness is low. The adviser should most likely:",
          {
              "A": "Follow ability and ignore willingness, because constraints in the IPS are objective and attitudes are not part of the risk objective.",
              "B": "Document both ability and willingness and generally follow the LOWER of the two while educating the client, rather than forcing the higher risk budget.",
              "C": "Follow willingness only when it is higher than ability, and follow ability whenever willingness is lower, so the portfolio always takes more risk than the client prefers.",
          }, "B",
          {
              "A": "Incorrect. Willingness is part of the risk objective for individuals; you do not discard it.",
              "B": "Correct. Where ability and willingness conflict, document both and typically implement the lower while coaching. That is how individual constraints attach to HC/FC.",
              "C": "Incorrect. That rule would systematically override low willingness — the opposite of the usual resolution.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS c — ability vs willingness"),
        q("r9_pwm_hccons_los_c_q6", 6,
          "Human capital is about 1,456,000. Survivors already have 300,000 of earmarked liquid assets and a 200,000 group life policy. Additional life-insurance need is most likely:",
          {
              "A": "1,456,000, because existing assets and group cover should not be netted when the goal is to replace human capital in full.",
              "B": "200,000, because only the group policy is relevant and financial assets are already in the investment portfolio rather than in the insurance need.",
              "C": "About 956,000 (1,456,000 − 300,000 − 200,000). Size cover to human capital at risk net of existing assets and coverage; the need declines as HC declines with age.",
          }, "C",
          {
              "A": "Incorrect. Existing resources that would support survivors reduce the additional cover required.",
              "B": "Incorrect. Both earmarked assets and existing cover are subtracted in the human-capital approach.",
              "C": "Correct. Additional need ≈ HC − existing assets/coverage. As HC falls through the life cycle, so does the insurance constraint.",
          }, los, PWM_RID, PWM_AREA, "PWM LOS c — insurance need"),
    ])


def alts_b():
    los = f"{ALTS_RID}.b"
    return group(los, "b", TEXT[los], ALTS_RID, ALTS_NAME, ALTS_AREA, [
        q("r8_altaa_mitigator_los_b_q1", 1,
          "High-quality government bonds are the classic equity-risk mitigator most likely because they:",
          {
              "A": "Tend to rally in an equity sell-off (flight-to-quality, often negative crisis correlation), stay liquid when liquidity is scarce, and gain from duration as policy rates are cut.",
              "B": "Always earn a higher expected return than equities in expansions, so they mitigate by outgrowing the equity book rather than by correlation.",
              "C": "Are as illiquid as private credit in a crisis, which forces the investor to hold through the drawdown and therefore “mitigates” by preventing a sale.",
          }, "A",
          {
              "A": "Correct. Bonds mitigate via crisis correlation, crisis liquidity, and duration. That hedge is dependable relative to most alternatives — and it is the benchmark this LOS compares against.",
              "B": "Incorrect. The bond hedge is not “higher return than equities.” Expected return is the cost of the hedge.",
              "C": "Incorrect. Bond liquidity in a crisis is a reason they work as mitigators, not a lock-up.",
          }, los, ALTS_RID, ALTS_AREA, "Alts LOS b — why bonds mitigate"),
        q("r8_altaa_mitigator_los_b_q2", 2,
          "The main cost of using high-quality bonds as the equity-risk mitigator, especially in a low-yield setting, is most likely:",
          {
              "A": "Bonds become more liquid than usual, which unfortunately increases tracking error versus a private-asset benchmark the IPS does not use.",
              "B": "Low expected return, and at low yields both that expected return and the size of the negative-correlation cushion shrink because there is less room for yields to fall.",
              "C": "Bonds reliably raise equity beta in a crash, so they must be paired with leverage to restore the hedge that flight-to-quality would otherwise provide.",
          }, "B",
          {
              "A": "Incorrect. Crisis liquidity is a benefit of bonds as mitigators, not a cost versus a private benchmark.",
              "B": "Correct. Bonds are reliable and liquid but low-returning; the cushion weakens when yields have little room to fall. That is the opening for some alternatives.",
              "C": "Incorrect. High-quality bonds tend to lower, not raise, equity beta in a crash.",
          }, los, ALTS_RID, ALTS_AREA, "Alts LOS b — cost of the bond hedge"),
        q("r8_altaa_mitigator_los_b_q3", 3,
          "Relative to high-quality bonds, managed futures / trend-following as an equity-risk mitigator is most likely to:",
          {
              "A": "Match bonds on crisis liquidity and reliability, while also matching bond expected returns, so the two mitigators are interchangeable in an IPS.",
              "B": "Increase equity beta in a prolonged drawdown, because trend strategies are long-biased equity funds with a different name.",
              "C": "Offer higher expected return via “crisis alpha” (profiting as it rides a prolonged equity decline) but sacrifice liquidity and some reliability of the hedge versus bonds.",
          }, "C",
          {
              "A": "Incorrect. Trend is less liquid and less certain than bonds; that is the trade-off.",
              "B": "Incorrect. Trend/managed futures is the usual crisis-alpha example; long-biased equity hedge funds are the trap that still carry equity beta.",
              "C": "Correct. Select alternatives (trend, macro, market-neutral) can mitigate with a higher expected return than bonds, at the cost of liquidity and hedge certainty.",
          }, los, ALTS_RID, ALTS_AREA, "Alts LOS b — trend vs bonds"),
        q("r8_altaa_mitigator_los_b_q4", 4,
          "A long-biased equity hedge fund, compared with bonds or managed futures as a mitigator of a long equity position, is most likely:",
          {
              "A": "Not a true mitigator. It retains meaningful equity beta, so it tends to fall with the market and fails the test that a mitigator must work when equities drop.",
              "B": "The most reliable crisis hedge, because the hedge-fund label guarantees negative correlation with listed equity in a drawdown.",
              "C": "Equivalent to high-quality bonds on liquidity, because both can be sold T+1 without gates when a pension needs cash mid-crisis.",
          }, "A",
          {
              "A": "Correct. Long-biased / credit-oriented strategies often correlate WITH equities in a crash. The label “hedge fund” does not make it a mitigator.",
              "B": "Incorrect. The asset-class label is the trap this comparison is meant to catch.",
              "C": "Incorrect. Many hedge funds have gates/lock-ups; they are not bond-like crisis liquidity.",
          }, los, ALTS_RID, ALTS_AREA, "Alts LOS b — long-biased is not a mitigator"),
        q("r8_altaa_mitigator_los_b_q5", 5,
          "Rank (i) 10-year government bonds, (ii) a managed-futures fund, and (iii) a long-biased equity hedge fund as equity-risk mitigators:",
          {
              "A": "(iii) first, then (ii), then (i). Long-biased funds mitigate most because they are already in the alternatives bucket the IPS treats as a diversifier.",
              "B": "(i) and (ii) are genuine mitigators — bonds most reliable and liquid, managed futures higher-returning but less certain — while (iii) is not a mitigator.",
              "C": "All three rank equally if each has the same trailing three-year volatility, because mitigator quality is a volatility ranking rather than a crisis-correlation ranking.",
          }, "B",
          {
              "A": "Incorrect. Bucket labels do not rank mitigators. Long-biased equity is the non-mitigator.",
              "B": "Correct. Bonds = reliable, liquid, low-return. Trend = crisis alpha, higher return, less certain/less liquid. Long-biased = equity beta, not a mitigator.",
              "C": "Incorrect. Average volatility is not the test; behavior WHEN equities fall is.",
          }, los, ALTS_RID, ALTS_AREA, "Alts LOS b — rank three candidates"),
        q("r8_altaa_mitigator_los_b_q6", 6,
          "For an alternative to beat high-quality bonds as a mitigator of a long equity position, it most likely must:",
          {
              "A": "Carry a lock-up long enough that the investor cannot sell in a crash, which by itself is treated as risk mitigation in this comparison.",
              "B": "Be grouped under “alternatives” in a traditional opportunity set, because the asset-class label is sufficient evidence of low equity correlation.",
              "C": "Be reliably uncorrelated or negatively correlated when equities fall, and liquid enough for the hedge to matter — otherwise it is a return overlay, not a mitigator.",
          }, "C",
          {
              "A": "Incorrect. Illiquidity that traps the investor mid-crisis is a cost, not the definition of a mitigator. Illiquid names often cannot be sold to raise cash.",
              "B": "Incorrect. Traditional asset-class grouping is the next LOS; it is not proof of mitigation here.",
              "C": "Correct. Two tests: works when equities drop, and can actually be used (liquidity). Trend often meets both better than long-biased funds; bonds remain the more reliable, more liquid, lower-return answer.",
          }, los, ALTS_RID, ALTS_AREA, "Alts LOS b — tests of a true mitigator"),
    ])


def write_bundle(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def insert_groups(path: Path, new_groups: list[dict]) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    by_letter = {g["los_letter"]: g for g in data["drills"]}
    for g in new_groups:
        if g["los_letter"] in by_letter:
            raise SystemExit(f"{path.name} already has letter {g['los_letter']}")
        by_letter[g["los_letter"]] = g
    data["drills"] = [by_letter[k] for k in sorted(by_letter)]
    n = sum(len(g["questions"]) for g in data["drills"])
    data["reading"]["los_count"] = len(data["drills"])
    data["reading"]["question_count"] = n
    write_bundle(path, data)
    return sum(len(g["questions"]) for g in new_groups)


def assert_no_length_cue(groups):
    bad = []
    for g in groups:
        for item in g["questions"]:
            opts, correct = item["options"], item["correct"]
            if unique_longest(opts, correct) or unique_shortest(opts, correct):
                bad.append((item["id"], {k: len(opts[k]) for k in KEYS}, correct))
    if bad:
        raise SystemExit(f"length cue remains: {bad}")


def assert_rotation(groups):
    dist = {k: 0 for k in KEYS}
    for g in groups:
        for item in g["questions"]:
            dist[item["correct"]] += 1
    if not (dist["A"] == dist["B"] == dist["C"]):
        raise SystemExit(f"ABC not balanced in new items: {dist}")


def length_report(groups):
    rows = []
    for g in groups:
        for item in g["questions"]:
            lens = {k: len(item["options"][k]) for k in KEYS}
            rows.append((item["id"], item["correct"], lens))
            print(f"  {item['id']} key={item['correct']} {lens}")
    return rows


def main() -> None:
    amc_groups = [amc_a(), amc_b(), amc_c(), amc_d()]
    pwm_groups = [pwm_a(), pwm_c()]
    alts_groups = [alts_b()]
    new_groups = amc_groups + pwm_groups + alts_groups
    assert_no_length_cue(new_groups)
    assert_rotation(new_groups)
    print("New item lengths:")
    length_report(new_groups)

    amc_n = sum(len(g["questions"]) for g in amc_groups)
    write_bundle(RES / "los_drills_r36.json", {
        "schema_version": 2,
        "generated_by": "author_gap_drills.py",
        "curriculum_source": "CFA Program 2027 Level III, Asset Manager Code of Professional Conduct (original study items)",
        "content_type": "mc_only",
        "reading": {
            "reading_id": AMC_RID,
            "reading_name": AMC_NAME,
            "area_id": AMC_AREA,
            "los_count": 4,
            "question_count": amc_n,
        },
        "drills": amc_groups,
    })

    pwm_added = insert_groups(RES / "los_drills_r9.json", pwm_groups)
    alts_added = insert_groups(RES / "los_drills_r8.json", alts_groups)

    index_path = RES / "los_drills_index.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    if not any(b.get("reading_number") == 36 for b in index["bundles"]):
        # Keep ethics modules together: insert after r35.
        bundles = index["bundles"]
        insert_at = next(
            (i + 1 for i, b in enumerate(bundles) if b.get("reading_number") == 35),
            len(bundles),
        )
        bundles.insert(insert_at, {
            "reading_id": AMC_RID,
            "filename": "los_drills_r36",
            "reading_number": 36,
        })
        index_path.write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"AMC {amc_n}  PWM +{pwm_added}  alts +{alts_added}  total +{amc_n + pwm_added + alts_added}")


if __name__ == "__main__":
    main()
