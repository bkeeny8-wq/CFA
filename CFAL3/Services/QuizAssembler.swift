import Foundation

/// Which content sources feed the practice pool.
enum QuestionSourceFilter: String, CaseIterable, Identifiable, Codable {
    case both
    case caseOnly
    case drillsOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .both: return "All"
        case .caseOnly: return "Cases"
        case .drillsOnly: return "Drills"
        }
    }
}

enum QuizAssembler {

    /// Normalized view over both content sources so one filter pipeline
    /// serves case-based questions and LOS drills.
    struct PoolItem {
        let id: String
        let type: QuestionType
        let topicIDs: Set<String>
        let readingIDs: Set<String>
        let losIDs: Set<String>
        let gradeable: Bool
        let isDrill: Bool
    }

    /// Last-resort book for a reading `los_master` does not carry.
    ///
    /// Every bundled drill reading is in los_master today, so nothing here
    /// fires; it exists so a future content drop that adds drills before the
    /// master is updated still reaches the Books filter. Entries must agree
    /// with los_master — the endowment case study used to be listed under
    /// portfolio_construction here while los_master files it under the PM
    /// pathway, and back when this table was consulted unconditionally that
    /// single disagreement was enough to strand all 75 of its questions.
    private static let supplementalReadingTopics: [String: String] = [
        "guidance_standard_i_professionalism": "ethical_and_professional_standards",
        "guidance_standard_ii_integrity_capital_markets": "ethical_and_professional_standards",
        "guidance_standard_iii_duties_to_clients": "ethical_and_professional_standards",
        "guidance_standard_iv_duties_to_employers": "ethical_and_professional_standards",
        "guidance_standard_v_investment_analysis": "ethical_and_professional_standards",
        "guidance_standard_vi_conflicts_of_interest": "ethical_and_professional_standards",
        "guidance_standard_vii_responsibilities": "ethical_and_professional_standards",
        "case_study_in_portfolio_management_institutional_endowment": "portfolio_management_pathway",
        "case_study_in_portfolio_management_institutional_swf": "portfolio_construction",
    ]

    /// The granularity a session is "broken down" by. The finest active scope
    /// wins, so selecting specific LOS strata a session more tightly than
    /// selecting whole books. With nothing selected, a session spans every
    /// book present in the pool.
    enum Stratum {
        case los
        case reading
        case topic
    }

    /// Assemble a question ID list from the current PracticeBuilderPreference,
    /// drawing from the case bank and the LOS drill bank, respecting all
    /// filters and weakness weighting.
    ///
    /// `pref.count` is a PER-UNIT quota: each in-scope book / reading / LOS
    /// contributes up to that many questions, so the session total scales with
    /// how much scope is selected. `.all` lifts the cap and returns everything
    /// that matches.
    static func assemble(
        pref: PracticeBuilderPreference,
        content: ContentLoader,
        attempts: [Attempt]
    ) -> [String] {
        let pool = buildPool(pref: pref, content: content)
        let filtered = filterPool(pool, pref: pref)

        let ordered: [PoolItem]
        if pref.weaknessWeighted {
            ordered = orderByWeakness(pool: filtered, attempts: attempts)
        } else {
            ordered = filtered.shuffled()
        }

        guard pref.count != .all else {
            return ordered.map(\.id)
        }

        return stratifiedPick(
            ordered,
            pref: pref,
            quotaPerUnit: pref.count.rawValue,
            bookIDs: Set(content.questionBank?.topics.map(\.id) ?? [])
        )
    }

    // MARK: - Per-unit scaling

    /// The unit granularity a session breaks down into, given the active
    /// scope. Finest selected scope wins: LOS → reading → book.
    static func stratum(for pref: PracticeBuilderPreference) -> Stratum {
        if !pref.selectedLOS.isEmpty { return .los }
        if !pref.selectedReadings.isEmpty { return .reading }
        return .topic
    }

