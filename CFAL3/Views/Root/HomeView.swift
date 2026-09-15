import SwiftUI
import SwiftData

struct HomeView: View {
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

    /// One computation feeds both the card's numbers and the session it
    /// starts, so they cannot disagree.
    private var reviewPlan: ReviewQueue.Plan {
        ReviewQueue.plan(
            cards: reviewCards,
            attempts: attempts,
            dailyNewLimit: practicePref.dailyNewLimit,
            isEligible: ReviewQueue.eligibility(
                content: content,
                typeFilter: practicePref.typeFilter
            )
        )
    }

    private var weakestTopics: [TopicProgress] {
        ProgressStats.weakestTopics(content: content, attempts: attempts)
    }

    private var overallStats: (attempted: Int, unique: Int, total: Int, correctRate: Double, avgSeconds: Double) {
        ProgressStats.overallStats(
            attempts: attempts,
            totalQuestions: content.totalBankAndDrillQuestions
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCaption
                reviewCTACard(reviewPlan)
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
            // Plan lost its tab, so it needs an entry point that exists even on
            // a rest day or a build with no schedule — cases where the card
            // below renders nothing.
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    PlanView()
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Study plan")
            }
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

    private func reviewCTACard(_ plan: ReviewQueue.Plan) -> some View {
        Button {
            startReviewSession(plan)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(reviewTitle(plan))
                    .font(.headline)
                Text(reviewSubtitle(plan))
                    .font(.caption)
                if plan.notStartedCount > 0 && plan.dueCount > 0 {
                    Text("\(plan.notStartedCount.formatted()) not started")
                        .font(.caption2)
                        .opacity(0.8)
                }
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
        // The payload itself is the gate, so an enabled card always runs.
        .disabled(plan.isEmpty)
    }

    private func reviewTitle(_ plan: ReviewQueue.Plan) -> String {
        if plan.dueCount > 0 && plan.newInSession > 0 {
            return "Start review · \(plan.dueCount.formatted()) due · \(plan.newInSession) new"
        }
        if plan.dueCount > 0 { return "Start review · \(plan.dueCount.formatted()) due" }
        if plan.newInSession > 0 { return "Start studying · \(plan.newInSession) new" }
        if plan.isNewExhausted { return "Today's new questions are done" }
        // Never claim "caught up" before the deck has been seeded.
        if reviewCards.isEmpty && content.isLoaded { return "Preparing your review queue" }
        return "All caught up"
    }

    private func reviewSubtitle(_ plan: ReviewQueue.Plan) -> String {
        guard !plan.isEmpty else {
            if plan.isNewExhausted {
                return "\(plan.dailyNewLimit) new resume tomorrow · \(plan.notStartedCount.formatted()) not started"
            }
            return "Build a practice session instead"
        }
        // The estimate covers the capped slice, not the whole queue — say so,
        // or "3,115 due · ~66 min" reads as 3,115 questions in an hour.
        let minutes = max(5, Int(ceil(Double(plan.sessionIDs.count) * 1.1)))
        var parts = ["~\(minutes) min"]
        if plan.dueInSession > 0 && plan.newInSession > 0 {
            parts.append("\(plan.dueInSession) due + \(plan.newInSession) new")
        } else {
            parts.append("\(plan.sessionIDs.count) questions")
        }
        if plan.overflowDue > 0 { parts.append("\(plan.overflowDue.formatted()) more after this") }
        if practicePref.typeFilter != .mixed { parts.append(practicePref.typeFilter.displayName) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var todaysPlanCard: some View {
        if let schedule = content.schedule,
           let today = schedule.day(for: .now) {
            let delta = ScheduleProgress.delta(schedule: schedule, completions: dayCompletions)
            let isDone = dayCompletions.contains { $0.dateKey == today.date }

            NavigationLink {
                PlanView()
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
                            // The done-toggle is overlaid on this corner (a
                            // Button inside a NavigationLink label would never
                            // get the tap), so the hours have to yield its room.
                            .padding(.trailing, 26)
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
                value: "\(overallStats.unique.formatted())/\(overallStats.total.formatted())",
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


    private func startReviewSession(_ plan: ReviewQueue.Plan) {
        guard !plan.isEmpty else { return }
        sessionCoordinator.start(
            questionIDs: plan.sessionIDs,
            mode: .reviewDue,
            filterDescription: ReviewQueue.sessionLabel(for: plan)
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
