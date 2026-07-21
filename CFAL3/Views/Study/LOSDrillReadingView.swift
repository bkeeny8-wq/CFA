import SwiftUI

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
                            .frame(minWidth: 34)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .background(
                                Capsule()
                                    .fill(selected ? Theme.accent.opacity(0.18) : Color(.systemGray6))
                            )
                            .foregroundStyle(selected ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
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
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator

    @State private var showSummary = false

    var body: some View {
        Group {
            if showSummary {
                List {
                    Section("Drill session") {
                        Text("\(sessionCoordinator.completedAttemptIDs.count) attempts")
                    }
                    Section {
                        Button("Done") {
                            sessionCoordinator.finish()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                }
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
            } else {
                ContentUnavailableView("Drill not found", systemImage: "questionmark")
            }
        }
        .navigationTitle(sessionCoordinator.filterDescription)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: sessionCoordinator.currentIndex) { _, newValue in
            if newValue >= sessionCoordinator.questionIDs.count, !sessionCoordinator.questionIDs.isEmpty {
                showSummary = true
            }
        }
    }
}
