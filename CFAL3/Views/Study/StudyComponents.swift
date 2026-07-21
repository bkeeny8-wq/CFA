import SwiftUI
import SwiftData

struct StudyMasteryHeaderCard: View {
    @Environment(ContentLoader.self) private var content

    let master: LOSMaster
    let statuses: [LOSStudyStatus]

    var body: some View {
        let overall = StudyPlannerStats.overall(master: master, statuses: statuses)
        let fraction = overall.total == 0 ? 0 : Double(overall.mastered) / Double(overall.total)

        HStack(alignment: .top, spacing: 12) {
            ProgressRing(fraction: fraction, size: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(overall.mastered)/\(overall.total) LOS mastered")
                    .font(.headline)

                if let next = StudyDisplay.nextLOS(master: master, statuses: statuses, content: content) {
                    Text("Next: R\(next.readingNumber) \(next.readingShortTitle) · LOS \(next.losLetter)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cfaCard()
    }
}

struct StudyAreaBookCard: View {
    let area: AreaStudyProgress
    let readingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ProgressDisplay.shortName(area.areaID, fallback: area.name))
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("\(area.mastered)/\(area.total) LOS · \(readingCount) readings")
                .font(.caption)
                .foregroundStyle(.secondary)
            MasteryBar(value: area.masteredFraction)
        }
        .cfaCard()
    }
}

struct StudyAreaBookGrid<Card: View>: View {
    let areas: [AreaStudyProgress]
    let master: LOSMaster
    @ViewBuilder let card: (CurriculumArea, AreaStudyProgress) -> Card

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(areas) { areaProgress in
                if let curriculumArea = master.areas.first(where: { $0.id == areaProgress.areaID }) {
                    card(curriculumArea, areaProgress)
                }
            }
        }
    }
}

struct StudyReadingRowCard: View {
    @Environment(ContentLoader.self) private var content

    let area: CurriculumArea
    let reading: Reading
    let statuses: [LOSStudyStatus]
    let attempts: [Attempt]
    let highlightInProgress: Bool

    private var progress: ReadingStudyProgress {
        StudyPlannerStats.readingProgress(reading: reading, statuses: statuses)
    }

    private var state: ReadingStudyState {
        StudyDisplay.readingState(reading: reading, statuses: statuses, attempts: attempts, content: content)
    }

    var body: some View {
        let losFraction = progress.total == 0 ? 0 : Double(progress.mastered) / Double(progress.total)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("R\(StudyDisplay.readingNumber(reading, content: content)) · \(StudyDisplay.readingShortTitle(reading, content: content))")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
                stateLabel
            }

            Text(captionLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            MasteryBar(value: losFraction)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(highlightInProgress ? Theme.accent.opacity(0.08) : Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(
                    highlightInProgress ? Theme.accent.opacity(0.35) : Theme.hairline,
                    lineWidth: highlightInProgress ? 1 : 0.5
                )
        )
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch state {
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.success)
        case .inProgress:
            Text("In progress")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.accent)
        case .notStarted:
            Text("Not started")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var captionLine: String {
        switch state {
        case .done, .inProgress:
            var line = "\(progress.mastered)/\(progress.total) LOS"
            if let accuracy = StudyDisplay.drillAccuracy(reading: reading, attempts: attempts, content: content) {
                line += " · \(Formatting.percent(accuracy)) drill acc."
            }
            return line
        case .notStarted:
            let drills = StudyDisplay.drillCount(for: reading, content: content)
            return "0/\(progress.total) LOS · \(drills) drills"
        }
    }
}

struct StudyReadingPillHeader: View {
    let mastered: Int
    let total: Int
    let dueCount: Int

    var body: some View {
        HStack(spacing: 8) {
            CapsuleBadge(text: "\(mastered)/\(total) LOS")
            if dueCount > 0 {
                Text("\(dueCount) questions due")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
                    .foregroundStyle(.secondary)
            }
        }
    }
}