    /// The IDs of the units the quota is spread across. An explicit selection
    /// defines the units directly; with no selection at the book level, every
    /// book present in the (already filtered) pool becomes a unit so a
    /// whole-curriculum session is balanced across books rather than dominated
    /// by whichever book has the most questions.
    private static func targetUnits(
        stratum: Stratum,
        pref: PracticeBuilderPreference,
        pool: [PoolItem],
        bookIDs: Set<String>
    ) -> Set<String> {
        switch stratum {
        case .los:
            return pref.selectedLOS
        case .reading:
            return pref.selectedReadings
        case .topic:
            if !pref.selectedTopics.isEmpty { return pref.selectedTopics }
            // Only the six books. A PoolItem's topicIDs also carry the
            // topics.json summary IDs (cme_1, equity, ethics…), which share
            // this namespace but are not books — counting them made "5 per
            // book" spread its quota over ~16 units and return roughly twice
            // the questions the footer promised.
            let books = pool.reduce(into: Set<String>()) { $0.formUnion($1.topicIDs) }
            return books.intersection(bookIDs)
        }
    }

    private static func units(
        of item: PoolItem,
        stratum: Stratum,
        bookIDs: Set<String>
    ) -> Set<String> {
        switch stratum {
        case .los: return item.losIDs
        case .reading: return item.readingIDs
        // Same reason as targetUnits: keep non-book topic IDs out.
        case .topic: return item.topicIDs.intersection(bookIDs)
        }
    }

    /// Walk the priority-ordered pool once, giving each in-scope unit up to
    /// `quotaPerUnit` questions.
    ///
    /// A picked question is charged to exactly ONE unit — the emptiest one it
    /// touches — never to every under-quota unit at once. Charging them all
    /// reads like efficient scope-filling, but a bank question can still
    /// carry more than one LOS (now capped at 3). Before the tags were
    /// narrowed, 213 of 490 named 24 or more, and five such questions
    /// landing early drove all nine counters of a nine-LOS selection to the
    /// quota at once — 5 questions out of 145 eligible, against a promise of
    /// 45. Measured over 400 shuffles: 5–23 before, a full 45 after.
    ///
    /// One charge per question is also what makes the per-unit contract
    /// honest: N units in scope yield up to N × quota.
    private static func stratifiedPick(
        _ ordered: [PoolItem],
        pref: PracticeBuilderPreference,
        quotaPerUnit: Int,
        bookIDs: Set<String>
    ) -> [String] {
        let stratum = stratum(for: pref)
        let targets = targetUnits(stratum: stratum, pref: pref, pool: ordered, bookIDs: bookIDs)
        guard !targets.isEmpty, quotaPerUnit > 0 else { return [] }

        var takenPerUnit: [String: Int] = [:]
        var seen = Set<String>()
        var result: [String] = []

        for item in ordered {
            let itemUnits = units(of: item, stratum: stratum, bookIDs: bookIDs).intersection(targets)
            let underQuota = itemUnits.filter { (takenPerUnit[$0] ?? 0) < quotaPerUnit }
            guard !underQuota.isEmpty, seen.insert(item.id).inserted else { continue }
            result.append(item.id)
            // Emptiest unit first, so the quota spreads across the selection
            // instead of piling onto whichever unit happens to be listed
            // first; the unit ID breaks ties so one shuffle always yields one
            // session.
            if let charged = underQuota.min(by: {
                (takenPerUnit[$0] ?? 0, $0) < (takenPerUnit[$1] ?? 0, $1)
            }) {
                takenPerUnit[charged, default: 0] += 1
            }
        }
        return result
    }

    // MARK: - Pool construction

