import SwiftUI
import SwiftData

/// Reading detail: ONE column on every device, showing the reading's notes.
/// At regular width the content centers inside the readable-width cap, so a
/// full-screen iPad reading is a wide, comfortable page rather than a
/// half-screen column fighting a pinned panel. Daily drill work is one tap
/// from here; the Practice tab remains the custom builder.
struct StudyReadingDetailView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(TabRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var statuses: [LOSStudyStatus]
    @Query private var reviewCards: [ReviewCard]

    let area: CurriculumArea
    let reading: Reading
    var splitColumnVisibility: Binding<NavigationSplitViewVisibility>?

    @State private var showChecklist = false

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
            readingDrillsCTA
            checklistCTA

            if let notes {
                ReadingNotesView(notes: notes, showsTopicArea: false)
            } else {
                ContentUnavailableView(
                    "Notes coming soon",
                    systemImage: "doc.text",
                    description: Text("This reading doesn't have bundled notes yet. Use the drills and LOS checklist below until notes ship.")
                )
            }
        }
        .navigationTitle(reading.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showChecklist) {
            LOSChecklistPanel(area: area, reading: reading)
        }
        .toolbar {
            if let splitColumnVisibility, horizontalSizeClass == .regular {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withSittingAnimation(reduceMotion) {
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

    @ViewBuilder
    private var readingDrillsCTA: some View {
        if let bundle = content.drillBundle(forReading: reading.id),
           bundle.totalQuestions > 0 {
            Button {
                sessionCoordinator.start(
                    questionIDs: bundle.drills.flatMap { $0.questions.map(\.id) }.shuffled(),
                    mode: .losDrill,
                    filterDescription: "This reading's drills — \(reading.name)"
                )
                router.presentQuestionSitting()
            } label: {
                Text("This reading's drills")
            }
            .buttonStyle(PrimaryCTA())
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .frame(maxWidth: LayoutMetrics.studyReadingMaxWidth)
            .frame(maxWidth: .infinity)
            .accessibilityHint("\(bundle.totalQuestions) questions, shuffled")
        }
    }

    private var checklistCTA: some View {
        Button {
            showChecklist = true
        } label: {
            Text("LOS checklist")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(maxWidth: LayoutMetrics.studyReadingMaxWidth)
        .frame(maxWidth: .infinity)
        .accessibilityHint("Mark statements and sit tagged essays")
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
                    description: Text("No bundled case questions are tagged with these LOS yet. Sit the reading's drills instead.")
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
