import SwiftUI

struct LOSCoverageView: View {
    let coverage: [LOSAreaCoverage]

    var body: some View {
        ForEach(coverage, id: \.areaID) { area in
            Section(area.areaName) {
                ForEach(area.readings, id: \.readingID) { reading in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reading.readingName)
                                .font(.subheadline)
                            Text("\(reading.attempted)/\(reading.questionCount) attempted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        coverageColor(for: reading)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private func coverageColor(for reading: LOSReadingCoverage) -> Color {
        guard reading.questionCount > 0 else { return Color.secondary.opacity(0.2) }
        let attemptRatio = Double(reading.attempted) / Double(reading.questionCount)
        let correctness = reading.correctRate ?? 0.5
        let score = attemptRatio * correctness
        if score >= 0.75 { return .green.opacity(0.7) }
        if score >= 0.4 { return .yellow.opacity(0.7) }
        if attemptRatio > 0 { return .orange.opacity(0.7) }
        return Color.secondary.opacity(0.25)
    }
}
