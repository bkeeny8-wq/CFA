import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(PracticeBuilderPreference.self) private var practicePref
    @Environment(TabRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]
    @Query private var cards: [ReviewCard]
    @Query private var dayCompletions: [DayCompletion]

    @State private var selectedReadingID: String?
    @State private var selectedAreaID: String?

    var body: some View {
        let overall = ProgressStats.overallStats(
            attempts: attempts,
            totalQuestions: content.totalBankAndDrillQuestions
        )
        let topicProgress = ProgressStats.topicProgress(content: content, attempts: attempts, cards: cards)
        let coverage = ProgressStats.losCoverage(content: content, attempts: attempts)
        let visibleArea = selectedArea(in: coverage)
        let selected = selectedReading(in: visibleArea)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statTiles(overall: overall)
                HStack(alignment: .top, spacing: 18) {
                    losCoverageColumn(visibleArea, selected: selected)
                    inspector(selected)
                        .frame(width: horizontalSizeClass == .regular ? 280 : nil)
                }
                HStack(alignment: .top, spacing: 16) {
                    emptyCaseCallout(coverage)
                    bookGrid(topicProgress, coverage: coverage)
                }
                weeklySparkline
            }
            .padding(24)
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("progress.dashboard")
        .onAppear {
            seedSelection(coverage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Progress")
                .font(Theme.serif(.largeTitle, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Coverage is per LOS the stem actually tests.")
                .font(.subheadline)
                .foregroundStyle(Theme.dust)
        }
    }

    private func statTiles(
        overall: (attempted: Int, unique: Int, total: Int, correctRate: Double, avgSeconds: Double)
    ) -> some View {
        let finish = ReviewQueue.projectedFinishLine(
            notStarted: max(0, overall.total - overall.unique),
            dailyNewLimit: practicePref.dailyNewLimit
        )
        let delta: Double = {
            guard let schedule = content.schedule else { return 0 }
            return ScheduleProgress.delta(schedule: schedule, completions: dayCompletions)
        }()
        return HStack(spacing: 12) {
            progressTile(
                "Projected finish",
                finish?.replacingOccurrences(of: "Unseen finish ~", with: "") ?? "—",
                systemImage: "calendar"
            )
            progressTile(
                "Accuracy",
                ProgressStats.accuracyDisplay(attempts: attempts),
                systemImage: "target"
            )
            progressTile(
                "Attempted",
                "\(overall.unique.formatted()) of \(overall.total.formatted())",
                systemImage: "tray"
            )
            progressTile(
                delta < -0.5 ? "On pace" : "On pace",
                paceLabel(delta),
                systemImage: "clock",
                tint: delta < -0.5 ? Theme.copper : Theme.ink
            )
        }
    }

    private func paceLabel(_ delta: Double) -> String {
        if abs(delta) < 0.5 { return "On pace" }
        if delta > 0 { return "+\(Formatting.hours(delta, precise: true))" }
        return "−\(Formatting.hours(abs(delta), precise: true))"
    }

    private func progressTile(_ label: String, _ value: String, systemImage: String, tint: Color = Theme.ink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(Theme.dust)
            Text(value)
                .font(Theme.serif(.title3, weight: .semibold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardFill)
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
        )
    }

    private func losCoverageColumn(_ area: LOSAreaCoverage?, selected: LOSReadingCoverage?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("LOS coverage")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("progress.losCoverage")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let area {
                    let started = area.readings.filter { $0.attempted > 0 }.count
                    Text("\(started) of \(area.readings.count)")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                }
            }
            if let area {
                ForEach(area.readings, id: \.readingID) { reading in
                    Button {
                        selectedReadingID = reading.readingID
                    } label: {
                        pipRow(reading, selected: selected?.readingID == reading.readingID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pipRow(_ reading: LOSReadingCoverage, selected: Bool) -> some View {
        let filled = reading.items.filter { $0.attempted > 0 }.count
        let tier = pipTier(reading)
        return HStack(alignment: .top, spacing: 10) {
            Text(shortReadingName(reading))
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(tier)
                .font(.caption)
                .foregroundStyle(Theme.dust)
                .padding(.top, 2)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(reading.items) { item in
                        Circle()
                            .fill(item.attempted > 0 ? Theme.pine : Color.clear)
                            .overlay(Circle().stroke(Theme.pine.opacity(0.35), lineWidth: 1.2))
                            .frame(width: 9, height: 9)
                            .accessibilityLabel(
                                "LOS \(item.letter.uppercased()) \(item.attempted > 0 ? "attempted" : "not started")"
                            )
                    }
                }
                if selected {
                    Text("\(filled) of \(reading.items.count) LOS")
                        .font(.caption2)
                        .foregroundStyle(Theme.dust)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(filled) of \(reading.items.count) LOS attempted")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.sage : Color.clear)
        )
    }

    private func pipTier(_ reading: LOSReadingCoverage) -> String {
        guard reading.questionCount > 0 else { return "—" }
        if reading.attempted == 0 { return "not started" }
        let ratio = Double(reading.attempted) / Double(max(reading.questionCount, 1))
        if ratio >= 0.75 { return "strong" }
        if ratio >= 0.35 { return "partial" }
        return "weak"
    }

    private func shortReadingName(_ reading: LOSReadingCoverage) -> String {
        if let prefix = LOS.ethicsPipLabel(for: reading.readingID) {
            return prefix
        }
        if reading.readingID == "code_and_standards"
            || reading.readingID.contains("code_of_ethics")
            || reading.readingName.lowercased().contains("code of ethics") {
            return "Code of Ethics"
        }
        if reading.readingID.contains("application_of_code") {
            return "Application of the Code"
        }
        if reading.readingID.contains("asset_manager") {
            return "Asset Manager Code"
        }
        return reading.readingName
    }

    private func inspectorTitle(_ reading: LOSReadingCoverage) -> String {
        if let prefix = LOS.ethicsPipLabel(for: reading.readingID),
           let dot = prefix.firstIndex(of: ".") {
            let numeral = String(prefix[..<dot])
            let rest = prefix[prefix.index(after: dot)...].trimmingCharacters(in: .whitespaces)
            return "Standard \(numeral) — \(rest)"
        }
        return shortReadingName(reading)
    }

    @ViewBuilder
    private func inspector(_ reading: LOSReadingCoverage?) -> some View {
        if let reading {
            VStack(alignment: .leading, spacing: 12) {
                Text(inspectorTitle(reading))
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                ForEach(reading.items) { item in
                    HStack {
                        Circle()
                            .fill(item.attempted > 0 ? Theme.pine : Theme.pine.opacity(0.2))
                            .frame(width: 8, height: 8)
                        Text(".\(item.letter) \(item.displayText)")
                            .font(.caption)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                        Spacer()
                        Text(item.attempted == 0 ? "0 attempted" : "\(item.attempted) attempted")
                            .font(.caption2)
                            .foregroundStyle(Theme.dust)
                    }
                }
                Button {
                    drill(reading)
                } label: {
                    Label("Drill this LOS", systemImage: "hammer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryCTA())
                .disabled(content.drills(forLOS: (reading.items.first { $0.attempted == 0 } ?? reading.items.first)?.losID ?? "").isEmpty
                          && reading.questionCount == 0)
            }
            .cfaCard()
        }
    }

    private func drill(_ reading: LOSReadingCoverage) {
        let target = reading.items.first { $0.attempted == 0 } ?? reading.items.first
        guard let target else { return }
        var ids = content.drills(forLOS: target.losID).map(\.id)
        if ids.isEmpty {
            ids = content.questions(matchingLOS: [target.losID])
        }
        router.startQuestions(
            sessionCoordinator,
            ids: Array(ids.shuffled().prefix(20)),
            mode: .losDrill,
            description: "LOS \(target.letter.uppercased()) · \(shortReadingName(reading))"
        )
    }

    @ViewBuilder
    private func emptyCaseCallout(_ coverage: [LOSAreaCoverage]) -> some View {
        let match: (area: LOSAreaCoverage, reading: LOSReadingCoverage)? = {
            for area in coverage {
                if let reading = area.readings.first(where: { reading in
                    reading.caseQuestionCount == 0
                        && (reading.readingID.contains("swf") || reading.readingID.contains("endowment"))
                }) {
                    return (area, reading)
                }
            }
            return nil
        }()
        if let match {
            let started = match.area.readings.filter { $0.attempted > 0 }.count
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(ProgressDisplay.shortName(match.area.areaID, fallback: match.area.areaName))
                    Spacer()
                    Text("\(started) of \(match.area.readings.count)")
                }
                .font(.caption)
                .foregroundStyle(Theme.dust)
                Label(emptyReadingTitle(match.reading), systemImage: "scalemass")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("Drills and cards only. No case items tagged.")
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
                Button("Review cards") { router.selected = .cards }
                    .buttonStyle(.bordered)
                    .tint(Theme.pine)
            }
            .padding(16)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Theme.pine.opacity(0.35))
            )
            .frame(maxWidth: 280)
        }
    }

    private func emptyReadingTitle(_ reading: LOSReadingCoverage) -> String {
        if reading.readingID.contains("swf") { return "Sovereign Wealth Funds" }
        if reading.readingID.contains("endowment") { return "Endowment" }
        return reading.readingName
    }

    private func bookGrid(_ topics: [TopicProgress], coverage: [LOSAreaCoverage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Books")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(topics, id: \.topicID) { topic in
                    Button {
                        selectedAreaID = topic.topicID
                        selectedReadingID = coverage.first { $0.areaID == topic.topicID }?.readings.first?.readingID
                    } label: {
                        TopicProgressCard(
                            progress: topic,
                            selected: selectedAreaID == topic.topicID
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("A shared reading counts in both books.")
                .font(.caption2)
                .foregroundStyle(Theme.dust)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklySparkline: some View {
        let weeks = ProgressStats.weeklyVolumes(attempts: attempts)
        let current = weeks.last?.count ?? 0
        let previous = weeks.dropLast().last?.count ?? 0
        let delta: String
        if current == 0 && previous == 0 {
            delta = "no attempts yet"
        } else if current > previous {
            delta = "up from \(previous)"
        } else if current < previous {
            delta = "down from \(previous)"
        } else {
            delta = "level with \(previous)"
        }

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("This week")
                    .font(.subheadline.weight(.medium))
                Text("\(current) attempts · \(delta)")
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
            }
            Spacer()
            Chart(weeks) { week in
                LineMark(
                    x: .value("Week", week.id),
                    y: .value("Attempts", week.count)
                )
                .foregroundStyle(Theme.pine)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 120, height: 32)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week, \(current) attempts, \(delta)")
    }

    private func seedSelection(_ coverage: [LOSAreaCoverage]) {
        if selectedAreaID == nil {
            selectedAreaID = coverage.first { $0.areaID == "ethical_and_professional_standards" }?.areaID
                ?? coverage.first?.areaID
        }
        if selectedReadingID == nil, let area = selectedArea(in: coverage) {
            selectedReadingID = area.readings.first?.readingID
        }
    }

    private func selectedArea(in coverage: [LOSAreaCoverage]) -> LOSAreaCoverage? {
        if let id = selectedAreaID, let match = coverage.first(where: { $0.areaID == id }) {
            return match
        }
        return coverage.first { $0.areaID == "ethical_and_professional_standards" } ?? coverage.first
    }

    private func selectedReading(in area: LOSAreaCoverage?) -> LOSReadingCoverage? {
        guard let area else { return nil }
        if let id = selectedReadingID, let match = area.readings.first(where: { $0.readingID == id }) {
            return match
        }
        return area.readings.first
    }
}

private struct TopicProgressCard: View {
    let progress: TopicProgress
    var selected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "book")
                    .foregroundStyle(Theme.pine)
                Text(ProgressDisplay.shortName(progress.topicID, fallback: progress.name))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
            }
            MasteryBar(value: progress.total == 0 ? 0 : Double(progress.attempted) / Double(progress.total))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Theme.sage : Theme.cardFill)
                .shadow(color: Color.black.opacity(selected ? 0 : 0.04), radius: 8, y: 3)
        )
    }
}
