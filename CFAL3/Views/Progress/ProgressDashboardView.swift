import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(PracticeBuilderPreference.self) private var practicePref
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]
    @Query private var cards: [ReviewCard]
    @State private var showSession = false

    var body: some View {
        let overall = ProgressStats.overallStats(
            attempts: attempts,
            totalQuestions: content.totalQuestions
        )
        let topicProgress = ProgressStats.topicProgress(content: content, attempts: attempts, cards: cards)
        let coverage = ProgressStats.losCoverage(content: content, attempts: attempts)
        let density = ProgressStats.contentDensity(content: content)
        let dueCount = ProgressStats.dueCountByTopic(cards: cards).values.reduce(0, +)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCaption
                statCards(overall: overall, dueCount: dueCount)
                bookGrid(topicProgress)
                weeklySparkline
                drillDownRows(coverage: coverage, density: density, overall: overall)
            }
            .padding()
            .frame(maxWidth: horizontalSizeClass == .regular ? 960 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Progress")
        .navigationDestination(isPresented: $showSession) {
            SessionRunnerView()
        }
    }

    private var headerCaption: some View {
        HStack(spacing: 12) {
            Label("\(Formatting.daysUntilExam()) days to exam", systemImage: "calendar")
            Label("\(ProgressStats.streakDays(attempts: attempts))-day streak", systemImage: "flame")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statCards(
        overall: (attempted: Int, unique: Int, correctRate: Double, avgSeconds: Double),
        dueCount: Int
    ) -> some View {
        HStack(spacing: 8) {
            StatCard(label: "Accuracy", value: Formatting.percent(overall.correctRate))
            StatCard(label: "Attempted", value: "\(overall.unique)/\(content.totalQuestions)")

            Button {
                startReviewDue()
            } label: {
                StatCard(label: "Due today", value: "\(dueCount)", isAccent: dueCount > 0)
            }
            .buttonStyle(.plain)
            .disabled(dueCount == 0)
        }
    }

    private func bookGrid(_ topics: [TopicProgress]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(topics, id: \.topicID) { topic in
                TopicProgressCard(progress: topic)
            }
        }
    }

    private var weeklySparkline: some View {
        let weeks = ProgressStats.weeklyVolumes(attempts: attempts)
        let current = weeks.last?.count ?? 0
        let previous = weeks.dropLast().last?.count ?? 0

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("This week")
                    .font(.subheadline.weight(.medium))
                Text("\(current) attempts · \(weeklyDelta(current: current, previous: previous))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Chart(weeks) { week in
                LineMark(
                    x: .value("Week", week.id),
                    y: .value("Attempts", week.count)
                )
                .foregroundStyle(Theme.accent)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 120, height: 32)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private func drillDownRows(
        coverage: [LOSAreaCoverage],
        density: [ContentDensityProgress],
        overall: (attempted: Int, unique: Int, correctRate: Double, avgSeconds: Double)
    ) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                LOSCoverageDetailView(coverage: coverage)
            } label: {
                DrillDownRow(
                    title: "LOS coverage",
                    value: losCoverageSummary(coverage),
                    systemImage: "checklist.checked"
                )
            }

            Divider()
                .padding(.leading, 44)

            NavigationLink {
                ContentDensityDetailView(rows: density, averageSeconds: overall.avgSeconds)
            } label: {
                DrillDownRow(
                    title: "Question inventory",
                    value: "\(content.totalQuestions.formatted()) questions",
                    systemImage: "shippingbox"
                )
            }
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private func losCoverageSummary(_ coverage: [LOSAreaCoverage]) -> String {
        let attempted = coverage.flatMap(\.readings).map(\.attempted).reduce(0, +)
        let total = coverage.flatMap(\.readings).map(\.questionCount).reduce(0, +)
        return "\(attempted)/\(total)"
    }

    private func weeklyDelta(current: Int, previous: Int) -> String {
        if current > previous { return "up from \(previous)" }
        if current < previous { return "down from \(previous)" }
        return "level with \(previous)"
    }

    private func startReviewDue() {
        let due = cards.filter { $0.dueDate <= .now }.map(\.questionId)
        let filtered = Array(applyTypeFilter(due).prefix(60))
        guard !filtered.isEmpty else { return }
        sessionCoordinator.start(
            questionIDs: filtered,
            mode: .reviewDue,
            filterDescription: "Due review"
        )
        showSession = true
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
}

private struct StatCard: View {
    let label: String
    let value: String
    var isAccent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(isAccent ? .white.opacity(0.85) : .secondary)
        }
        .foregroundStyle(isAccent ? .white : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isAccent ? Theme.accent : Color(.systemGray6))
        )
    }
}

private struct TopicProgressCard: View {
    let progress: TopicProgress

    private var shortName: String {
        switch progress.topicID {
        case "asset_allocation": return "Asset allocation"
        case "portfolio_construction": return "Portfolio constr."
        case "performance_measurement": return "Perf. measurement"
        case "derivatives_and_risk_management": return "Derivatives"
        case "ethical_and_professional_standards": return "Ethics"
        case "portfolio_management_pathway": return "PM pathway"
        default: return progress.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shortName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let w = progressExamWeights[progress.topicID] {
                    Text(w)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(.systemGray5)))
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(progress.attempted)/\(progress.total) · \(Formatting.percent(progress.correctRate))")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: progress.total == 0 ? 0 : Double(progress.attempted) / Double(progress.total))
                .tint(Theme.accent)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}

private struct DrillDownRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}

private struct LOSCoverageDetailView: View {
    let coverage: [LOSAreaCoverage]

    var body: some View {
        List {
            LOSCoverageView(coverage: coverage)
        }
        .navigationTitle("LOS coverage")
    }
}

private struct ContentDensityDetailView: View {
    let rows: [ContentDensityProgress]
    let averageSeconds: Double

    var body: some View {
        List {
            Section("Timing") {
                LabeledContent(
                    "Avg time",
                    value: Formatting.duration(seconds: Int(averageSeconds.rounded()))
                )
            }
            if !rows.isEmpty {
                ContentDensitySection(rows: rows)
            }
        }
        .navigationTitle("Question inventory")
    }
}
