import SwiftUI
import SwiftData

@Observable
final class StudySessionCoordinator {
    var questionIDs: [String] = []
    var currentIndex: Int = 0
    var mode: SessionMode = .random
    var filterDescription: String = ""
    var sessionID: UUID = UUID()
    var completedAttemptIDs: [UUID] = []
    /// Question IDs the candidate flagged and skipped without answering.
    var skippedQuestionIDs: [String] = []
    /// When this session began. Sessions were persisted with startedAt and
    /// endedAt both set to the save moment, so every one recorded zero
    /// duration.
    var startedAt: Date = .now

    /// Hide/show for the vignette, keyed by case. Consecutive questions in
    /// the same case share this so the case does not collapse on every
    /// advance; a new sitting starts expanded.
    private var vignetteExpandedByCase: [String: Bool] = [:]

    var isActive: Bool { !questionIDs.isEmpty }
    var currentQuestionID: String? {
        guard currentIndex >= 0, currentIndex < questionIDs.count else { return nil }
        return questionIDs[currentIndex]
    }

    func start(
        questionIDs: [String],
        mode: SessionMode,
        filterDescription: String,
        sessionID: UUID = UUID()
    ) {
        self.questionIDs = questionIDs
        self.currentIndex = 0
        self.mode = mode
        self.filterDescription = filterDescription
        self.sessionID = sessionID
        self.completedAttemptIDs = []
        self.startedAt = .now
        self.vignetteExpandedByCase = [:]
        self.skippedQuestionIDs = []
    }

    /// Default open — Level III is sat with the vignette on the page.
    func vignetteExpanded(for caseID: String) -> Bool {
        vignetteExpandedByCase[caseID] ?? true
    }

    func setVignetteExpanded(_ expanded: Bool, for caseID: String) {
        vignetteExpandedByCase[caseID] = expanded
    }

    /// Persist the finished session. Lives here so the question runner and the
    /// drill runner cannot disagree — the drill runner had no equivalent at
    /// all, so every drill session (the larger half of the content) was absent
    /// from history and from every exported backup.
    func makeSessionRecord() -> Session {
        Session(
            // The session's own id, so the row has a stable identity and can be
            // kept up to date instead of only ever being created. It used to be
            // a fresh UUID per call, which left `persist` no way to find the
            // row it had already written.
            id: sessionID,
            startedAt: startedAt,
            endedAt: .now,
            mode: mode.rawValue,
            filterDescription: filterDescription,
            attemptIds: completedAttemptIDs
        )
    }

    /// Write this session's row, or bring the existing one up to date.
    ///
    /// Called as the session progresses, not once at the end. "Save & exit" on
    /// the summary screen used to be the only writer of a Session row, so
    /// every other way out — the back button, a swipe, switching tabs — lost
    /// the record of that sitting completely. The attempts themselves survived
    /// (each is saved as it is graded), but the row that groups them into a
    /// session did not, so history under-counted sittings and backups exported
    /// fewer sessions than had actually happened.
    ///
    /// Idempotent: safe to call after every answer, and on the way out.
    @MainActor
    func persist(into context: ModelContext) {
        // Skip-only sittings never wrote a row: persist gated on attempts,
        // and the runners only watched completedAttemptIDs, so flagging
        // every item and leaving left no session in history.
        guard !completedAttemptIDs.isEmpty || !skippedQuestionIDs.isEmpty else { return }

        let id = sessionID
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })

        if let existing = try? context.fetch(descriptor).first {
            existing.endedAt = .now
            existing.attemptIds = completedAttemptIDs
        } else {
            context.insert(makeSessionRecord())
        }
        try? context.save()
    }

    func recordAttempt(_ attemptID: UUID) {
        completedAttemptIDs.append(attemptID)
    }

    /// Flag-and-move: leave this item unanswered, keep the sitting going.
    @discardableResult
    func skipCurrent() -> Bool {
        if let id = currentQuestionID, !skippedQuestionIDs.contains(id) {
            skippedQuestionIDs.append(id)
        }
        return advance()
    }

    func advance() -> Bool {
        // Always move forward — including PAST the last question. The
        // session runner shows the summary when currentIndex reaches
        // questionIDs.count; stopping short of the end left the runner
        // displaying the final question after "Finish session".
        guard currentIndex < questionIDs.count else { return false }
        currentIndex += 1
        return currentIndex < questionIDs.count
    }

    func finish() {
        questionIDs = []
        currentIndex = 0
    }

    /// Start a follow-up sitting of the missed IDs. The runner must set
    /// `openedSessionID` to `sessionID` *before* this runs, or the sessionID
    /// onChange will treat the retry as a hijack and dismiss.
    func retryMissed(questionIDs: [String], sessionID: UUID) {
        let prior = filterDescription
        let label = prior.hasPrefix("Retry missed") ? prior : "Retry missed · \(prior)"
        start(
            questionIDs: questionIDs,
            mode: mode,
            filterDescription: label,
            sessionID: sessionID
        )
    }
}

/// Value-type debrief the session summary screens share. Built from attempts
/// plus a label/pace lookup so tests do not need a live store.
struct SessionDebrief: Equatable {
    struct Row: Equatable {
        var questionID: String
        var label: String
        var durationSeconds: Int
        var wasCorrect: Bool?
        var pointsEarned: Int?
        var pointsPossible: Int?
        var grade: Int?
        /// Exam point value for the 90s/point target. Nil → one MC slot (90s).
        var examPoints: Int?
        var isEssay: Bool
    }

