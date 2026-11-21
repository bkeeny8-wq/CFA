#!/usr/bin/env python3
"""Read the Meldrum question-bank snapshots and say what they actually support.

    python3 scripts/analyze_mm.py [--snapshot YYYY-MM-DD]

Three things this computes that the dashboard does not:

1. A WILSON interval on every module score. The dashboard prints "100%" next
   to a module where one question was answered. The normal approximation is
   useless there (it gives a zero-width interval at p=0 or p=1); Wilson is not,
   so it is what tells you that a 100% on n=1 and a 77% on n=13 are not
   comparable claims.

2. MARKS AT RISK — exam weight x (1 - score). A 10-point gap in the Pathway
   costs more than twice a 10-point gap in Performance Measurement, because
   the Pathway is 32.5% of the exam and PM is 7.5%. Relative-to-peer deltas
   hide that completely; they are a ranking, not a quantity.

3. Whether the plan's own desk_need ranking agrees. The ranking was produced
   by rating readings on their content before any of these questions were
   answered, so this is an out-of-sample test of it.

A note on the peer column: it is the bank's lifetime cohort average, which
mostly reflects candidates answering AFTER studying a module. Reading an
early-and-cold score against it is a pessimistic comparison by construction.
"""

import argparse
import json
import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCORES = ROOT / "scripts" / "mm_scores.json"
RANKING = ROOT / "scripts" / "reading_ranking.json"
SCHEDULE = ROOT / "CFAL3" / "Resources" / "study_schedule.json"
MM_REVIEW = ROOT / "CFAL3" / "Resources" / "mm_review.json"

BOOK = {1: "Asset Allocation", 2: "Portfolio Construction",
        3: "Performance Measurement", 4: "Derivatives & Risk",
        5: "Ethics", 6: "PM Pathway"}

# Questions per module, read off the dashboard badges. Used only to split a
# book's exam weight across its modules; each book is renormalised to its own
# stated total, so a misread badge shifts one module's share slightly and
# cannot distort the book-level numbers at all.
BANK_Q = {
    1: {1: 109, 2: 92, 3: 56, 4: 62, 5: 32},
    2: {1: 24, 2: 52, 3: 71, 4: 51, 5: 89, 6: 30},
    3: {1: 78, 2: 34, 3: 44},
    4: {1: 45, 2: 60, 3: 70},
    5: {1: 57, 2: 13, 3: 8, 4: 19, 5: 9, 6: 12, 7: 7, 8: 16, 9: 25, 10: 2},
    6: {1: 64, 2: 58, 3: 54, 4: 65, 5: 44, 6: 70, 7: 76},
}


