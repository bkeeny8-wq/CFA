import SwiftUI

struct LOSCoverageView: View {
    let coverage: [LOSAreaCoverage]

    var body: some View {
        ForEach(coverage, id: \.areaID) { area in
            Section(area.areaName) {
                ForEach(area.readings, id: \.readingID) { reading in
                    DisclosureGroup {
                        ForEach(reading.items) { item in
                            losRow(item)
                        }
                    } label: {
                        readingLabel(reading)
                    }
                }
            }
        }
    }

    private func readingLabel(_ reading: LOSReadingCoverage) -> some View {
        let tier = coverageTier(
            attempted: reading.attempted,
            total: reading.questionCount,
            rate: reading.correctRate
        )
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(reading.readingName)
                    .font(.subheadline)
                Text("\(reading.attempted)/\(reading.questionCount) attempted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(tier.name, systemImage: tier.symbol)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(coverageColor(tier.name))
                .frame(width: 28, height: 28)
                .accessibilityLabel("Coverage: \(tier.name)")
        }
    }

    private func losRow(_ item: LOSItemCoverage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.letter.uppercased())
                .font(.caption.weight(.semibold))
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayText)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.attempted)/\(item.questionCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "LOS \(item.letter.uppercased()). \(item.displayText). \(item.attempted) of \(item.questionCount) attempted"
        )
    }

    /// One classification, rendered as a shape AND a colour AND a spoken name.
    private func coverageTier(
        attempted: Int,
        total: Int,
        rate: Double?
    ) -> (name: String, symbol: String) {
        guard total > 0 else { return ("no questions", "minus.circle") }
        let attemptRatio = Double(attempted) / Double(total)
        let score = attemptRatio * (rate ?? 0.5)
        if score >= 0.75 { return ("strong", "checkmark.circle.fill") }
        if score >= 0.4 { return ("partial", "circle.lefthalf.filled") }
        if attemptRatio > 0 { return ("weak", "exclamationmark.circle") }
        return ("not started", "circle")
    }

    private func coverageColor(_ name: String) -> Color {
        switch name {
        case "strong": return .green
        case "partial": return .yellow
        case "weak": return .orange
        default: return .secondary
        }
    }
}
