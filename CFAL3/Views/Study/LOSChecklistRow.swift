import SwiftUI

struct LOSChecklistRow: View {
    let los: LOS
    let state: LOSStudyState
    let questionAttempted: Int
    let correctRate: Double?
    let essayCount: Int
    let onCycleState: () -> Void
    var onSitEssays: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onCycleState) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(iconColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(los.letter.uppercased()). \(los.displayText)")
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Text(state.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if questionAttempted > 0 {
                                Text("· \(questionAttempted) Q's")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let correctRate {
                                    Text("· \(Formatting.percent(correctRate))")
                                        .font(.caption)
                                        .foregroundStyle(correctRate >= 0.7 ? .green : .orange)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if let onSitEssays, essayCount > 0 {
                Button(action: onSitEssays) {
                    VStack(spacing: 2) {
                        Image(systemName: "pencil.and.list.clipboard")
                        Text("Sit essays")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Sit \(essayCount) essay\(essayCount == 1 ? "" : "s")")
                .accessibilityIdentifier("los.essays.\(los.id)")
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch state {
        case .notStarted: return "circle"
        case .reviewing: return "circle.lefthalf.filled"
        case .mastered: return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .notStarted: return .secondary
        case .reviewing: return .orange
        case .mastered: return .green
        }
    }
}
