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

    /// Only questions the user has actually answered can be "due" — every
    /// card is seeded with `dueDate = .now`, so without the attempts test this
    /// pill reported the reading's entire question count on a fresh install.
    ///
    /// Uses `totalAttempts` alone rather than ReviewQueue's stricter union,
    /// because this call site has no attempts array in scope. The difference
    /// only shows for a question abandoned at the grading screen, which reads
    /// as not-started on this one pill.
    static func dueCount(for reading: Reading, cards: [ReviewCard], now: Date = .now) -> Int {
        cards.filter { card in
            card.totalAttempts > 0 && card.dueDate <= now && card.readingIds.contains(reading.id)
        }.count
    }

    /// Plan JSON still carries MM codes (`D3: B1-M1 …`). Today and Plan show
    /// the reading name; the code is a production leftover, not a study label.
    static func scheduleBlockTitle(_ block: ScheduleBlock, content: ContentLoader) -> String {
        if let id = block.readingID, let match = content.reading(id: id) {
            return readingShortTitle(match.reading, content: content)
        }
        return stripPlanCode(block.label)
    }

    static func stripPlanCode(_ label: String) -> String {
        let pattern = #"^(?:D\d+|MM Video|MM Q|MM):\s*(?:B\d+-M\d+\s+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return label }
        let range = NSRange(label.startIndex..., in: label)
        let stripped = regex.stringByReplacingMatches(in: label, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? label : stripped
    }
}

/// The Progress pace tile's caption and value.
///
/// These shipped contradicting each other: the caption was
/// `delta < -0.5 ? "On pace" : "On pace"` — both branches the same string, a
/// half-finished edit — while the value beside it read "−12h" and the tile
/// tinted copper on the very same condition. Someone twelve hours behind the
/// plan was told "On pace".
///
/// Kept out of the view so the three states can be tested. The 0.5h deadband
/// is deliberate: the plan is in hours and a few minutes either way is noise,
/// not a status change.
enum SchedulePace {
    static let deadbandHours = 0.5

    /// What the tile is reporting: the state, not the number.
    static func caption(_ delta: Double) -> String {
        if abs(delta) < deadbandHours { return "On pace" }
        return delta > 0 ? "Ahead" : "Behind"
    }

    /// The number under it. An em dash when on pace — repeating "On pace" as
    /// both caption and value is what the old pairing did in the other
    /// direction, and it reads as a glitch.
    static func value(_ delta: Double) -> String {
        if abs(delta) < deadbandHours { return "—" }
        let magnitude = Formatting.hours(abs(delta), precise: true)
        return delta > 0 ? "+\(magnitude)" : "−\(magnitude)"
    }

    static func isBehind(_ delta: Double) -> Bool { delta <= -deadbandHours }
}
