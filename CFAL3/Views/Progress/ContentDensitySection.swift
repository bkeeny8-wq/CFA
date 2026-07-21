import SwiftUI

struct ContentDensitySection: View {
    let rows: [ContentDensityProgress]

    private var grandHave: Int { rows.map(\.haveTotal).reduce(0, +) }
    private var grandTarget: Int { rows.map(\.targetTotal).reduce(0, +) }

    var body: some View {
        Section {
            LabeledContent("Bank + drills") {
                Text("\(grandHave.formatted()) / \(grandTarget.formatted())")
                    .foregroundStyle(grandHave >= grandTarget ? Theme.accent : .secondary)
            }
            LabeledContent("Essays in bank") {
                let have = rows.map(\.haveEssay).reduce(0, +)
                let target = rows.map(\.targetEssay).reduce(0, +)
                Text("\(have) / \(target)")
            }

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.areaName)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(row.examWeight)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    MasteryBar(value: row.totalProgress)
                    HStack {
                        Text("\(row.haveTotal) / \(row.targetTotal)")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("MC \(row.haveMC)/\(row.targetMC) · Essay \(row.haveEssay)/\(row.targetEssay)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Content density")
        } footer: {
            Text("Targets: ~2,765 questions (~75% MC, ~25% AI-graded essays). Depth varies by LOS and exam weight — not a fixed count per LOS.")
        }
    }
}
