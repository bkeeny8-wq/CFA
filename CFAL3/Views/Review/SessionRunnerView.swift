import SwiftUI
import SwiftData

struct SessionRunnerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(ContentLoader.self) private var content

    @State private var showSummary = false

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
            if sessionCoordinator.currentIndex >= sessionCoordinator.questionIDs.count,
               !sessionCoordinator.questionIDs.isEmpty {
                showSummary = true
            }
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
