import SwiftUI
import SwiftData

struct SessionRunnerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

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
        // Keep the session's row current as you go, so leaving by any route
        // still records the sitting. "Save & exit" was the only writer.
        .onChange(of: sessionCoordinator.completedAttemptIDs.count) { _, _ in
            sessionCoordinator.persist(into: modelContext)
        }
    }

    @ViewBuilder
    private func attemptView(for questionID: String) -> some View {
        let progress = (
            current: sessionCoordinator.currentIndex + 1,
            total: sessionCoordinator.questionIDs.count
        )
        if content.question(id: questionID) != nil {
            let caseID = content.context(for: questionID)?.caseId
            QuestionAttemptView(
                questionID: questionID,
                standalone: false,
                sessionProgress: progress,
                vignetteExpansion: caseID.map { id in
                    Binding(
                        get: { sessionCoordinator.vignetteExpanded(for: id) },
                        set: { sessionCoordinator.setVignetteExpanded($0, for: id) }
                    )
                }
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
        SessionDebriefList(
            debrief: debrief,
            modeLine: sessionCoordinator.filterDescription,
            onRetry: debrief.canRetry ? retryMissed : nil,
            doneTitle: "Save & exit",
            onDone: {
                saveSession()
                sessionCoordinator.finish()
                dismiss()
            }
        )
    }

    private var debrief: SessionDebrief {
        SessionDebrief.snapshot(rows: debriefRows)
    }

    private var debriefRows: [SessionDebrief.Row] {
        let byID = Dictionary(uniqueKeysWithValues: attempts.map { ($0.id, $0) })
        return sessionCoordinator.completedAttemptIDs.compactMap { id in
            byID[id].map { SessionDebrief.row(attempt: $0, content: content) }
        }
    }

    private func retryMissed() {
        let ids = debrief.missedIDs
        guard !ids.isEmpty else { return }
        saveSession()
        let next = UUID()
        openedSessionID = next
        sessionCoordinator.retryMissed(questionIDs: ids, sessionID: next)
        showSummary = false
    }

    private func saveSession() {
        sessionCoordinator.persist(into: modelContext)
    }
}

struct SessionDebriefList: View {
    let debrief: SessionDebrief
    let modeLine: String
    var onRetry: (() -> Void)?
    var doneTitle: String
    var onDone: () -> Void

    var body: some View {
        List {
            Section("Session debrief") {
                Text(debrief.scoreLine)
                Text(debrief.paceLine)
                Text("Mode: \(modeLine)")
            }
            if !debrief.missedLabels.isEmpty {
                Section("Missed") {
                    ForEach(Array(debrief.missedLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                    }
                }
            }
            Section {
                if let onRetry, debrief.canRetry {
                    Button("Retry missed (\(debrief.missedIDs.count))") {
                        onRetry()
                    }
                }
                Button(doneTitle, action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
    }
}
