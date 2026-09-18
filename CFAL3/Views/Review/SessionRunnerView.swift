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
            if showSummary || sessionCoordinator.isPastLastQuestion {
                sessionSummary
            } else if let questionID = sessionCoordinator.currentQuestionID {
                attemptView(for: questionID)
                    .id(questionID)
            } else {
                ContentUnavailableView(
                    "This sitting is empty",
                    systemImage: "tray",
                    description: Text("Go back and start a review, practice, or drill session.")
                )
            }
        }
        .navigationTitle(sessionCoordinator.filterDescription)
        .navigationBarTitleDisplayMode(.inline)
        .hidesStudySelector()
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
        .onChange(of: sessionCoordinator.skippedQuestionIDs.count) { _, _ in
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
            MissingSittingItemView(
                title: "Question missing",
                description: "This item isn't in the current build. Skip & flag to keep the sitting going."
            )
        }
    }

    private var sessionSummary: some View {
        SessionDebriefList(
            debrief: debrief,
            skippedCount: sessionCoordinator.skippedQuestionIDs.count,
            skippedLabels: skippedLabels,
            modeLine: sessionCoordinator.filterDescription,
            onRetry: (debrief.canRetry || !sessionCoordinator.skippedQuestionIDs.isEmpty) ? retryMissed : nil,
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

    private var skippedLabels: [String] {
        SessionDebrief.skippedLabels(
            ids: sessionCoordinator.skippedQuestionIDs,
            content: content
        )
    }

    private func retryMissed() {
        var ids = debrief.missedIDs
        for id in sessionCoordinator.skippedQuestionIDs where !ids.contains(id) {
            ids.append(id)
        }
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
    var skippedCount: Int = 0
    var skippedLabels: [String] = []
    let modeLine: String
    var onRetry: (() -> Void)?
    var doneTitle: String
    var onDone: () -> Void

    var body: some View {
        List {
            Section {
                Text(debrief.scoreLine)
                if skippedCount > 0 {
                    Text("\(skippedCount) skipped & flagged")
                }
                Text(debrief.paceLine)
                Text("Mode: \(modeLine)")
            } header: {
                Text("Session debrief")
                    .accessibilityAddTraits(.isHeader)
            }
            if !debrief.missedLabels.isEmpty {
                Section {
                    ForEach(Array(debrief.missedLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                    }
                } header: {
                    Text("Missed")
                        .accessibilityAddTraits(.isHeader)
                }
            }
            if !skippedLabels.isEmpty {
                Section {
                    ForEach(Array(skippedLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                    }
                } header: {
                    Text("Skipped & flagged")
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Section {
                if let onRetry, debrief.canRetry || skippedCount > 0 {
                    let retryCount = debrief.missedIDs.count + skippedCount
                    Button(retryTitle(missed: debrief.missedIDs.count, skipped: skippedCount, total: retryCount)) {
                        onRetry()
                    }
                }
                Button(doneTitle, action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
    }

    private func retryTitle(missed: Int, skipped: Int, total: Int) -> String {
        if skipped > 0 && missed == 0 {
            return "Retry skipped (\(skipped))"
        }
        if skipped > 0 {
            return "Retry missed & skipped (\(total))"
        }
        return "Retry missed (\(missed))"
    }
}

/// An ID in the sitting that is not in this build. Skip keeps the session
/// moving instead of trapping the candidate on a dead screen.
struct MissingSittingItemView: View {
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    let title: String
    let description: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "questionmark.circle")
        } description: {
            Text(description)
        } actions: {
            if sessionCoordinator.isActive {
                Button(AttemptHost.skipTitle) {
                    _ = sessionCoordinator.skipCurrent()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("attempt.skip")
            }
        }
        .readableContentWidth()
        .padding()
    }
}
