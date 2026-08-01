import SwiftUI
import SwiftData

/// Reading detail: ONE column on every device, showing the reading's notes.
/// At regular width the content centers inside the readable-width cap, so a
/// full-screen iPad reading is a wide, comfortable page rather than a
/// half-screen column fighting a pinned panel. Drills live in the Practice
/// tab, so they are not duplicated here.
struct StudyReadingDetailView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var statuses: [LOSStudyStatus]
    @Query private var reviewCards: [ReviewCard]

    let area: CurriculumArea
    let reading: Reading
    var splitColumnVisibility: Binding<NavigationSplitViewVisibility>?

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

    private var readingProgress: ReadingStudyProgress {
        StudyPlannerStats.readingProgress(reading: reading, statuses: statuses)
    }

    var body: some View {
        VStack(spacing: 0) {
            pillHeader

            if let notes {
                ReadingNotesView(notes: notes, showsTopicArea: false)
            } else {
                ContentUnavailableView(
                    "Notes coming soon",
                    systemImage: "doc.text",
                    description: Text("This reading doesn't have bundled notes yet.")
                )
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
