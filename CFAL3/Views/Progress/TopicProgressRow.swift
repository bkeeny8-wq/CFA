import SwiftUI

struct TopicProgressRow: View {
    let progress: TopicProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.name)
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
