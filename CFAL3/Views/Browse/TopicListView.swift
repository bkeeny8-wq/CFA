import SwiftUI
import SwiftData

struct TopicListView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            if let error = content.loadError {
                Text(error)
                    .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(content.questionBank?.topics ?? []) { topic in
                        let progress = topicProgress(for: topic)
                        NavigationLink {
                            CaseListView(topicID: topic.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    ProgressRing(
                                        fraction: progress.total == 0
                                            ? 0
                                            : Double(progress.attempted) / Double(progress.total)
                                    )
                                    Spacer()
                                    if let w = ProgressDisplay.examWeights[topic.id] {
                                        CapsuleBadge(text: w)
                                    }
                                }
                                Text(ProgressDisplay.shortName(topic.id, fallback: topic.shortName))
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text("\(progress.total) questions · \(Formatting.percent(progress.correctRate)) correct")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .cfaCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Cases")
    }

    private func topicProgress(for topic: BankTopic) -> (attempted: Int, total: Int, correctRate: Double) {
        let questionIDs = Set(topic.cases.flatMap { $0.questions.map(\.id) })
        let topicAttempts = attempts.filter { questionIDs.contains($0.questionId) }
        let unique = Set(topicAttempts.map(\.questionId)).count
        let gradable = topicAttempts.filter { $0.wasCorrect != nil }
        let correct = gradable.filter { $0.wasCorrect == true }.count
        let rate = gradable.isEmpty ? 0 : Double(correct) / Double(gradable.count)
        return (unique, questionIDs.count, rate)
    }
}
