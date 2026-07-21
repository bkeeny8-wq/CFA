import SwiftUI
import SwiftData

private enum StudyReadingTab: String, Identifiable {
    case notes = "Notes"
    case drills = "Drills"
    case checklist = "Checklist"

    var id: String { rawValue }
}

/// Reading detail: ONE column on every device. Notes, drills, and the LOS
/// checklist are peer tabs — nothing permanently splits the screen. At
/// regular width the content centers inside the readable-width cap, so a
/// full-screen iPad reading is a wide, comfortable page rather than a
/// half-screen column fighting a pinned panel.
struct StudyReadingDetailView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var statuses: [LOSStudyStatus]
    @Query private var reviewCards: [ReviewCard]

    let area: CurriculumArea
    let reading: Reading
    var splitColumnVisibility: Binding<NavigationSplitViewVisibility>?

    @State private var selectedTab: StudyReadingTab = .notes

    init(
        area: CurriculumArea,
        reading: Reading,
        splitColumnVisibility: Binding<NavigationSplitViewVisibility>? = nil
    ) {
        self.area = area
        self.reading = reading
        self.splitColumnVisibility = splitColumnVisibility
    }

    private var notes: ReadingNotesEntry? {
        content.readingNotes(id: reading.id)
    }

    private var drillBundle: LOSDrillBundle? {
        content.drillBundle(forReading: reading.id)
    }

    private var readingProgress: ReadingStudyProgress {
        StudyPlannerStats.readingProgress(reading: reading, statuses: statuses)
    }

    private var availableTabs: [StudyReadingTab] {
        var tabs: [StudyReadingTab] = []
        if notes != nil { tabs.append(.notes) }
        if drillBundle != nil { tabs.append(.drills) }
        tabs.append(.checklist)
        return tabs
    }

    var body: some View {
        VStack(spacing: 0) {
            pillHeader
            tabPicker

            switch selectedTab {
            case .notes:
                if let notes {
                    ReadingNotesView(notes: notes, showsTopicArea: false)
                } else {
                    checklistContent
                }
            case .drills:
                if let drillBundle {
                    LOSDrillReadingView(reading: reading, bundle: drillBundle)
                } else {
                    checklistContent
                }
            case .checklist:
                checklistContent
            }
        }
        .navigationTitle(reading.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let splitColumnVisibility, horizontalSizeClass == .regular {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.snappy) {
                            splitColumnVisibility.wrappedValue =
                                splitColumnVisibility.wrappedValue == .detailOnly ? .all : .detailOnly
                        }
                    } label: {
                        Label(
                            splitColumnVisibility.wrappedValue == .detailOnly
                                ? "Show sidebar" : "Focus reading",
                            systemImage: splitColumnVisibility.wrappedValue == .detailOnly
                                ? "sidebar.left" : "arrow.up.left.and.arrow.down.right"
                        )
                    }
                }
            }
        }
        .onAppear {
            seedSelectedTab()
        }
    }

    // MARK: - Pieces

    private var pillHeader: some View {
        StudyReadingPillHeader(
            mastered: readingProgress.mastered,
            total: readingProgress.total,
            dueCount: StudyDisplay.dueCount(for: reading, cards: reviewCards)
        )
        .frame(maxWidth: LayoutMetrics.studyReadingMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var tabPicker: some View {
        if availableTabs.count > 1 {
            Picker("View", selection: $selectedTab) {
                ForEach(availableTabs) { tab in
                    Text(tabLabel(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: LayoutMetrics.studyReadingMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(12)
        }
    }

    /// The checklist reads like a page, not a sidebar: same readable-width
    /// cap and centering as the notes.
    private var checklistContent: some View {
        ScrollView {
            LOSChecklistPanel(area: area, reading: reading)
                .padding(12)
                .frame(maxWidth: LayoutMetrics.studyReadingMaxWidth)
                .frame(maxWidth: .infinity)
        }
    }

    private func seedSelectedTab() {
        guard !availableTabs.contains(selectedTab) else { return }
        selectedTab = availableTabs.first ?? .checklist
    }

    private func tabLabel(_ tab: StudyReadingTab) -> String {
        if tab == .drills, let count = drillBundle?.totalQuestions {
            return "Drills (\(count))"
        }
        return tab.rawValue
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
