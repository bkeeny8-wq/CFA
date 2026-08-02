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

    /// Drill readings that no bank question references, mapped to the bank
    /// topic they belong to so the Topics filter still reaches them.
    private static let supplementalReadingTopics: [String: String] = [
        "guidance_standard_i_professionalism": "ethical_and_professional_standards",
        "guidance_standard_ii_integrity_capital_markets": "ethical_and_professional_standards",
        "guidance_standard_iii_duties_to_clients": "ethical_and_professional_standards",
        "guidance_standard_iv_duties_to_employers": "ethical_and_professional_standards",
        "guidance_standard_v_investment_analysis": "ethical_and_professional_standards",
        "guidance_standard_vi_conflicts_of_interest": "ethical_and_professional_standards",
        "guidance_standard_vii_responsibilities": "ethical_and_professional_standards",
        "case_study_in_portfolio_management_institutional_endowment": "portfolio_construction",
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
            quotaPerUnit: pref.count.rawValue
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
        pool: [PoolItem]
    ) -> Set<String> {
        switch stratum {
        case .los:
            return pref.selectedLOS
        case .reading:
            return pref.selectedReadings
        case .topic:
            if !pref.selectedTopics.isEmpty { return pref.selectedTopics }
            return pool.reduce(into: Set<String>()) { $0.formUnion($1.topicIDs) }
        }
    }

    private static func units(of item: PoolItem, stratum: Stratum) -> Set<String> {
        switch stratum {
        case .los: return item.losIDs
        case .reading: return item.readingIDs
        case .topic: return item.topicIDs
        }
    }

    /// Walk the priority-ordered pool once, giving each in-scope unit up to
    /// `quotaPerUnit` questions. A question tagged to several in-scope units
    /// counts toward every under-quota unit it touches, so multi-tagged
    /// questions fill scope efficiently and are never returned twice.
    private static func stratifiedPick(
        _ ordered: [PoolItem],
        pref: PracticeBuilderPreference,
        quotaPerUnit: Int
    ) -> [String] {
        let stratum = stratum(for: pref)
        let targets = targetUnits(stratum: stratum, pref: pref, pool: ordered)
        guard !targets.isEmpty, quotaPerUnit > 0 else { return [] }

        var takenPerUnit: [String: Int] = [:]
        var seen = Set<String>()
        var result: [String] = []

        for item in ordered {
            let itemUnits = units(of: item, stratum: stratum).intersection(targets)
            let underQuota = itemUnits.filter { (takenPerUnit[$0] ?? 0) < quotaPerUnit }
            guard !underQuota.isEmpty, seen.insert(item.id).inserted else { continue }
            result.append(item.id)
            for unit in underQuota {
                takenPerUnit[unit, default: 0] += 1
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

    /// Maps every reading ID to the bank topics whose questions reference it
    /// (plus the topic summaries' declared readings), supplemented with static
    /// entries for drill-only readings. All inserts are union-based so
    /// malformed content can never crash assembly.
    static func readingTopicIndex(content: ContentLoader) -> [String: Set<String>] {
        var index: [String: Set<String>] = [:]
        for summary in content.topicSummaries {
            for readingID in summary.readingIDs {
                index[readingID, default: []].insert(summary.id)
            }
        }
        if let bank = content.questionBank {
            for topic in bank.topics {
                for caseStudy in topic.cases {
                    for q in caseStudy.questions {
                        for readingID in q.primaryReadingIDs {
                            index[readingID, default: []].insert(topic.id)
                        }
                    }
                }
            }
        }
        for (readingID, topicID) in supplementalReadingTopics {
            index[readingID, default: []].insert(topicID)
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