    var attempted: Int
    var correctMC: Int
    var scoredMC: Int
    var essayEarned: Int
    var essayPossible: Int
    var missedIDs: [String]
    var missedLabels: [String]
    var unscoredCount: Int
    var elapsedSeconds: Int
    var targetSeconds: Int

    var canRetry: Bool { !missedIDs.isEmpty }

    var scoreLine: String {
        var parts: [String] = []
        if scoredMC > 0 {
            parts.append("\(correctMC)/\(scoredMC) correct")
        }
        if essayPossible > 0 {
            parts.append("\(essayEarned)/\(essayPossible) essay points")
        }
        if unscoredCount > 0 {
            parts.append("\(unscoredCount) ungraded")
        }
        if parts.isEmpty {
            return attempted == 0
                ? "No answers recorded"
                : "\(attempted) attempt\(attempted == 1 ? "" : "s")"
        }
        return parts.joined(separator: " · ")
    }

    var paceLine: String {
        if elapsedSeconds == 0 && attempted == 0 {
            return "No timed answers — skipped items don't count toward the 90s/point pace"
        }
        let delta = elapsedSeconds - targetSeconds
        let vs: String
        if delta == 0 {
            vs = "on the 90s/point pace"
        } else if delta > 0 {
            vs = "\(Formatting.duration(seconds: delta)) over 90s/point"
        } else {
            vs = "\(Formatting.duration(seconds: -delta)) under 90s/point"
        }
        return "\(Formatting.duration(seconds: elapsedSeconds)) elapsed · \(Formatting.duration(seconds: targetSeconds)) target · \(vs)"
    }

    static func snapshot(rows: [Row]) -> SessionDebrief {
        var correctMC = 0
        var scoredMC = 0
        var essayEarned = 0
        var essayPossible = 0
        var missedIDs: [String] = []
        var missedLabels: [String] = []
        var unscored = 0
        var elapsed = 0
        var target = 0

        for row in rows {
            elapsed += max(0, row.durationSeconds)
            target += ExamPacing.targetSeconds(points: row.examPoints)

            if row.isEssay {
                if let earned = row.pointsEarned, let possible = row.pointsPossible, possible > 0 {
                    essayEarned += earned
                    essayPossible += possible
                    if Double(earned) / Double(possible) < 0.7 {
                        missedIDs.append(row.questionID)
                        missedLabels.append(row.label)
                    }
                } else if let grade = row.grade {
                    if grade < 3 {
                        missedIDs.append(row.questionID)
                        missedLabels.append(row.label)
                    }
                } else {
                    unscored += 1
                }
            } else if let correct = row.wasCorrect {
                scoredMC += 1
                if correct {
                    correctMC += 1
                } else {
                    missedIDs.append(row.questionID)
                    missedLabels.append(row.label)
                }
            } else {
                unscored += 1
            }
        }

        return SessionDebrief(
            attempted: rows.count,
            correctMC: correctMC,
            scoredMC: scoredMC,
            essayEarned: essayEarned,
            essayPossible: essayPossible,
            missedIDs: missedIDs,
            missedLabels: missedLabels,
            unscoredCount: unscored,
            elapsedSeconds: elapsed,
            targetSeconds: target
        )
    }

    static func row(attempt: Attempt, content: ContentLoader) -> Row {
        if let question = content.question(id: attempt.questionId) {
            return Row(
                questionID: question.id,
                label: "Q\(question.number) · \(Formatting.truncatedStem(question.stem, limit: 48))",
                durationSeconds: attempt.durationSeconds,
                wasCorrect: attempt.wasCorrect,
                pointsEarned: attempt.pointsEarned,
                pointsPossible: attempt.pointsPossible,
                grade: attempt.grade,
                examPoints: question.pointValue,
                isEssay: question.type == .essay
            )
        }
        if let drill = content.drillQuestion(id: attempt.questionId) {
            return Row(
                questionID: drill.id,
                label: "Drill Q\(drill.number) · \(Formatting.truncatedStem(drill.stem, limit: 48))",
                durationSeconds: attempt.durationSeconds,
                wasCorrect: attempt.wasCorrect,
                pointsEarned: attempt.pointsEarned,
                pointsPossible: attempt.pointsPossible,
                grade: attempt.grade,
                examPoints: nil,
                isEssay: false
            )
        }
        return Row(
            questionID: attempt.questionId,
            label: attempt.questionId,
            durationSeconds: attempt.durationSeconds,
            wasCorrect: attempt.wasCorrect,
            pointsEarned: attempt.pointsEarned,
            pointsPossible: attempt.pointsPossible,
            grade: attempt.grade,
            examPoints: nil,
            isEssay: attempt.essayText != nil
        )
    }

    static func skippedLabels(ids: [String], content: ContentLoader) -> [String] {
        ids.map { id in
            if let question = content.question(id: id) {
                return "Q\(question.number) · \(Formatting.truncatedStem(question.stem, limit: 48))"
            }
            if let drill = content.drillQuestion(id: id) {
                return "Drill Q\(drill.number) · \(Formatting.truncatedStem(drill.stem, limit: 48))"
            }
            return id
        }
    }
}
