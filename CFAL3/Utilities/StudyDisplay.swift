import Foundation

enum ReadingStudyState {
    case done
    case inProgress
    case notStarted
}

enum StudyDisplay {
    struct NextLOS {
        let readingNumber: Int
        let readingShortTitle: String
        let losLetter: String
    }

    static func nextLOS(
        master: LOSMaster,
        statuses: [LOSStudyStatus],
        content: ContentLoader
    ) -> NextLOS? {
        let byLOS = Dictionary(uniqueKeysWithValues: statuses.map { ($0.losId, $0) })

        for area in master.areas {
            for reading in area.readings {
                for los in reading.los {
                    if byLOS[los.id]?.studyState != .mastered {
                        return NextLOS(
                            readingNumber: readingNumber(reading, content: content),
                            readingShortTitle: readingShortTitle(reading, content: content),
                            losLetter: los.letter
                        )
                    }
                }
            }
        }
        return nil
    }

    static func readingNumber(_ reading: Reading, content: ContentLoader) -> Int {
        content.readingNotes(id: reading.id)?.readingNumber ?? 0
    }

    static func readingShortTitle(_ reading: Reading, content: ContentLoader) -> String {
        if let title = content.readingNotes(id: reading.id)?.title, !title.isEmpty {
            return title
        }
        return Formatting.shortTopicName(reading.name)
    }

    static func readingState(
        reading: Reading,
        statuses: [LOSStudyStatus],
        attempts: [Attempt],
        content: ContentLoader
    ) -> ReadingStudyState {
        let progress = StudyPlannerStats.readingProgress(reading: reading, statuses: statuses)
        if progress.total > 0, progress.mastered == progress.total {
            return .done
        }

        let byLOS = Dictionary(uniqueKeysWithValues: statuses.map { ($0.losId, $0) })
        let hasStatus = reading.los.contains { byLOS[$0.id] != nil }
        let drillIDs = drillQuestionIDs(for: reading, content: content)
        let hasDrillAttempt = attempts.contains { drillIDs.contains($0.questionId) }

        if hasStatus || hasDrillAttempt {
            return .inProgress
        }
        return .notStarted
    }

    static func firstInProgressReadingID(
        in area: CurriculumArea,
        statuses: [LOSStudyStatus],
        attempts: [Attempt],
        content: ContentLoader
    ) -> String? {
        for reading in area.readings {
            if readingState(reading: reading, statuses: statuses, attempts: attempts, content: content) == .inProgress {
                return reading.id
            }
        }
        return nil
    }

    static func drillQuestionIDs(for reading: Reading, content: ContentLoader) -> Set<String> {
        guard let bundle = content.drillBundle(forReading: reading.id) else { return [] }
        return Set(bundle.drills.flatMap { $0.questions.map(\.id) })
    }

    static func drillCount(for reading: Reading, content: ContentLoader) -> Int {
        content.drillBundle(forReading: reading.id)?.totalQuestions ?? 0
    }

    static func drillAccuracy(
        reading: Reading,
        attempts: [Attempt],
        content: ContentLoader
    ) -> Double? {
        let ids = drillQuestionIDs(for: reading, content: content)
        guard !ids.isEmpty else { return nil }
        let relevant = attempts.filter { ids.contains($0.questionId) }
        let gradable = relevant.filter { $0.wasCorrect != nil }
        guard !gradable.isEmpty else { return nil }
        return Double(gradable.filter { $0.wasCorrect == true }.count) / Double(gradable.count)
    }

    static func dueCount(for reading: Reading, cards: [ReviewCard], now: Date = .now) -> Int {
        cards.filter { card in
            card.dueDate <= now && card.readingIds.contains(reading.id)
        }.count
    }
}
