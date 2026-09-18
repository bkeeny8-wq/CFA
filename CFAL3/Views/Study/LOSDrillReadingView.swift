import SwiftUI
import SwiftData

struct LOSDrillReadingView: View {
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator

    let reading: Reading
    let bundle: LOSDrillBundle

    @State private var selectedLOS: String?
    @State private var query = ""
    @State private var showSession = false

    private var selectedGroup: LOSDrillGroup? {
        let letter = selectedLOS ?? bundle.drills.first?.losLetter
        return bundle.drills.first { $0.losLetter == letter }
    }

    private var searchResults: [(letter: String, drill: DrillQuestion)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return bundle.drills.flatMap { group in
            group.questions
                .filter {
                    $0.stem.lowercased().contains(q)
                        || group.losText.lowercased().contains(q)
                }
                .map { (group.losLetter.uppercased(), $0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerSection

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    losSelector
                    if let group = selectedGroup {
                        selectedGroupContent(group)
                    }
                } else {
                    searchContent
                }
            }
            .padding()
        }
        .navigationTitle("LOS Drills")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search this reading's drills"
        )
        .navigationDestination(isPresented: $showSession) {
            DrillSessionRunnerView()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(bundle.totalQuestions) drill questions")
                    .font(.headline)
                Text("Curriculum-grounded MC drills — one set per LOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                startSession(
                    ids: bundle.drills.flatMap { $0.questions.map(\.id) }.shuffled(),
                    description: "LOS drills — \(reading.name)"
                )
            } label: {
                Label("Drill all \(bundle.totalQuestions) (shuffled)", systemImage: "shuffle")
            }
        }
        .cfaCard()
    }

    private var losSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(bundle.drills) { group in
                    let selected = (selectedLOS ?? bundle.drills.first?.losLetter) == group.losLetter
                    Button {
                        selectedLOS = group.losLetter
                    } label: {
                        Text(group.losLetter.uppercased())
                            .font(.subheadline.weight(.medium))
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, 4)
                            .background(
                                Capsule()
                                    .fill(selected ? Theme.accent.opacity(0.18) : Color(.systemGray6))
                            )
                            .foregroundStyle(selected ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("LOS \(group.losLetter.uppercased())")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func selectedGroupContent(_ group: LOSDrillGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.losText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                startSession(
                    ids: group.questions.map(\.id),
                    description: "LOS \(group.losLetter.uppercased()) drill"
                )
            } label: {
                Label("Run all \(group.questions.count)", systemImage: "play.fill")
            }

            ForEach(group.questions) { drill in
                NavigationLink {
                    LOSDrillAttemptView(drill: drill)
                } label: {
                    drillRow(drill)
                }
                .buttonStyle(.plain)
            }
        }
        .cfaCard()
    }

    @ViewBuilder
    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(searchResults.count) match\(searchResults.count == 1 ? "" : "es")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !searchResults.isEmpty {
                Button {
                    startSession(
                        ids: searchResults.map(\.drill.id).shuffled(),
                        description: "Search: \(query.trimmingCharacters(in: .whitespacesAndNewlines))"
                    )
                } label: {
                    Label("Run matches", systemImage: "play.fill")
                }
            } else {
                ContentUnavailableView(
                    "No matching drills",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different word from the stem or the LOS statement.")
                )
            }

            ForEach(searchResults, id: \.drill.id) { result in
                NavigationLink {
                    LOSDrillAttemptView(drill: result.drill)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        CapsuleBadge(text: result.letter)
                        drillRow(result.drill)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .cfaCard()
    }

    private func drillRow(_ drill: DrillQuestion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Q\(drill.number)")
                .font(.subheadline.weight(.medium))
            Text(Formatting.truncatedStem(drill.stem))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func startSession(ids: [String], description: String) {
        sessionCoordinator.start(
            questionIDs: ids,
            mode: .losDrill,
            filterDescription: description
        )
        showSession = true
    }
}

struct DrillSessionRunnerView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Query private var attempts: [Attempt]

    @State private var showSummary = false
    @State private var openedSessionID: UUID?

    var body: some View {
        Group {
            if showSummary {
                SessionDebriefList(
                    debrief: debrief,
                    skippedCount: sessionCoordinator.skippedQuestionIDs.count,
                    skippedLabels: SessionDebrief.skippedLabels(
                        ids: sessionCoordinator.skippedQuestionIDs,
                        content: content
                    ),
                    modeLine: sessionCoordinator.filterDescription,
                    onRetry: (debrief.canRetry || !sessionCoordinator.skippedQuestionIDs.isEmpty) ? retryMissed : nil,
                    doneTitle: "Done",
                    onDone: {
                        sessionCoordinator.persist(into: modelContext)
                        sessionCoordinator.finish()
                        dismiss()
                    }
                )
            } else if let questionID = sessionCoordinator.currentQuestionID,
                      let drill = content.drillQuestion(id: questionID) {
                LOSDrillAttemptView(
                    drill: drill,
                    standalone: false,
                    sessionProgress: (
                        current: sessionCoordinator.currentIndex + 1,
                        total: sessionCoordinator.questionIDs.count
                    )
                )
                .id(questionID)
            } else if sessionCoordinator.currentQuestionID != nil {
                MissingSittingItemView(
                    title: "Drill missing",
                    description: "This drill isn't in the current build. Skip & flag to keep the sitting going."
                )
            } else {
                ContentUnavailableView(
                    "Drill missing",
                    systemImage: "questionmark",
                    description: Text("This drill isn't in the current build. Go back and continue from the next question.")
                )
            }
        }
        .navigationTitle(sessionCoordinator.filterDescription)
        .navigationBarTitleDisplayMode(.inline)
        .hidesStudySelector()
        .onAppear {
            if openedSessionID == nil { openedSessionID = sessionCoordinator.sessionID }
        }
        .onChange(of: sessionCoordinator.currentIndex) { _, newValue in
            if newValue >= sessionCoordinator.questionIDs.count, !sessionCoordinator.questionIDs.isEmpty {
                showSummary = true
            }
        }
        .onChange(of: sessionCoordinator.sessionID) { _, newValue in
            guard let openedSessionID, openedSessionID != newValue else { return }
            dismiss()
        }
        // Same as the question runner: record as you go, so abandoning a drill
        // session still leaves a row behind.
        .onChange(of: sessionCoordinator.completedAttemptIDs.count) { _, _ in
            sessionCoordinator.persist(into: modelContext)
        }
        .onChange(of: sessionCoordinator.skippedQuestionIDs.count) { _, _ in
            sessionCoordinator.persist(into: modelContext)
        }
    }

    private var debrief: SessionDebrief {
        let byID = Dictionary(uniqueKeysWithValues: attempts.map { ($0.id, $0) })
        let rows = sessionCoordinator.completedAttemptIDs.compactMap { id in
            byID[id].map { SessionDebrief.row(attempt: $0, content: content) }
        }
        return SessionDebrief.snapshot(rows: rows)
    }

    private func retryMissed() {
        var ids = debrief.missedIDs
        for id in sessionCoordinator.skippedQuestionIDs where !ids.contains(id) {
            ids.append(id)
        }
        guard !ids.isEmpty else { return }
        sessionCoordinator.persist(into: modelContext)
        let next = UUID()
        openedSessionID = next
        sessionCoordinator.retryMissed(questionIDs: ids, sessionID: next)
        showSummary = false
    }
}
