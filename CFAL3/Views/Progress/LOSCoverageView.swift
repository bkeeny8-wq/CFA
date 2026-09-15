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
                        // Colour alone cannot carry this: the green/yellow/
                        // orange tiers are indistinguishable with the common
                        // forms of colour blindness, and VoiceOver read the
                        // swatch as nothing at all.
                        Label(coverageTier(for: reading).name,
                              systemImage: coverageTier(for: reading).symbol)
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .foregroundStyle(coverageColor(for: reading))
                            .frame(width: 28, height: 28)
                            .accessibilityLabel("Coverage: \(coverageTier(for: reading).name)")
                    }
                }
            }
        }
    }

    /// One classification, rendered as a shape AND a colour AND a spoken name.
    private func coverageTier(
        for reading: LOSReadingCoverage
    ) -> (name: String, symbol: String) {
        guard reading.questionCount > 0 else { return ("no questions", "minus.circle") }
        let attemptRatio = Double(reading.attempted) / Double(reading.questionCount)
        let score = attemptRatio * (reading.correctRate ?? 0.5)
        if score >= 0.75 { return ("strong", "checkmark.circle.fill") }
        if score >= 0.4 { return ("partial", "circle.lefthalf.filled") }
        if attemptRatio > 0 { return ("weak", "exclamationmark.circle") }
        return ("not started", "circle")
    }

    private func coverageColor(for reading: LOSReadingCoverage) -> Color {
        switch coverageTier(for: reading).name {
        case "strong": return .green
        case "partial": return .yellow
        case "weak": return .orange
        default: return .secondary
        }
    }
}
