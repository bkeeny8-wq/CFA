import SwiftUI
import SwiftData

struct TopicListView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    var body: some View {
        List {
            if let error = content.loadError {
                Text(error)
            } else {
                ForEach(content.questionBank?.topics ?? []) { topic in
                    let progress = topicProgress(for: topic)
                    NavigationLink {
                        CaseListView(topicID: topic.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(topic.shortName)
                                .font(.headline)
                            Text("\(progress.attempted)/\(progress.total) attempted · \(Formatting.percent(progress.correctRate)) correct")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ProgressView(value: progress.total == 0 ? 0 : Double(progress.attempted) / Double(progress.total))
                                .tint(Theme.accent)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Browse")
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
