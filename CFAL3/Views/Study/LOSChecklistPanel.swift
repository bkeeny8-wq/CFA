import SwiftUI
import SwiftData

struct LOSChecklistPanel: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Query private var statuses: [LOSStudyStatus]
    @Query private var attempts: [Attempt]

    let area: CurriculumArea
    let reading: Reading
    var onOpenNotes: (() -> Void)?

    private var statusByLOS: [String: LOSStudyStatus] {
        Dictionary(uniqueKeysWithValues: statuses.map { ($0.losId, $0) })
    }

    private var notes: ReadingNotesEntry? {
        content.readingNotes(id: reading.id)
    }

    var body: some View {
        List {
            let progress = StudyPlannerStats.readingProgress(reading: reading, statuses: statuses)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(progress.mastered)/\(progress.total) mastered")
                        .font(.headline)
                    if progress.reviewing > 0 {
                        Text("\(progress.reviewing) reviewing")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    MasteryBar(value: progress.masteredFraction)
                }
                .padding(.vertical, 4)

                if let onOpenNotes, notes != nil {
                    Button(action: onOpenNotes) {
                        Label("Read study notes", systemImage: "doc.text.fill")
                    }
                }

                StudyPracticeButton(area: area, reading: reading)
            }

            Section("Learning outcome statements") {
                ForEach(reading.los) { los in
                    LOSChecklistRow(
                        los: los,
                        state: statusByLOS[los.id]?.studyState ?? .notStarted,
                        questionAttempted: StudyPlannerStats.questionStats(
                            losID: los.id,
                            content: content,
                            attempts: attempts
                        ).attempted,
                        correctRate: StudyPlannerStats.questionStats(
                            losID: los.id,
                            content: content,
                            attempts: attempts
                        ).correctRate,
                        onCycleState: { cycleState(for: los) }
                    )
                }
            }

            Section {
                Text("Tap a statement to cycle: Not started → Reviewing → Mastered")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cycleState(for los: LOS) {
        if let existing = statusByLOS[los.id] {
            switch existing.studyState {
            case .notStarted: existing.studyState = .reviewing
            case .reviewing: existing.studyState = .mastered
            case .mastered: existing.studyState = .notStarted
            }
        } else {
            let status = LOSStudyStatus(
                losId: los.id,
                readingId: reading.id,
                areaId: area.id,
                state: .reviewing
            )
            modelContext.insert(status)
        }
        try? modelContext.save()
    }
}

struct StudyPracticeButton: View {
    let area: CurriculumArea
    let reading: Reading

    @State private var showPractice = false

    var body: some View {
        Button {
            showPractice = true
        } label: {
            Label("Practice questions for this reading", systemImage: "questionmark.circle")
        }
        .navigationDestination(isPresented: $showPractice) {
            StudyPracticeTopicPicker(
                losFilter: Set(reading.los.map(\.id)),
                title: reading.name
            )
        }
    }
}
