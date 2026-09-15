import SwiftUI

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
            startedAt: startedAt,
            endedAt: .now,
            mode: mode.rawValue,
            filterDescription: filterDescription,
            attemptIds: completedAttemptIDs
        )
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
