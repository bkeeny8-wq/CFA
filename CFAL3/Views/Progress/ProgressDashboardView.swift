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
            totalQuestions: content.totalBankAndDrillQuestions
        )
        let topicProgress = ProgressStats.topicProgress(content: content, attempts: attempts, cards: cards)
        let coverage = ProgressStats.losCoverage(content: content, attempts: attempts)
        let density = ProgressStats.contentDensity(content: content)
        let plan = ReviewQueue.plan(
            cards: cards,
            attempts: attempts,
            dailyNewLimit: practicePref.dailyNewLimit,
            isEligible: ReviewQueue.eligibility(
                content: content,
                typeFilter: practicePref.typeFilter
            )
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCaption
                statCards(overall: overall, plan: plan)
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
        overall: (attempted: Int, unique: Int, total: Int, correctRate: Double, avgSeconds: Double),
        plan: ReviewQueue.Plan
    ) -> some View {
        HStack(spacing: 8) {
            ProgressStatTile(label: "Accuracy", value: Formatting.percent(overall.correctRate))
            ProgressStatTile(
                label: "Attempted",
                value: "\(overall.unique.formatted())/\(overall.total.formatted())"
            )

            Button {
                startReviewSession(plan)
            } label: {
                // Show the session this tile actually starts, not the due
                // count: gating on plan.isEmpty while printing dueCount made
                // it read "0" in the accent colour and then run 20 questions.
                let tile = ReviewCTA.tile(for: plan)
                ProgressStatTile(
                    label: tile.label,
                    value: tile.value,
                    isAccent: !plan.isEmpty
                )
            }
            .buttonStyle(.plain)
            .disabled(plan.isEmpty)
        }
    }


    private func bookGrid(_ topics: [TopicProgress]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(topics, id: \.topicID) { topic in
                    TopicProgressCard(progress: topic)
                }
            }
            bookOverlapNote(topics)
        }
    }

    /// A reading shared by two books puts its drills in both, so the cards sum
    /// to more than the inventory above them. Each card is right on its own;
    /// say so rather than let the arithmetic look broken. Computed, so it
    /// disappears if the curriculum mapping ever stops overlapping.
    @ViewBuilder
    private func bookOverlapNote(_ topics: [TopicProgress]) -> some View {
        let overlap = topics.map(\.total).reduce(0, +) - content.totalBankAndDrillQuestions
        if overlap > 0 {
            Text("Books overlap by \(overlap.formatted()) questions — a reading that belongs to two books counts toward both, so these totals sum to more than the inventory.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        overall: (attempted: Int, unique: Int, total: Int, correctRate: Double, avgSeconds: Double)
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
                    value: "\(content.totalBankAndDrillQuestions.formatted()) questions",
                    systemImage: "shippingbox"
                )
            }
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    /// Shown as a percentage, not a fraction. A question tagged to three
    /// readings is counted once per reading — correct for the per-reading rows
    /// behind this one, but summing them yields reading-slots, not questions.
    /// Printing that sum put a third "total questions" number on this screen.
    private func losCoverageSummary(_ coverage: [LOSAreaCoverage]) -> String {
        let readings = coverage.flatMap(\.readings)
        let attempted = readings.map(\.attempted).reduce(0, +)
        let total = readings.map(\.questionCount).reduce(0, +)
        let fraction = total == 0 ? 0 : Double(attempted) / Double(total)
        return "\(Formatting.percent(fraction)) attempted"
    }

    private func weeklyDelta(current: Int, previous: Int) -> String {
        if current > previous { return "up from \(previous)" }
        if current < previous { return "down from \(previous)" }
        return "level with \(previous)"
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

private struct ProgressStatTile: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ProgressDisplay.shortName(progress.topicID, fallback: progress.name))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let w = ProgressDisplay.examWeights[progress.topicID] {
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
            MasteryBar(value: progress.total == 0 ? 0 : Double(progress.attempted) / Double(progress.total))
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
