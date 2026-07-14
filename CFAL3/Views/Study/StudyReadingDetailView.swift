import SwiftUI
import SwiftData

private enum StudyReadingTab: String, Identifiable {
    case notes = "Notes"
    case drills = "Drills"
    case checklist = "Checklist"

    var id: String { rawValue }
}

private enum StudyPrimaryPane: String, CaseIterable, Identifiable {
    case notes = "Notes"
    case drills = "Drills"

    var id: String { rawValue }
}

struct StudyReadingDetailView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let area: CurriculumArea
    let reading: Reading

    @State private var selectedTab: StudyReadingTab = .notes
    @State private var primaryPane: StudyPrimaryPane = .notes

    private var notes: ReadingNotesEntry? {
        content.readingNotes(id: reading.id)
    }

    private var drillBundle: LOSDrillBundle? {
        content.drillBundle(forReading: reading.id)
    }

    private var availableTabs: [StudyReadingTab] {
        var tabs: [StudyReadingTab] = []
        if notes != nil { tabs.append(.notes) }
        if drillBundle != nil { tabs.append(.drills) }
        tabs.append(.checklist)
        return tabs
    }

    private var useSplitLayout: Bool {
        horizontalSizeClass == .regular && availableTabs.count > 1
    }

    var body: some View {
        Group {
            if useSplitLayout {
                regularWidthLayout
            } else {
                compactLayout
            }
        }
        .navigationTitle(reading.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if notes != nil {
                selectedTab = .notes
                primaryPane = .notes
            } else if drillBundle != nil {
                selectedTab = .drills
                primaryPane = .drills
            } else {
                selectedTab = .checklist
            }
        }
    }

    // MARK: - iPad: notes/drills beside checklist

    private var regularWidthLayout: some View {
        GeometryReader { proxy in
            if proxy.size.width >= LayoutMetrics.studySideBySideMinWidth {
                HStack(spacing: 0) {
                    primaryColumn
                        .frame(maxWidth: .infinity)

                    Divider()

                    LOSChecklistPanel(area: area, reading: reading)
                        .frame(width: LayoutMetrics.studyChecklistWidth)
                }
            } else {
                compactLayout
            }
        }
        .toolbar {
            if notes != nil && drillBundle != nil {
                ToolbarItem(placement: .principal) {
                    Picker("Content", selection: $primaryPane) {
                        ForEach(StudyPrimaryPane.allCases) { pane in
                            Text(paneLabel(pane)).tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }
            }
        }
        .onChange(of: primaryPane) { _, newValue in
            selectedTab = newValue == .notes ? .notes : .drills
        }
    }

    @ViewBuilder
    private var primaryColumn: some View {
        switch primaryPane {
        case .notes:
            if let notes {
                ReadingNotesView(notes: notes)
            } else if let drillBundle {
                LOSDrillReadingView(reading: reading, bundle: drillBundle)
            } else {
                LOSChecklistPanel(area: area, reading: reading)
            }
        case .drills:
            if let drillBundle {
                LOSDrillReadingView(reading: reading, bundle: drillBundle)
            } else if let notes {
                ReadingNotesView(notes: notes)
            } else {
                LOSChecklistPanel(area: area, reading: reading)
            }
        }
    }

    // MARK: - iPhone: tabbed layout

    private var compactLayout: some View {
        VStack(spacing: 0) {
            if availableTabs.count > 1 {
                Picker("View", selection: $selectedTab) {
                    ForEach(availableTabs) { tab in
                        Text(tabLabel(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }

            switch selectedTab {
            case .notes:
                if let notes {
                    ReadingNotesView(notes: notes)
                } else {
                    LOSChecklistPanel(area: area, reading: reading)
                }
            case .drills:
                if let drillBundle {
                    LOSDrillReadingView(reading: reading, bundle: drillBundle)
                } else {
                    LOSChecklistPanel(area: area, reading: reading)
                }
            case .checklist:
                LOSChecklistPanel(area: area, reading: reading)
            }
        }
    }

    private func tabLabel(_ tab: StudyReadingTab) -> String {
        if tab == .drills, let count = drillBundle?.totalQuestions {
            return "Drills (\(count))"
        }
        return tab.rawValue
    }

    private func paneLabel(_ pane: StudyPrimaryPane) -> String {
        if pane == .drills, let count = drillBundle?.totalQuestions {
            return "Drills (\(count))"
        }
        return pane.rawValue
    }
}

/// Picks a topic that has cases matching the LOS filter, then opens case list.
struct StudyPracticeTopicPicker: View {
    @Environment(ContentLoader.self) private var content

    let losFilter: Set<String>
    let title: String

    var body: some View {
        List {
            if matchingTopics.isEmpty {
                ContentUnavailableView(
                    "No matching cases",
                    systemImage: "tray",
                    description: Text("No bundled questions are tagged with these LOS yet.")
                )
            } else {
                ForEach(matchingTopics, id: \.id) { topic in
                    NavigationLink {
                        CaseListView(topicID: topic.id, initialLOSFilter: losFilter)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.shortName)
                                .font(.headline)
                            Text("\(caseCount(topic)) cases with matching questions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var matchingTopics: [BankTopic] {
        content.questionBank?.topics.filter { topic in
            !content.cases(forTopic: topic.id, losFilter: losFilter).isEmpty
        } ?? []
    }

    private func caseCount(_ topic: BankTopic) -> Int {
        content.cases(forTopic: topic.id, losFilter: losFilter).count
    }
}
