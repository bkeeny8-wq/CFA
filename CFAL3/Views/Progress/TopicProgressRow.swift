import SwiftUI

struct TopicProgressRow: View {
    let progress: TopicProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.name)
                if let w = ProgressDisplay.examWeights[progress.topicID] {
                    Text(w)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
                Spacer()
                Text("\(progress.attempted)/\(progress.total)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(Formatting.percent(progress.correctRate))
                Spacer()
                Text(Formatting.duration(seconds: Int(progress.averageSeconds.rounded())))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
