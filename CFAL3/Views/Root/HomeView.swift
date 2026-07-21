import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var selectedTab: AppTab

    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(PracticeBuilderPreference.self) private var practicePref
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \ReviewCard.dueDate) private var reviewCards: [ReviewCard]
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]
    @Query private var losStatuses: [LOSStudyStatus]
    @Query private var dayCompletions: [DayCompletion]
    @Environment(\.modelContext) private var modelContext

    @State private var showSession = false
    @State private var showPractice = false

    private let reviewSessionCap = 60

    private var dueToday: Int {
        reviewCards.filter { $0.dueDate <= .now }.count
    }

    private var weakestTopics: [TopicProgress] {
        ProgressStats.weakestTopics(content: content, attempts: attempts)
    }

    private var overallStats: (attempted: Int, unique: Int, correctRate: Double, avgSeconds: Double) {
        ProgressStats.overallStats(attempts: attempts, totalQuestions: content.totalQuestions)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCaption
                reviewCTACard
                todaysPlanCard
                statCardsRow
                continueCard
                weakestChips
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 960 : .infinity)
        .frame(maxWidth: .infinity)
        .navigationTitle("Home")
        .navigationDestination(isPresented: $showSession) {
            SessionRunnerView()
        }
        .navigationDestination(isPresented: $showPractice) {
            PracticeBuilderView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private var headerCaption: some View {
        HStack {
            Label("\(Formatting.daysUntilExam()) days to exam", systemImage: "calendar")
            Spacer()
            Label("\(ProgressStats.streakDays(attempts: attempts))-day streak", systemImage: "flame")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var reviewCTACard: some View {
        let due = dueToday
        let sessionSize = min(due, reviewSessionCap)
        let minutes = max(5, Int(ceil(Double(sessionSize) * 1.1)))

        return Button {
            startReviewDue()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(due > 0 ? "Start review · \(due) due" : "All caught up")
                    .font(.headline)
                Text(due > 0
                     ? "~\(minutes) min · spaced repetition"
                     : "Build a practice session instead")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.accent.opacity(0.14))
            )
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .disabled(due == 0)
    }

    @ViewBuilder
    private var todaysPlanCard: some View {
        if let schedule = content.schedule,
           let today = schedule.day(for: .now) {
            let delta = ScheduleProgress.delta(schedule: schedule, completions: dayCompletions)
            let isDone = dayCompletions.contains { $0.dateKey == today.date }

            Button {
                selectedTab = .plan
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Today's plan")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Formatting.hours(today.hours))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if today.hours == 0 {
                        Text(today.note ?? "Rest day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(today.blocks) { block in
                            Text("\(block.start) · \(block.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if delta < -2 {
                        Text("\(Formatting.hours(abs(delta), precise: true)) to make up — schedule adds time, it never slips.")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .cfaCard()
            .overlay(alignment: .topTrailing) {
                Button {
                    toggleTodayCompletion(today, isDone: isDone)
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDone ? Theme.success : .secondary)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDone ? "Mark incomplete" : "Mark done")
            }
        }
    }

    private func toggleTodayCompletion(_ today: ScheduleDay, isDone: Bool) {
        if isDone, let existing = dayCompletions.first(where: { $0.dateKey == today.date }) {
            modelContext.delete(existing)
        } else if !isDone {
            modelContext.insert(DayCompletion(dateKey: today.date, completedHours: today.hours))
        }
        try? modelContext.save()
    }

    private var statCardsRow: some View {
        HStack(spacing: 10) {
            StatCard(
                value: Formatting.percent(overallStats.correctRate),
                label: "Accuracy"
            )
            StatCard(
                value: "\(overallStats.unique)/\(content.totalQuestions)",
                label: "Attempted"
            )
        }
    }

    @ViewBuilder
    private var continueCard: some View {
        if let item = continueStudyItem {
            NavigationLink {
                StudyReadingDetailView(area: item.area, reading: item.reading)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Continue \(item.shortTitle)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(item.done)/\(item.total) LOS · \(item.area.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let losCaption = losStudiedCaption {
                        Text(losCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cfaCard()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var weakestChips: some View {
        if !weakestTopics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weakest topics")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(weakestTopics.prefix(3), id: \.topicID) { topic in
                        Button {
                            // Scope first, navigate second — mutating the
                            // preference from the destination's onAppear was
                            // fragile (re-fires can stomp in-progress edits).
                            practicePref.selectedTopics = [topic.topicID]
                            practicePref.selectedReadings = []
                            practicePref.selectedLOS = []
                            showPractice = true
                        } label: {
                            Text("\(ProgressDisplay.shortName(topic.topicID, fallback: topic.name)) \(Int((topic.correctRate * 100).rounded()))%")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Theme.warning.opacity(0.15))
                                )
                                .foregroundStyle(Theme.warning.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var losStudiedCaption: String? {
        guard let master = content.losMaster else { return nil }
        let overall = StudyPlannerStats.overall(master: master, statuses: losStatuses)
        let studied = overall.mastered + overall.reviewing
        return "\(studied)/\(overall.total) LOS studied"
    }

    private struct ContinueStudyItem {
        let area: CurriculumArea
        let reading: Reading
        let shortTitle: String
        let done: Int
        let total: Int
    }

    private var continueStudyItem: ContinueStudyItem? {
        guard let master = content.losMaster else { return nil }

        if let latest = losStatuses.max(by: { $0.updatedAt < $1.updatedAt }),
           latest.studyState != .notStarted,
           let match = readingMatch(readingID: latest.readingId, areaID: latest.areaId, master: master) {
            let prog = StudyPlannerStats.readingProgress(reading: match.reading, statuses: losStatuses)
            let done = prog.mastered + prog.reviewing
            return ContinueStudyItem(
                area: match.area,
                reading: match.reading,
                shortTitle: readingShortTitle(match.reading),
                done: done,
                total: prog.total
            )
        }

        for attempt in attempts {
            if let readingID = content.question(id: attempt.questionId)?.primaryReadingIDs.first,
               let match = readingMatch(readingID: readingID, areaID: nil, master: master) {
                let prog = StudyPlannerStats.readingProgress(reading: match.reading, statuses: losStatuses)
                let done = prog.mastered + prog.reviewing
                return ContinueStudyItem(
                    area: match.area,
                    reading: match.reading,
                    shortTitle: readingShortTitle(match.reading),
                    done: done,
                    total: prog.total
                )
            }
        }

        return nil
    }

    private func readingMatch(
        readingID: String,
        areaID: String?,
        master: LOSMaster
    ) -> (area: CurriculumArea, reading: Reading)? {
        for area in master.areas where areaID == nil || area.id == areaID {
            if let reading = area.readings.first(where: { $0.id == readingID }) {
                return (area, reading)
            }
        }
        return nil
    }

    private func readingShortTitle(_ reading: Reading) -> String {
        content.readingNotes(id: reading.id)?.title ?? reading.name
    }

    private func applyTypeFilter(_ ids: [String]) -> [String] {
        ids.filter { qid in
            if let q = content.question(id: qid) {
                return practicePref.typeFilter.allows(q.type)
                    && (q.type != .mc || q.canGradeMC)
            }
            if let d = content.drillQuestion(id: qid) {
                return practicePref.typeFilter.allows(d.type) && d.correct != nil
            }
            return false
        }
    }

    private func startReviewDue() {
        let due = reviewCards.filter { $0.dueDate <= .now }.map(\.questionId)
        let filtered = Array(applyTypeFilter(due).prefix(reviewSessionCap))
        guard !filtered.isEmpty else { return }
        sessionCoordinator.start(
            questionIDs: filtered,
            mode: .reviewDue,
            filterDescription: "Due review"
        )
        showSession = true
    }
}

/// Simple horizontal wrapping layout for topic chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
