import Foundation
import SwiftData

struct TopicProgress {
    let topicID: String
    let name: String
    let attempted: Int
    let total: Int
    let correctRate: Double
    let averageSeconds: Double
}

struct WeeklyAttemptVolume: Identifiable {
    let id: String
    let weekStart: Date
    let count: Int
}

struct LOSReadingCoverage {
    let readingID: String
    let readingName: String
    let attempted: Int
    let questionCount: Int
    let correctRate: Double?
}

struct LOSAreaCoverage {
    let areaID: String
    let areaName: String
    let readings: [LOSReadingCoverage]
}

enum ProgressStats {
    static func topicProgress(
        content: ContentLoader,
        attempts: [Attempt],
        cards: [ReviewCard]
    ) -> [TopicProgress] {
        guard let bank = content.questionBank else { return [] }

        let readingTopics = QuizAssembler.readingTopicIndex(content: content)
        var drillIDsByTopic: [String: Set<String>] = [:]
        for bundle in content.losDrillBundles.values {
            for group in bundle.drills {
                for drill in group.questions {
                    for topicID in readingTopics[drill.readingID] ?? [] {
                        drillIDsByTopic[topicID, default: []].insert(drill.id)
                    }
                }
            }
        }

        return bank.topics.map { topic in
            var questionIDs = Set(topic.cases.flatMap { $0.questions.map(\.id) })
            questionIDs.formUnion(drillIDsByTopic[topic.id] ?? [])
            let topicAttempts = attempts.filter { questionIDs.contains($0.questionId) }
            let uniqueAttempted = Set(topicAttempts.map(\.questionId)).count
            let gradable = topicAttempts.filter { $0.wasCorrect != nil }
            let correct = gradable.filter { $0.wasCorrect == true }.count
            let rate = gradable.isEmpty ? 0 : Double(correct) / Double(gradable.count)
            let avgTime = topicAttempts.isEmpty
                ? 0
                : Double(topicAttempts.map(\.durationSeconds).reduce(0, +)) / Double(topicAttempts.count)

            return TopicProgress(
                topicID: topic.id,
                name: topic.shortName,
                attempted: uniqueAttempted,
                total: questionIDs.count,
                correctRate: rate,
                averageSeconds: avgTime
            )
        }
    }

    static func weakestTopics(
        content: ContentLoader,
        attempts: [Attempt],
        minimumAttempts: Int = 5,
        limit: Int = 3
    ) -> [TopicProgress] {
        topicProgress(content: content, attempts: attempts, cards: [])
            .filter { $0.attempted >= minimumAttempts }
            .sorted { $0.correctRate < $1.correctRate }
            .prefix(limit)
            .map { $0 }
    }