    private static func buildPool(
        pref: PracticeBuilderPreference,
        content: ContentLoader
    ) -> [PoolItem] {
        var pool: [PoolItem] = []

        if pref.sourceFilter != .drillsOnly, let bank = content.questionBank {
            for topic in bank.topics {
                for caseStudy in topic.cases {
                    for q in caseStudy.questions {
                        pool.append(PoolItem(
                            id: q.id,
                            type: q.type,
                            topicIDs: [topic.id],
                            readingIDs: Set(q.primaryReadingIDs),
                            losIDs: Set(q.candidateLOS),
                            gradeable: q.type != .mc || q.canGradeMC,
                            isDrill: false
                        ))
                    }
                }
            }
        }

        if pref.sourceFilter != .caseOnly {
            let readingTopics = readingTopicIndex(content: content)
            for bundle in content.losDrillBundles.values {
                for group in bundle.drills {
                    for d in group.questions {
                        pool.append(PoolItem(
                            id: d.id,
                            type: d.type,
                            topicIDs: readingTopics[d.readingID] ?? [],
                            readingIDs: [d.readingID],
                            losIDs: [d.primaryLOS],
                            gradeable: d.correct != nil,
                            isDrill: true
                        ))
                    }
                }
            }
        }

        return pool
    }

    /// Maps every reading to the book it belongs to, on `los_master`'s say-so.
    ///
    /// los_master has to be the authority here because it is what the scope
    /// UI is built from: the Books sheet, the Readings sheet and the LOS
    /// filter all enumerate `losMaster.areas`. Any other answer means the
    /// builder offers a reading under a book and then filters away every
    /// question belonging to it.
    ///
    /// Which is what happened. This used to be derived the other way round —
    /// from topics.json summaries, plus every bank question's
    /// `primary_reading_ids`, plus a static table — and a reading's book was
    /// then whatever cited it. Six readings came out under the wrong book and
    /// two of those dead-ended completely: picking book "Portfolio
    /// Construction" together with "Overview of Equity Portfolio Management"
    /// matched 0 of that reading's 145 questions, and the mirror case did the
    /// same to the endowment case study's 75. The same mis-mapping filed 300
    /// drills under a second book, which is the "books overlap" the Progress
    /// dashboard used to have to apologise for.
    static func readingTopicIndex(content: ContentLoader) -> [String: Set<String>] {
        var index: [String: Set<String>] = [:]
        for area in content.losMaster?.areas ?? [] {
            for reading in area.readings {
                index[reading.id, default: []].insert(area.id)
            }
        }
        // Only for a reading los_master does not carry at all. Every bundled
        // drill reading is in los_master today, so this is a safety net, not
        // a second opinion — it must never override the authority above.
        for (readingID, topicID) in supplementalReadingTopics where index[readingID] == nil {
            index[readingID] = [topicID]
        }
        return index
    }

    // MARK: - Filtering

    static func filterPool(
        _ pool: [PoolItem],
        pref: PracticeBuilderPreference
    ) -> [PoolItem] {
        pool.filter { item in
            guard pref.typeFilter.allows(item.type) else { return false }

            // Content-integrity gate: never serve an MC that cannot be graded.
            guard item.gradeable else { return false }

            if !pref.selectedTopics.isEmpty,
               item.topicIDs.isDisjoint(with: pref.selectedTopics) {
                return false
            }
            if !pref.selectedReadings.isEmpty,
               item.readingIDs.isDisjoint(with: pref.selectedReadings) {
                return false
            }
            if !pref.selectedLOS.isEmpty,
               item.losIDs.isDisjoint(with: pref.selectedLOS) {
                return false
            }
            return true
        }
    }

    // MARK: - Ordering

    private static func orderByWeakness(
        pool: [PoolItem],
        attempts: [Attempt]
    ) -> [PoolItem] {
        var latestScoreByQ: [String: Double] = [:]
        for attempt in attempts.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let wasCorrect = attempt.wasCorrect {
                latestScoreByQ[attempt.questionId] = wasCorrect ? 1.0 : 0.0
            } else if let grade = attempt.grade {
                latestScoreByQ[attempt.questionId] = Double(grade) / 5.0
            }
        }

        return pool
            .shuffled()
            .map { item -> (PoolItem, Double) in
                let score = latestScoreByQ[item.id] ?? 0.4
                return (item, score)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
