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

struct LOSItemCoverage: Identifiable, Hashable {
    let losID: String
    let letter: String
    let displayText: String
    let attempted: Int
    let questionCount: Int
    let correctRate: Double?

    var id: String { losID }
}

struct LOSReadingCoverage {
    let readingID: String
    let readingName: String
    let attempted: Int
    let questionCount: Int
    let caseQuestionCount: Int
    let drillQuestionCount: Int
    let correctRate: Double?
    let items: [LOSItemCoverage]
}

struct LOSAreaCoverage {
    let areaID: String
    let areaName: String
    let readings: [LOSReadingCoverage]
}

enum ProgressStats {
    static let legacyTopicMap: [String: String] = [
        "cme_1": "asset_allocation",
        "cme_2": "asset_allocation",
        "derivatives": "derivatives_and_risk_management",
        "alt_investments": "portfolio_construction",
        "institutional_investors": "portfolio_construction",
        "performance_evaluation": "performance_measurement",
        "manager_selection": "performance_measurement",
        "ethics": "ethical_and_professional_standards",
        "equity": "portfolio_management_pathway",
        "fixed_income": "portfolio_management_pathway",
        "trade_strategy_execution_volume_2_of_the_pm_pathwaymod_7":
            "portfolio_management_pathway",
    ]

    static func canonicalTopicID(_ id: String) -> String {
        legacyTopicMap[id] ?? id
    }

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

