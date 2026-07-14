import SwiftUI
import SwiftData

/// Three-column browse flow for iPad: topics → cases → case detail.
struct BrowseSplitView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    @State private var selectedTopicID: String?
    @State private var selectedCaseID: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            topicsColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } content: {
            casesColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { seedSelectionIfNeeded() }
        .onChange(of: selectedTopicID) { _, _ in
            selectedCaseID = nil
            if let topicID = selectedTopicID {
                let cases = content.cases(forTopic: topicID, losFilter: [])
                selectedCaseID = cases.first?.id
            }
        }
    }

    @ViewBuilder
    private var topicsColumn: some View {
        if let error = content.loadError {
            Text(error)
        } else {
            List(selection: $selectedTopicID) {
                ForEach(content.questionBank?.topics ?? []) { topic in
                    let progress = topicProgress(for: topic)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(topic.shortName)
                            .font(.headline)
                        Text("\(progress.attempted)/\(progress.total) attempted · \(Formatting.percent(progress.correctRate)) correct")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ProgressView(value: progress.total == 0 ? 0 : Double(progress.attempted) / Double(progress.total))
                            .tint(Theme.accent)
                    }
                    .padding(.vertical, 4)
                    .tag(topic.id as String?)
                }
            }
            .navigationTitle("Browse")
        }
    }

    @ViewBuilder
    private var casesColumn: some View {
        if let topicID = selectedTopicID, let topic = content.topic(id: topicID) {
            CaseListView(
                topicID: topicID,
                selectionMode: true,
                selectedCaseID: $selectedCaseID
            )
            .navigationTitle(topic.shortName)
        } else {
            ContentUnavailableView(
                "Select a topic",
                systemImage: "folder",
                description: Text("Choose a topic to browse its cases.")
            )
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let caseID = selectedCaseID {
            NavigationStack {
                CaseDetailView(caseID: caseID)
            }
        } else {
            ContentUnavailableView(
                "Select a case",
                systemImage: "doc.richtext",
                description: Text("Pick a case to read the vignette and practice questions.")
            )
        }
    }

    private func seedSelectionIfNeeded() {
        guard selectedTopicID == nil,
              let first = content.questionBank?.topics.first else { return }
        selectedTopicID = first.id
    }

    private func topicProgress(for topic: BankTopic) -> (attempted: Int, total: Int, correctRate: Double) {
        let questionIDs = Set(topic.cases.flatMap { $0.questions.map(\.id) })
        let topicAttempts = attempts.filter { questionIDs.contains($0.questionId) }
        let unique = Set(topicAttempts.map(\.questionId)).count
        let gradable = topicAttempts.filter { $0.wasCorrect != nil }
        let correct = gradable.filter { $0.wasCorrect == true }.count
        let rate = gradable.isEmpty ? 0 : Double(correct) / Double(gradable.count)
        return (unique, questionIDs.count, rate)
    }
}
