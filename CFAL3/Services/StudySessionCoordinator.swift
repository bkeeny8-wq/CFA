import SwiftUI

@Observable
final class StudySessionCoordinator {
    var questionIDs: [String] = []
    var currentIndex: Int = 0
    var mode: SessionMode = .random
    var filterDescription: String = ""
    var sessionID: UUID = UUID()
    var completedAttemptIDs: [UUID] = []

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
