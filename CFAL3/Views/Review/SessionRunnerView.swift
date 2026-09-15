import SwiftUI
import SwiftData

struct SessionRunnerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(ContentLoader.self) private var content

    @State private var showSummary = false
    /// The session this runner was opened for. There is one coordinator for
    /// the whole app, so starting a session from another tab replaces it —
    /// and this runner, still on screen, would silently begin showing the new
    /// session's questions under the old title. Close instead.
    @State private var openedSessionID: UUID?

    var body: some View {
        Group {
            if showSummary {
                sessionSummary
            } else if let questionID = sessionCoordinator.currentQuestionID {
                attemptView(for: questionID)
                    .id(questionID)
            } else {
                ContentUnavailableView("No questions", systemImage: "tray")
            }
        }
        .navigationTitle(sessionCoordinator.filterDescription)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: sessionCoordinator.currentIndex) { _, newValue in
            if newValue >= sessionCoordinator.questionIDs.count {
                showSummary = true
            }
        }
        .onAppear {
            if openedSessionID == nil { openedSessionID = sessionCoordinator.sessionID }
            if sessionCoordinator.currentIndex >= sessionCoordinator.questionIDs.count,
               !sessionCoordinator.questionIDs.isEmpty {
                showSummary = true
            }
        }
        .onChange(of: sessionCoordinator.sessionID) { _, newValue in
            guard let openedSessionID, openedSessionID != newValue else { return }
            dismiss()
        }
    }

    @ViewBuilder
    private func attemptView(for questionID: String) -> some View {
        let progress = (
            current: sessionCoordinator.currentIndex + 1,
            total: sessionCoordinator.questionIDs.count
        )
        if content.question(id: questionID) != nil {
            QuestionAttemptView(
                questionID: questionID,
                standalone: false,
                sessionProgress: progress
            )
        } else if let drill = content.drillQuestion(id: questionID) {
            LOSDrillAttemptView(
                drill: drill,
                standalone: false,
                sessionProgress: progress
            )
        } else {
            ContentUnavailableView("Question not found", systemImage: "questionmark.circle")
        }
    }

    private var sessionSummary: some View {
        List {
            Section("Session summary") {
                Text("\(sessionCoordinator.completedAttemptIDs.count) attempts")
                Text("Mode: \(sessionCoordinator.filterDescription)")
            }
            Section {
                Button("Save & exit") {
                    saveSession()
                    sessionCoordinator.finish()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
    }

    private func saveSession() {
        let session = Session(
            startedAt: .now,
            endedAt: .now,
            mode: sessionCoordinator.mode.rawValue,
            filterDescription: sessionCoordinator.filterDescription,
            attemptIds: sessionCoordinator.completedAttemptIDs
        )
        modelContext.insert(session)
        try? modelContext.save()
    }
}
