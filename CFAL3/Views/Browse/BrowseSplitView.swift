import SwiftUI
import SwiftData

/// Three-column browse flow for iPad: topics → cases → case detail.
///
/// Interaction model mirrors Study: columns visible = browsing; TAPPING a
/// case = working it full screen. The collapse is driven by the tap callback
/// from CaseListView, never by selection-change detection, so re-tapping the
/// already-selected case also collapses. No case is ever auto-selected.
struct BrowseSplitView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    /// Non-nil when shown as the Practice tab's browse mode. The switcher has to
    /// live in the sidebar's own bar — an outer `.toolbar` cannot reach into a
    /// split view's columns.
    var practiceMode: Binding<PracticeMode>?

    @State private var selectedTopicID: String?
    @State private var selectedCaseID: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            topicsColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
                .toolbar(removing: .sidebarToggle)
        } content: {
            casesColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detailColumn
                .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            seedTopicIfNeeded()
        }
        .onChange(of: selectedTopicID) { _, _ in
            // Switching topics returns to browsing — never auto-open a case.
            selectedCaseID = nil
        }
    }

    // MARK: - Columns

    @ViewBuilder
    private var topicsColumn: some View {
        if let error = content.loadError {
            Text(error)
        } else {
            // Same book names, same exam-weight chips and same caption as the
            // compact layout in TopicListView — this is one screen, and which
            // rendering you get is only a matter of window width.
            List(selection: $selectedTopicID) {
                ForEach(content.questionBank?.topics ?? []) { topic in
                    let progress = ProgressStats.caseProgress(topic: topic, attempts: attempts)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(ProgressDisplay.shortName(topic.id, fallback: topic.shortName))
                                .font(.headline)
                            Spacer()
                            if let weight = ProgressDisplay.examWeights[topic.id] {
                                CapsuleBadge(text: weight)
                            }
                        }
                        Text("\(progress.total) case questions · \(Formatting.percent(progress.correctRate)) correct")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        MasteryBar(value: progress.total == 0 ? 0 : Double(progress.attempted) / Double(progress.total))
                    }
                    .padding(.vertical, 4)
                    .tag(topic.id as String?)
                }
            }
            .navigationTitle("Cases")
            .navigationBarTitleDisplayMode(practiceMode == nil ? .automatic : .inline)
            .toolbar {
                if let practiceMode {
                    ToolbarItem(placement: .principal) {
                        PracticeModePicker(mode: practiceMode)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var casesColumn: some View {
        if let topicID = selectedTopicID, let topic = content.topic(id: topicID) {
            CaseListView(
                topicID: topicID,
                selectionMode: true,
                selectedCaseID: $selectedCaseID,
                onCaseSelected: { _ in collapseToCase() }
            )
            .navigationTitle(ProgressDisplay.shortName(topic.id, fallback: topic.shortName))
            .toolbar {
                // Same principle as Study: switching books must not depend
                // on the topics column being on screen.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(content.questionBank?.topics ?? []) { candidate in
                            Button {
                                selectedTopicID = candidate.id
                            } label: {
                                let name = ProgressDisplay.shortName(
                                    candidate.id, fallback: candidate.shortName
                                )
                                if candidate.id == selectedTopicID {
                                    Label(name, systemImage: "checkmark")
                                } else {
                                    Text(name)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                    .accessibilityLabel("Switch book")
                }
            }
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
                CaseDetailView(
                    caseID: caseID,
                    splitColumnVisibility: $columnVisibility
                )
            }
        } else {
            ContentUnavailableView(
                "Select a case",
                systemImage: "doc.richtext",
                description: Text("Pick a case to read the vignette and practice questions.")
            )
        }
    }

    // MARK: - Interaction

    /// Tap = work the case. Collapse unconditionally at regular width.
    private func collapseToCase() {
        guard horizontalSizeClass == .regular else { return }
        withAnimation(.snappy) {
            columnVisibility = .detailOnly
        }
    }

    /// Only the TOPIC is seeded so the cases column has content on first
    /// launch. Cases are never auto-selected.
    private func seedTopicIfNeeded() {
        guard selectedTopicID == nil,
              let first = content.questionBank?.topics.first else { return }
        selectedTopicID = first.id
    }

}
