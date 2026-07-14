import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]
    @Query private var cards: [ReviewCard]

    var body: some View {
        List {
            let overall = ProgressStats.overallStats(
                attempts: attempts,
                totalQuestions: content.totalQuestions
            )

            Section("Overall") {
                LabeledContent("Total attempts", value: "\(overall.attempted)")
                LabeledContent("Unique questions", value: "\(overall.unique)/\(content.totalQuestions)")
                LabeledContent("Correctness", value: Formatting.percent(overall.correctRate))
                LabeledContent("Avg time", value: Formatting.duration(seconds: Int(overall.avgSeconds.rounded())))
            }

            Section("Topics") {
                ForEach(ProgressStats.topicProgress(content: content, attempts: attempts, cards: cards), id: \.topicID) { topic in
                    TopicProgressRow(progress: topic)
                }
            }

            LOSCoverageView(coverage: ProgressStats.losCoverage(content: content, attempts: attempts))

            if !ProgressStats.contentDensity(content: content).isEmpty {
                ContentDensitySection(rows: ProgressStats.contentDensity(content: content))
            }

            Section("Weekly volume") {
                Chart(ProgressStats.weeklyVolumes(attempts: attempts)) { week in
                    BarMark(
                        x: .value("Week", week.id),
                        y: .value("Attempts", week.count)
                    )
                    .foregroundStyle(Theme.accent)
                }
                .frame(height: horizontalSizeClass == .regular ? 220 : 180)
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: horizontalSizeClass == .regular ? 960 : .infinity)
        .frame(maxWidth: .infinity)
        .navigationTitle("Progress")
    }
}
