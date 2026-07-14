import SwiftUI

let progressExamWeights: [String: String] = [
    "asset_allocation": "15–20%",
    "portfolio_construction": "15–20%",
    "performance_measurement": "5–10%",
    "derivatives_and_risk_management": "10–15%",
    "ethical_and_professional_standards": "10–15%",
    "portfolio_management_pathway": "30–35%",
]

struct TopicProgressRow: View {
    let progress: TopicProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.name)
                if let w = progressExamWeights[progress.topicID] {
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
