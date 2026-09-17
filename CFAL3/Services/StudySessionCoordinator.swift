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
    /// When this session began. Sessions were persisted with startedAt and
    /// endedAt both set to the save moment, so every one recorded zero
    /// duration.
    var startedAt: Date = .now

    var isActive: Bool { !questionIDs.isEmpty }
    var currentQuestionID: String? {
        guard currentIndex >= 0, currentIndex < questionIDs.count else { return nil }
        return questionIDs[currentIndex]
    }

    func start(questionIDs: [String], mode: SessionMode, filterDescription: String) {
        self.questionIDs = questionIDs
        self.currentIndex = 0
        self.mode = mode
        self.filterDescription = filterDescription
        self.sessionID = UUID()
        self.completedAttemptIDs = []
        self.startedAt = .now
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
        guard !completedAttemptIDs.isEmpty else { return }

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
}
