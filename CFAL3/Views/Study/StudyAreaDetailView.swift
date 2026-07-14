import SwiftUI
import SwiftData

struct StudyAreaDetailView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var statuses: [LOSStudyStatus]

    let area: CurriculumArea

    var body: some View {
        List {
            let areaProgress = StudyPlannerStats.areaProgress(
                master: LOSMaster(areas: [area], losFlat: area.readings.flatMap(\.los)),
                statuses: statuses
            ).first ?? AreaStudyProgress(areaID: area.id, name: area.name, total: 0, mastered: 0, reviewing: 0)

            Section {
                Text("\(areaProgress.mastered)/\(areaProgress.total) LOS mastered across \(area.readings.count) readings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: areaProgress.masteredFraction)
                    .tint(Theme.accent)
            }

            Section("Readings") {
                ForEach(area.readings) { reading in
                    NavigationLink {
                        StudyReadingDetailView(area: area, reading: reading)
                    } label: {
                        let rp = StudyPlannerStats.readingProgress(reading: reading, statuses: statuses)
                        let hasNotes = content.readingNotes(id: reading.id) != nil
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(reading.name)
                                    .font(.headline)
                                if hasNotes {
                                    Image(systemName: "doc.text.fill")
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            Text("\(rp.mastered)/\(rp.total) mastered")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: rp.masteredFraction)
                                .tint(Theme.accent)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(area.name)
    }
}