def wilson(k, n, z=1.96):
    """Wilson score interval — behaves at n=1 and at p=0 or 1, unlike the
    normal approximation, which collapses to a point there and would report
    a 1-of-1 module as 100% +/- 0."""
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    d = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / d
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, centre - half), min(1.0, centre + half))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--snapshot", default=None,
                    help="date of the snapshot to analyse (default: latest)")
    args = ap.parse_args()

    data = json.loads(SCORES.read_text())
    snaps = data["snapshots"]
    snap = (next(s for s in snaps if s["date"] == args.snapshot)
            if args.snapshot else snaps[-1])
    prev = None
    idx = snaps.index(snap)
    if idx > 0:
        prev = {m["reading_id"]: m for m in snaps[idx - 1]["modules"]}

    weight = {int(k): v for k, v in data["exam_weight"].items()
              if k.isdigit()}
    ranking = {r["reading_id"]: r for r in json.loads(RANKING.read_text())}
    order = sorted(ranking.values(), key=lambda r: -r["desk_need"])
    rank = {r["reading_id"]: i + 1 for i, r in enumerate(order)}

    sched = json.loads(SCHEDULE.read_text())
    desk, legs = {}, {}
    for day in sched["days"]:
        for blk in day["blocks"]:
            rid = blk.get("reading_id")
            if not rid:
                continue
            (legs if blk.get("commute") else desk)[rid] = \
                (legs if blk.get("commute") else desk).get(rid, 0) + blk["minutes"]

    # ---- per-module -------------------------------------------------------
    rows = []
    for m in snap["modules"]:
        n, score = m["n"], m["score"]
        k = round(score / 100 * n)
        lo, hi = wilson(k, n)
        share = BANK_Q[m["book"]][m["lm"]] / sum(BANK_Q[m["book"]].values())
        mw = weight[m["book"]] * share          # this module's exam weight
        rid = m["reading_id"]
        rows.append(dict(
            book=m["book"], lm=m["lm"], rid=rid, n=n, score=score,
            peer=m["peer"], delta=score - m["peer"], lo=lo * 100, hi=hi * 100,
            width=(hi - lo) * 100, mw=mw, risk=mw * (1 - score / 100),
            rank=rank.get(rid, 0), need=ranking.get(rid, {}).get("desk_need", 0),
            desk=desk.get(rid, 0), leg=legs.get(rid, 0),
            moved=(score - prev[rid]["score"]) if prev and rid in prev else None,
            fresh=bool(prev and rid not in prev),
        ))

    print(f"=== snapshot {snap['date']} — {snap['total_answered']} answered, "
          f"{snap['overall']}% vs {snap['overall_peer']}% peer\n")

    # ---- significance: does the interval clear the peer mark? -------------
    print("MODULES WHOSE 95% INTERVAL EXCLUDES THE PEER AVERAGE")
    print("(the only per-module claims this sample actually supports)\n")
    print(f"  {'module':46} {'n':>3} {'you':>4} {'95% CI':>13} {'peer':>5} {'verdict':>8}")
    sig = [r for r in rows if r["hi"] < r["peer"] or r["lo"] > r["peer"]]
    for r in sorted(sig, key=lambda r: r["delta"]):
        v = "BELOW" if r["hi"] < r["peer"] else "ABOVE"
        print(f"  B{r['book']} LM{r['lm']:<2} {r['rid'][:38]:40} {r['n']:3} "
              f"{r['score']:3}% [{r['lo']:4.0f},{r['hi']:4.0f}] {r['peer']:4}% {v:>8}")
    print(f"\n  {len(sig)} of {len(rows)} modules. The other "
          f"{len(rows)-len(sig)} are consistent with being at peer.\n")

    # ---- marks at risk, by book ------------------------------------------
    print("MARKS AT RISK BY BOOK — exam weight x (1 - your score)")
    print("(what the gap is worth, not how big it looks)\n")
    print(f"  {'book':26} {'wt':>5} {'you':>5} {'n':>5} {'bank':>6} "
          f"{'seen':>5} {'at risk':>8} {'vs peer':>8}")
    tot_risk = tot_peer_risk = 0.0
    for b in sorted(BOOK):
        br = [r for r in rows if r["book"] == b]
        if not br:
            continue
        n = sum(r["n"] for r in br)
        k = sum(round(r["score"] / 100 * r["n"]) for r in br)
        sc = k / n * 100
        pk = sum(r["peer"] / 100 * r["n"] for r in br)
        pc = pk / n * 100
        bank = data["bank_size"][str(b)]
        risk = weight[b] * (1 - sc / 100)
        prisk = weight[b] * (1 - pc / 100)
        tot_risk += risk
        tot_peer_risk += prisk
        print(f"  {BOOK[b]:26} {weight[b]:4.1f}% {sc:4.0f}% {n:5} {bank:6} "
              f"{n/bank*100:4.0f}% {risk:7.2f}  {risk-prisk:+7.2f}")
    print(f"  {'':26} {'':5} {'':5} {'':5} {'':6} {'':5} {tot_risk:7.2f}"
          f"  {tot_risk-tot_peer_risk:+7.2f}")
    print(f"\n  Projected score if today's rates held across the whole exam: "
          f"{100-tot_risk:.1f}%")
    print(f"  The same candidate cohort would score {100-tot_peer_risk:.1f}%.\n")

    # ---- where the marks actually sit ------------------------------------
    print("TOP 10 MODULES BY MARKS AT RISK")
    print("(exam weight of the module x the fraction you are getting wrong)\n")
    print(f"  {'module':46} {'wt':>5} {'you':>5} {'risk':>6} "
          f"{'rank':>7} {'desk':>6} {'train':>6}")
    for r in sorted(rows, key=lambda r: -r["risk"])[:10]:
        print(f"  B{r['book']} LM{r['lm']:<2} {r['rid'][:38]:40} {r['mw']:4.1f}% "
              f"{r['score']:4}% {r['risk']:5.2f} {r['rank']:4}/36 "
              f"{r['desk']/60:5.1f}h {r['leg']:5}m")

    # ---- out-of-sample test of the ranking --------------------------------
    print("\nDOES THE PLAN'S desk_need RANKING PREDICT THE RESULTS?")
    big = [r for r in rows if r["n"] >= 20]
    for label, key in (("vs delta-to-peer", "delta"), ("vs absolute score", "score")):
        xs = [r["need"] for r in big]
        ys = [r[key] for r in big]
        mx = sum(xs) / len(xs)
        my = sum(ys) / len(ys)
        cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
        den = math.sqrt(sum((x - mx) ** 2 for x in xs)
                        * sum((y - my) ** 2 for y in ys))
        r_ = cov / den
        t = r_ * math.sqrt(len(xs) - 2) / math.sqrt(1 - r_ * r_)
        print(f"  r(desk_need, {label:18}) = {r_:+.3f}   t={t:+.2f}  "
              f"n={len(xs)}   (negative = ranking was right)")

    # ---- plan mismatches --------------------------------------------------
    print("\nPLAN MISMATCHES — scored at or below 60% but ranked easy (>18/36)")
    print(f"  {'module':46} {'you':>5} {'rank':>7} {'desk':>6} {'train':>6} {'%train':>7}")
    for r in sorted(rows, key=lambda r: r["score"]):
        if r["score"] <= 60 and r["rank"] > 18 and r["n"] >= 20:
            tot = r["desk"] + r["leg"]
            print(f"  B{r['book']} LM{r['lm']:<2} {r['rid'][:38]:40} {r['score']:4}% "
                  f"{r['rank']:4}/36 {r['desk']/60:5.1f}h {r['leg']:5}m "
                  f"{r['leg']/tot*100:6.0f}%")

    # Rank-vs-rank: where the plan's ordering and the score ordering disagree
    # most. Comparing ranks rather than raw values avoids picking a threshold,
    # and both axes are restricted to the n>=20 modules so Ethics' 1- and
    # 2-question cells cannot produce a spurious disagreement.
    print("\nBIGGEST ORDERING DISAGREEMENTS (n>=20 modules only)")
    by_score = sorted(big, key=lambda r: r["score"])
    srank = {r["rid"]: i + 1 for i, r in enumerate(by_score)}
    prank = {r["rid"]: i + 1 for i, r in
             enumerate(sorted(big, key=lambda r: -r["need"]))}
    print(f"  {'module':46} {'you':>5} {'plan':>6} {'score':>6} {'gap':>5} "
          f"{'desk':>6} {'train':>6}")
    for r in sorted(big, key=lambda r: -abs(prank[r["rid"]] - srank[r["rid"]]))[:6]:
        gap = prank[r["rid"]] - srank[r["rid"]]
        word = "plan over-rates" if gap < 0 else "plan under-rates"
        print(f"  B{r['book']} LM{r['lm']:<2} {r['rid'][:38]:40} {r['score']:4}% "
              f"{prank[r['rid']]:4}/{len(big)} {srank[r['rid']]:4}/{len(big)} "
              f"{gap:+4}  {r['desk']/60:5.1f}h {r['leg']:5}m   {word}")

    # ---- coverage ---------------------------------------------------------
    print("\nSTILL UNMEASURED")
    seen = {r["rid"] for r in rows}
    for rid in sorted(desk, key=lambda r: -desk[r]):
        if rid not in seen:
            print(f"  {rid[:52]:54} rank {rank.get(rid,0):2}/36  "
                  f"{desk[rid]/60:5.1f}h desk + {legs.get(rid,0):4}m train")

    # ---- test-retest ------------------------------------------------------
    # The strongest thing in this dataset. When a module's n grows between two
    # snapshots, the NEW questions are an independent second sample of the same
    # module. Correlating the old score against the incremental score measures
    # reliability directly, instead of inferring it from binomial theory.
    if prev:
        pairs = []
        for m in snap["modules"]:
            q = prev.get(m["reading_id"])
            if not q or m["n"] <= q["n"]:
                continue
            add_n = m["n"] - q["n"]
            add_k = round(m["score"] / 100 * m["n"]) - round(q["score"] / 100 * q["n"])
            pairs.append(dict(rid=m["reading_id"], n1=q["n"], s1=q["score"],
                              n2=add_n, s2=add_k / add_n * 100, now=m["score"]))
        if len(pairs) >= 3:
            print("\n\nTEST-RETEST — modules re-sampled since the previous snapshot")
            print("(the second column is the NEW questions only, not the running total)\n")
            print(f"  {'module':46}{'first':>8}{'retest':>8}{'swing':>7}{'pooled':>8}")
            for p in sorted(pairs, key=lambda p: p["s2"] - p["s1"]):
                print(f"  {p['rid'][:44]:46}{p['s1']:7.0f}%{p['s2']:7.0f}%"
                      f"{p['s2']-p['s1']:+6.0f}{p['now']:7.0f}%")
            xs = [p["s1"] for p in pairs]
            ys = [p["s2"] for p in pairs]
            mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
            cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
            den = math.sqrt(sum((x - mx) ** 2 for x in xs)
                            * sum((y - my) ** 2 for y in ys))
            r_ = cov / den if den else 0.0
            swing = sum(abs(y - x) for x, y in zip(xs, ys)) / len(xs)
            print(f"\n  test-retest r = {r_:+.3f} over {len(pairs)} modules, "
                  f"mean absolute swing {swing:.1f}pp")
            if r_ < 0.3:
                print("  A module's score does NOT predict its own next sample. Any")
                print("  per-module finding is a coin flip; use the BOOK, which is the")
                print("  unit the generator allocates by anyway.")

    # ---- pace -------------------------------------------------------------
    # The dashboard shows only accuracy. The session log also carries a clock,
    # and time spent is an INDEPENDENT signal: a module answered slowly and
    # wrongly is a different problem from one answered quickly and wrongly, and
    # they do not want the same remedy.
    sessions = data.get("sessions", [])
    clean = [s for s in sessions if not s.get("outlier")]
    agg = {}
    for s in clean:
        if not s.get("reading_id"):
            continue
        a = agg.setdefault(s["reading_id"], {"sec": 0, "q": 0, "c": 0})
        a["sec"] += s["seconds"]
        a["q"] += s["questions"]
        a["c"] += s["correct"]

    if agg:
        print("\n\nPACE — seconds per question, from the quiz clock")
        excluded = [s for s in sessions if s.get("outlier")]
        allsec = sum(s["seconds"] for s in sessions)
        cleansec = sum(s["seconds"] for s in clean)
        cleanq = sum(s["questions"] for s in clean)
        print(f"  {len(sessions)} quizzes, {allsec/3600:.1f}h on the bank in total.")
        for s in excluded:
            print(f"  excluded: {s['at']} — {s['outlier']}")
        print(f"  Usable: {cleanq} questions in {cleansec/3600:.2f}h "
              f"= {cleansec/cleanq:.0f}s per question.")
        print("  Do NOT read that against the ~90s-per-item-set-question exam")
        print("  budget: these are module-level practice questions, shorter than")
        print("  an exam vignette, so the comparison flatters the pace. What is")
        print("  clean is the comparison BETWEEN modules below — same bank, same")
        print("  format, same day, so the differences are real.\n")

        prof = []
        for rid, a in agg.items():
            prof.append(dict(rid=rid, spq=a["sec"] / a["q"],
                             score=a["c"] / a["q"] * 100, q=a["q"],
                             rank=rank.get(rid, 0)))
        med_t = sorted(p["spq"] for p in prof)[len(prof) // 2]
        med_s = sorted(p["score"] for p in prof)[len(prof) // 2]

        xs = [p["spq"] for p in prof]
        ys = [p["score"] for p in prof]
        mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
        cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
        den = math.sqrt(sum((x - mx) ** 2 for x in xs)
                        * sum((y - my) ** 2 for y in ys))
        r_ = cov / den
        print(f"  r(seconds per question, score) = {r_:+.3f} over {len(prof)} modules")
        print(f"  medians: {med_t:.0f}s per question, {med_s:.0f}% correct\n")

        QUAD = {
            (False, True): ("SOLID            ", "quick and right — leave it alone"),
            (True, True): ("FRAGILE          ", "right, but slowly — knows it, has to derive it"),
            (False, False): ("DIDN'T ENGAGE    ", "quick and wrong — no foothold, likely guessed"),
            (True, False): ("WORKED AND FAILED", "slow and wrong — the real gaps"),
        }
        for key in [(True, False), (False, False), (True, True), (False, True)]:
            group = [p for p in prof
                     if (p["spq"] > med_t, p["score"] >= med_s) == key]
            if not group:
                continue
            name, gloss = QUAD[key]
            print(f"  {name} — {gloss}")
            for p in sorted(group, key=lambda p: p["score"]):
                print(f"      {p['rid'][:46]:48} {p['score']:4.0f}%  "
                      f"{p['spq']:4.0f}s/q   plan rank {p['rank']:2}/36")
            print()

    # ---- numbering check --------------------------------------------------
    mm = json.loads(MM_REVIEW.read_text())
    print("\nQUESTION-BANK vs REVIEW-PDF MODULE NUMBERING")
    for b in sorted(BOOK):
        pdf_no = {m["readingID"]: i + 1
                  for i, m in enumerate(mm["books"][b - 1]["modules"])
                  if m.get("readingID")}
        for r in [x for x in rows if x["book"] == b]:
            p = pdf_no.get(r["rid"])
            if p is None:
                print(f"  B{b} LM{r['lm']:<2} {r['rid'][:44]:46} "
                      f"bank has it, review PDF does NOT")
            elif p != r["lm"]:
                print(f"  B{b} LM{r['lm']:<2} {r['rid'][:44]:46} "
                      f"review PDF calls it LM{p}")


if __name__ == "__main__":
    main()