    static func streakDays(attempts: [Attempt], now: Date = .now) -> Int {
        guard !attempts.isEmpty else { return 0 }
        let calendar = Calendar.current
        let daysWithAttempts = Set(attempts.map { calendar.startOfDay(for: $0.timestamp) })
        var streak = 0
        var cursor = calendar.startOfDay(for: now)

        while daysWithAttempts.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    static func overallStats(attempts: [Attempt], totalQuestions: Int) -> (attempted: Int, unique: Int, correctRate: Double, avgSeconds: Double) {
        let unique = Set(attempts.map(\.questionId)).count
        let gradable = attempts.filter { $0.wasCorrect != nil }
        let correct = gradable.filter { $0.wasCorrect == true }.count
        let rate = gradable.isEmpty ? 0 : Double(correct) / Double(gradable.count)
        let avg = attempts.isEmpty
            ? 0
            : Double(attempts.map(\.durationSeconds).reduce(0, +)) / Double(attempts.count)
        return (attempts.count, unique, rate, avg)
    }

    static func weeklyVolumes(attempts: [Attempt], weeks: Int = 8, now: Date = .now) -> [WeeklyAttemptVolume] {
        let calendar = Calendar.current
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }

        return (0..<weeks).reversed().map { offset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: startOfWeek) ?? startOfWeek
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let count = attempts.filter { $0.timestamp >= weekStart && $0.timestamp < weekEnd }.count
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return WeeklyAttemptVolume(id: formatter.string(from: weekStart), weekStart: weekStart, count: count)
        }
    }

    static func losCoverage(content: ContentLoader, attempts: [Attempt]) -> [LOSAreaCoverage] {
        guard let master = content.losMaster, let bank = content.questionBank else { return [] }

        let questionsByReading: [String: [String]] = {
            var map: [String: Set<String>] = [:]
            for topic in bank.topics {
                for caseStudy in topic.cases {
                    for question in caseStudy.questions {
                        for readingID in question.primaryReadingIDs {
                            map[readingID, default: []].insert(question.id)
                        }
                    }
                }
            }
            // drills are first-class practice content; count them per reading.
            for bundle in content.losDrillBundles.values {
                for group in bundle.drills {
                    for drill in group.questions {
                        map[drill.readingID, default: []].insert(drill.id)
                    }
                }
            }
            return map.mapValues { Array($0) }
        }()

        let latestAttemptByQuestion: [String: Attempt] = {
            var map: [String: Attempt] = [:]
            for attempt in attempts.sorted(by: { $0.timestamp < $1.timestamp }) {
                map[attempt.questionId] = attempt
            }
            return map
        }()

        return master.areas.map { area in
            let readings = area.readings.map { reading -> LOSReadingCoverage in
                let questionIDs = questionsByReading[reading.id] ?? []
                let attemptedIDs = questionIDs.filter { latestAttemptByQuestion[$0] != nil }
                let gradable = attemptedIDs.compactMap { latestAttemptByQuestion[$0] }.filter { $0.wasCorrect != nil }
                let correct = gradable.filter { $0.wasCorrect == true }.count
                let rate: Double? = gradable.isEmpty ? nil : Double(correct) / Double(gradable.count)
                return LOSReadingCoverage(
                    readingID: reading.id,
                    readingName: reading.name,
                    attempted: attemptedIDs.count,
                    questionCount: questionIDs.count,
                    correctRate: rate
                )
            }
            return LOSAreaCoverage(areaID: area.id, areaName: area.name, readings: readings)
        }
    }

    static func dueCountByTopic(cards: [ReviewCard], now: Date = .now) -> [String: Int] {
        Dictionary(grouping: cards.filter { $0.dueDate <= now }, by: \.topicId)
            .mapValues(\.count)
    }

    static func cardStats(for questionID: String, attempts: [Attempt], card: ReviewCard?) -> (attempts: Int, correct: Int, lastWasCorrect: Bool?) {
        let questionAttempts = attempts.filter { $0.questionId == questionID }
        let correctCount = questionAttempts.filter { $0.wasCorrect == true }.count
        let last = questionAttempts.sorted { $0.timestamp > $1.timestamp }.first?.wasCorrect
        return (questionAttempts.count, correctCount, last)
    }

    private static let topicToExamArea: [String: String] = [
        "cme_1": "asset_allocation",
        "cme_2": "asset_allocation",
        "asset_allocation": "asset_allocation",
        "derivatives": "derivatives_and_risk_management",
        "fixed_income": "portfolio_management_pathway",
        "equity": "portfolio_management_pathway",
        "alt_investments": "portfolio_construction",
        "institutional_investors": "portfolio_construction",
        "trade_strategy_execution_volume_2_of_the_pm_pathwaymod_7": "portfolio_management_pathway",
        "performance_evaluation": "performance_measurement",
        "manager_selection": "performance_measurement",
        "ethics": "ethical_and_professional_standards",
    ]

    static func contentDensity(content: ContentLoader) -> [ContentDensityProgress] {
        guard let targets = content.contentTargets, let bank = content.questionBank else { return [] }

        var haveByArea: [String: (mc: Int, essay: Int, drill: Int)] = [:]
        for area in targets.areas {
            haveByArea[area.id] = (0, 0, 0)
        }

        for topic in bank.topics {
            guard let areaID = topicToExamArea[topic.id] else { continue }
            var counts = haveByArea[areaID] ?? (0, 0, 0)
            for caseStudy in topic.cases {
                for question in caseStudy.questions {
                    if question.type == .essay {
                        counts.essay += 1
                    } else {
                        counts.mc += 1
                    }
                }
            }
            haveByArea[areaID] = counts
        }

        if let master = content.losMaster {
            for area in master.areas {
                for reading in area.readings {
                    let drillCount = content.drillBundle(forReading: reading.id)?.drills
                        .flatMap(\.questions).count ?? 0
                    var counts = haveByArea[area.id] ?? (0, 0, 0)
                    counts.drill += drillCount
                    haveByArea[area.id] = counts
                }
            }
        }

        return targets.areas.map { area in
            let have = haveByArea[area.id] ?? (0, 0, 0)
            let total = have.mc + have.essay + have.drill
            return ContentDensityProgress(
                areaID: area.id,
                areaName: area.name,
                examWeight: area.examWeight,
                haveTotal: total,
                haveMC: have.mc + have.drill,
                haveEssay: have.essay,
                targetTotal: area.total,
                targetMC: area.mc,
                targetEssay: area.essay
            )
        }
    }
}