    /// Consecutive days studied, counting back from today — or from yesterday
    /// if today has not been studied YET.
    ///
    /// That "yet" is the whole point. Counting from today alone meant the
    /// streak collapsed to 0 at midnight and stayed there until the first
    /// question of the day: you opened the app having studied thirty days
    /// running and were told your streak was zero, which is both wrong and
    /// exactly the wrong thing to say to someone about to start.
    static func streakDays(attempts: [Attempt], now: Date = .now) -> Int {
        guard !attempts.isEmpty else { return 0 }
        let calendar = Calendar.current
        let daysWithAttempts = Set(attempts.map { calendar.startOfDay(for: $0.timestamp) })
        let today = calendar.startOfDay(for: now)

        // A streak is alive until today ENDS, not until today begins.
        var cursor = today
        if !daysWithAttempts.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
                return 0
            }
            cursor = yesterday
        }

        var streak = 0
        while daysWithAttempts.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Accuracy over gradable attempts, or a dash when nothing has been graded.
    ///
    /// The rate is 0 both for "answered nothing" and for "got everything
    /// wrong", so printing it raw showed a freshly-erased app a bold "0%"
    /// under Accuracy — which reads as a score, not as an empty history.
    static func accuracyDisplay(attempts: [Attempt]) -> String {
        let graded = attempts.filter { $0.wasCorrect != nil }
        guard !graded.isEmpty else { return "—" }
        let correct = graded.filter { $0.wasCorrect == true }.count
        return Formatting.percent(Double(correct) / Double(graded.count))
    }

    /// `unique` counts distinct questionIds across ALL attempts — bank and
    /// drill alike — so `total` has to span the same union. It is returned
    /// rather than left to the caller: when each view supplied its own
    /// denominator, both picked the bank-only count and "812/490" was reachable.
    static func overallStats(attempts: [Attempt], totalQuestions: Int) -> (attempted: Int, unique: Int, total: Int, correctRate: Double, avgSeconds: Double) {
        let unique = Set(attempts.map(\.questionId)).count
        let gradable = attempts.filter { $0.wasCorrect != nil }
        let correct = gradable.filter { $0.wasCorrect == true }.count
        let rate = gradable.isEmpty ? 0 : Double(correct) / Double(gradable.count)
        let avg = attempts.isEmpty
            ? 0
            : Double(attempts.map(\.durationSeconds).reduce(0, +)) / Double(attempts.count)
        return (attempts.count, unique, totalQuestions, rate, avg)
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

        // Per-LOS pool: case items tagged on that LOS ∪ drills whose primary
        // LOS is that row. Reading totals are the union of those pools, so
        // Standard III and GIPS .k show their own attempted/size instead of
        // disappearing into a reading-level smear.
        var caseByLOS: [String: Set<String>] = [:]
        var drillByLOS: [String: Set<String>] = [:]
        for topic in bank.topics {
            for caseStudy in topic.cases {
                for question in caseStudy.questions {
                    for losID in question.candidateLOS {
                        caseByLOS[losID, default: []].insert(question.id)
                    }
                }
            }
        }
        for bundle in content.losDrillBundles.values {
            for group in bundle.drills {
                for drill in group.questions {
                    drillByLOS[drill.primaryLOS, default: []].insert(drill.id)
                }
            }
        }
        var questionsByLOS: [String: Set<String>] = [:]
        for (id, ids) in caseByLOS { questionsByLOS[id, default: []].formUnion(ids) }
        for (id, ids) in drillByLOS { questionsByLOS[id, default: []].formUnion(ids) }

        let latestAttemptByQuestion: [String: Attempt] = {
            var map: [String: Attempt] = [:]
            for attempt in attempts.sorted(by: { $0.timestamp < $1.timestamp }) {
                map[attempt.questionId] = attempt
            }
            return map
        }()

        func coverage(for ids: Set<String>) -> (attempted: Int, total: Int, rate: Double?) {
            let attemptedIDs = ids.filter { latestAttemptByQuestion[$0] != nil }
            let gradable = attemptedIDs.compactMap { latestAttemptByQuestion[$0] }.filter { $0.wasCorrect != nil }
            let correct = gradable.filter { $0.wasCorrect == true }.count
            let rate: Double? = gradable.isEmpty ? nil : Double(correct) / Double(gradable.count)
            return (attemptedIDs.count, ids.count, rate)
        }

        return master.areas.map { area in
            let readings = area.readings.map { reading -> LOSReadingCoverage in
                let items = reading.los.map { los -> LOSItemCoverage in
                    let ids = questionsByLOS[los.id] ?? []
                    let stats = coverage(for: ids)
                    return LOSItemCoverage(
                        losID: los.id,
                        letter: los.letter,
                        displayText: los.displayText,
                        attempted: stats.attempted,
                        questionCount: stats.total,
                        correctRate: stats.rate
                    )
                }
                var readingIDs = Set<String>()
                var caseIDs = Set<String>()
                var drillIDs = Set<String>()
                for los in reading.los {
                    if let ids = questionsByLOS[los.id] {
                        readingIDs.formUnion(ids)
                    }
                    if let ids = caseByLOS[los.id] { caseIDs.formUnion(ids) }
                    if let ids = drillByLOS[los.id] { drillIDs.formUnion(ids) }
                }
                let stats = coverage(for: readingIDs)
                return LOSReadingCoverage(
                    readingID: reading.id,
                    readingName: reading.name,
                    attempted: stats.attempted,
                    questionCount: stats.total,
                    caseQuestionCount: caseIDs.count,
                    drillQuestionCount: drillIDs.count,
                    correctRate: stats.rate,
                    items: items
                )
            }
            return LOSAreaCoverage(areaID: area.id, areaName: area.name, readings: readings)
        }
    }

    /// Progress over a book's CASE questions only — deliberately narrower than
    /// `topicProgress`, which also counts the LOS drills. The case browser can
    /// only reach case questions, so a drill-inclusive total there would be a
    /// denominator the user cannot move. Callers must label it as such; the
    /// two screens that show it used to keep private, divergent copies.
    static func caseProgress(
        topic: BankTopic,
        attempts: [Attempt]
    ) -> (attempted: Int, total: Int, correctRate: Double) {
        let questionIDs = Set(topic.cases.flatMap { $0.questions.map(\.id) })
        let mine = attempts.filter { questionIDs.contains($0.questionId) }
        let unique = Set(mine.map(\.questionId)).count
        let gradable = mine.filter { $0.wasCorrect != nil }
        let correct = gradable.filter { $0.wasCorrect == true }.count
        let rate = gradable.isEmpty ? 0 : Double(correct) / Double(gradable.count)
        return (unique, questionIDs.count, rate)
    }

    /// `bestPoints` exists because essays have no `wasCorrect` — they are
    /// scored out of a mark. Without it a caller can only ask "was it correct",
    /// which is false for every essay ever written, however good.
    static func cardStats(
        for questionID: String,
        attempts: [Attempt],
        card: ReviewCard?
    ) -> (attempts: Int, correct: Int, lastWasCorrect: Bool?, bestPoints: (earned: Int, possible: Int)?) {
        let questionAttempts = attempts.filter { $0.questionId == questionID }
        let correctCount = questionAttempts.filter { $0.wasCorrect == true }.count
        let last = questionAttempts.sorted { $0.timestamp > $1.timestamp }.first?.wasCorrect

        let scored = questionAttempts.compactMap { attempt -> (Int, Int)? in
            guard let earned = attempt.pointsEarned,
                  let possible = attempt.pointsPossible,
                  possible > 0
            else { return nil }
            return (earned, possible)
        }
        // Best attempt, not latest: the pill is a record of what you have shown
        // you can do, and a scratch re-attempt should not erase it.
        let best = scored.max { Double($0.0) / Double($0.1) < Double($1.0) / Double($1.1) }

        return (
            questionAttempts.count,
            correctCount,
            last,
            best.map { (earned: $0.0, possible: $0.1) }
        )
    }

    static func contentDensity(content: ContentLoader) -> [ContentDensityProgress] {
        guard let targets = content.contentTargets, let bank = content.questionBank else { return [] }

        var haveByArea: [String: (mc: Int, essay: Int, drill: Int)] = [:]
        for area in targets.areas {
            haveByArea[area.id] = (0, 0, 0)
        }

        for topic in bank.topics {
            let areaID = canonicalTopicID(topic.id)
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
