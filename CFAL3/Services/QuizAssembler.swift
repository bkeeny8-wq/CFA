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

    /// Assemble a question ID list from the current PracticeBuilderPreference,
    /// drawing from the case bank and the LOS drill bank, respecting all
    /// filters and weakness weighting.
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

        switch pref.count {
        case .all:
            return ordered.map(\.id)
        default:
            return ordered.prefix(pref.count.rawValue).map(\.id)
        }
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
