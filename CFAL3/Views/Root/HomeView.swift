import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(TabRouter.self) private var router
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(PracticeBuilderPreference.self) private var practicePref
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \ReviewCard.dueDate) private var reviewCards: [ReviewCard]
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]
    @Query private var losStatuses: [LOSStudyStatus]
    @Query private var dayCompletions: [DayCompletion]
    @Environment(\.modelContext) private var modelContext

    @State private var dayToken = 0

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
            VStack(alignment: .leading, spacing: 18) {
                if let error = content.loadError {
                    DaybookLoadErrorPanel(message: error) {
                        Task { await content.loadOffMainActor() }
                    }
                } else {
                    todayHeader
                    heroCard(reviewPlan)
                    oneTapRow
                    todaysPlanCard
                    continueCard
                    weakestChips
                    statsFooter
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 960 : .infinity)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            dayToken &+= 1
        }
    }

    private var todayHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(Theme.serif(.largeTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(todayDate)  ·  \(Formatting.daysUntilExam()) days to exam")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dust)
            }
            Spacer()
            let streak = ProgressStats.streakDays(attempts: attempts)
            if streak > 0 {
                Label("\(streak)-day streak", systemImage: "flame")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.pine)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.cardFill))
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
            }
        }
    }

    private var todayDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: .now)
    }

    private func heroCard(_ plan: ReviewQueue.Plan) -> some View {
        let inputs = ctaInputs(plan)
        return VStack(alignment: .leading, spacing: 14) {
            Text(ReviewCTA.heroHeadline(inputs))
                .font(Theme.serif(.title, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("home.review.title")
            Text(heroSubtitle(inputs))
                .font(.subheadline)
                .foregroundStyle(Theme.dust)
            Button {
                startReviewSession(plan)
            } label: {
                Text("Start sitting")
            }
            .buttonStyle(CompactCTA())
            .disabled(plan.isEmpty)
            .accessibilityIdentifier("home.startSitting")
            if !plan.isEmpty {
                Text("Choose types")
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
                    .accessibilityIdentifier("home.review.mix")
            }
            if plan.isEmpty && plan.isNewOff {
                Button("Turn on new questions in Settings") {
                    router.showSettings = true
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.pine)
            } else if plan.isEmpty && !inputs.isPreparing && content.loadError == nil {
                Button("Open Practice") {
                    router.selected = .practice
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.pine)
                .accessibilityIdentifier("home.review.openPractice")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.sage)
        )
    }

    private func heroSubtitle(_ inputs: ReviewCTA.Inputs) -> String {
        let plan = inputs.plan
        guard !plan.isEmpty else { return ReviewCTA.subtitle(inputs) }
        let minutes = max(5, Formatting.estimatedMinutes(
            mc: plan.sessionIDs.count - inputs.essaysInSession,
            essays: inputs.essaysInSession
        ))
        var parts = ["About \(minutes) minutes"]
        if inputs.essaysInSession > 0 {
            parts.append("includes \(inputs.essaysInSession) essay\(inputs.essaysInSession == 1 ? "" : "s")")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var oneTapRow: some View {
        HStack(spacing: 10) {
            oneTapPill(
                title: "Today's mix · \(reviewPlan.sessionIDs.count)",
                systemImage: "square.stack.3d.up",
                enabled: !reviewPlan.isEmpty,
                identifier: "home.mix"
            ) {
                startReviewSession(reviewPlan)
            }
            oneTapPill(
                title: "This reading's drills",
                systemImage: "pencil.and.outline",
                enabled: readingDrillIDs != nil,
                identifier: "home.drills"
            ) {
                startReadingDrills()
            }
            oneTapPill(
                title: "Sit a case",
                systemImage: "briefcase",
                enabled: caseToSit != nil,
                identifier: "home.case"
            ) {
                startCaseSitting()
            }
        }
    }

    private func oneTapPill(
        title: String,
        systemImage: String,
        enabled: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(Theme.cardFill)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var todaysPlanCard: some View {
        if let schedule = content.schedule,
           let today = schedule.day(for: .now) {
            let delta = ScheduleProgress.delta(schedule: schedule, completions: dayCompletions)
            let isDone = dayCompletions.contains { $0.dateKey == today.date }

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    router.selected = .plan
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Today's plan")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(Formatting.hours(today.hours))
                                .font(.subheadline)
                                .foregroundStyle(Theme.dust)
                                .padding(.trailing, today.isRestDay ? 0 : 28)
                        }

                        if today.isRestDay {
                            Text(today.note ?? "Rest day")
                                .font(.subheadline)
                                .foregroundStyle(Theme.dust)
                        } else {
                            ForEach(Array(today.blocks.enumerated()), id: \.element.id) { index, block in
                                HStack(spacing: 10) {
                                    timelineDot(index: index, count: today.blocks.count)
                                    Text("\(block.start)  ·  \(blockKindLabel(block))  ·  \(block.label)")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                }
                            }
                        }

                        if delta < -2 {
                            Label(
                                "\(Formatting.hours(abs(delta), precise: true)) to make up — schedule never slips.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(Theme.copper)
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .cfaCard()
            .overlay(alignment: .topTrailing) {
                if !today.isRestDay {
                    Button {
                        toggleTodayCompletion(today, isDone: isDone)
                    } label: {
                        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isDone ? Theme.pine : Theme.dust)
                            .padding(18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDone ? "Mark incomplete" : "Mark done")
                }
            }
        }
    }

    private func timelineDot(index: Int, count: Int) -> some View {
        VStack(spacing: 0) {
            Circle()
                .stroke(Theme.pine.opacity(0.45), lineWidth: 1.5)
                .frame(width: 10, height: 10)
            if index < count - 1 {
                Rectangle()
                    .fill(Theme.pine.opacity(0.2))
                    .frame(width: 1, height: 14)
            }
        }
        .frame(width: 10)
    }

    private func blockKindLabel(_ block: ScheduleBlock) -> String {
        switch block.kind {
        case .questions: return "Drills"
        case .review: return "Case"
        case .deep3, .study, .video: return "Notes"
        default:
            let lower = block.label.lowercased()
            if lower.contains("case") { return "Case" }
            if lower.contains("drill") || lower.contains("question") { return "Drills" }
            return "Notes"
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

    private func ctaInputs(_ plan: ReviewQueue.Plan) -> ReviewCTA.Inputs {
        ReviewCTA.Inputs(
            plan: plan,
            contentIsLoaded: content.isLoaded,
            contentFailed: content.loadError != nil,
            hasSeededCards: !reviewCards.isEmpty,
            typeFilter: practicePref.typeFilter,
            essaysInSession: plan.sessionIDs.filter { questionType(for: $0) == .essay }.count
        )
    }

    @ViewBuilder
    private var continueCard: some View {
        if let item = continueStudyItem {
            Button {
                router.selected = .notes
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Continue  ·  \(item.shortTitle)")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("\(item.done)/\(item.total) LOS · \(item.area.name)")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                    if !weakestTopics.isEmpty {
                        Text("Weak spots")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.copper)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .cfaCard()
        } else {
            Button {
                router.selected = .notes
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start a reading")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("No in-progress reading yet. Open Notes and pick the first module on the plan.")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .cfaCard()
            .accessibilityIdentifier("home.continue.empty")
        }
    }

    @ViewBuilder
    private var weakestChips: some View {
        if !weakestTopics.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(weakestTopics.prefix(3), id: \.topicID) { topic in
                    Button {
                        practicePref.selectedTopics = [topic.topicID]
                        practicePref.selectedReadings = []
                        practicePref.selectedLOS = []
                        router.selected = .practice
                    } label: {
                        Label(
                            ProgressDisplay.shortName(topic.topicID, fallback: topic.name),
                            systemImage: "arrow.left.arrow.right"
                        )
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().strokeBorder(Theme.copper.opacity(0.55), lineWidth: 1)
                        )
                        .foregroundStyle(Theme.copper)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statsFooter: some View {
        Button {
            router.selected = .progress
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                    Text(ProgressStats.accuracyDisplay(attempts: attempts))
                        .font(Theme.serif(.title3, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attempted")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                    Text("\(overallStats.unique.formatted()) of \(overallStats.total.formatted())")
                        .font(Theme.serif(.title3, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityIdentifier("home.progressLink")
        .accessibilityLabel("Open Progress")
        .accessibilityHint("Shows LOS coverage and pace")
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

    private var focusReading: Reading? {
        if let item = continueStudyItem { return item.reading }
        if let schedule = content.schedule, let today = schedule.day(for: .now) {
            for block in today.blocks {
                if let id = block.readingID, let match = content.reading(id: id) {
                    return match.reading
                }
            }
        }
        return content.losMaster?.areas.first?.readings.first
    }

    private var readingDrillIDs: [String]? {
        guard let reading = focusReading,
              let bundle = content.drillBundle(forReading: reading.id) else { return nil }
        let ids = bundle.drills.flatMap { $0.questions.map(\.id) }
        return ids.isEmpty ? nil : ids
    }

    private var caseToSit: CaseStudy? {
        let attempted = Set(attempts.map(\.questionId))
        let topics = content.questionBank?.topics ?? []
        for topic in topics {
            if let fresh = topic.cases.first(where: { study in
                study.questions.contains { !attempted.contains($0.id) }
            }) {
                return fresh
            }
        }
        return topics.first?.cases.first
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

    private func questionType(for id: String) -> QuestionType {
        if let q = content.question(id: id) { return q.type }
        if let d = content.drillQuestion(id: id) { return d.type }
        return .mc
    }

    private func startReviewSession(_ plan: ReviewQueue.Plan) {
        router.startQuestions(
            sessionCoordinator,
            ids: plan.sessionIDs,
            mode: .reviewDue,
            description: ReviewQueue.sessionLabel(for: plan)
        )
    }

    private func startReadingDrills() {
        guard let ids = readingDrillIDs, let reading = focusReading else { return }
        let session = Array(ids.shuffled().prefix(20))
        router.startQuestions(
            sessionCoordinator,
            ids: session,
            mode: .losDrill,
            description: "This reading's drills — \(reading.name)"
        )
    }

    private func startCaseSitting() {
        guard let study = caseToSit else { return }
        router.startQuestions(
            sessionCoordinator,
            ids: study.questions.map(\.id),
            mode: .random,
            description: "\(study.title)"
        )
    }
}

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
