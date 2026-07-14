import SwiftUI
import SwiftData

struct StudyPlannerView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var statuses: [LOSStudyStatus]

    var body: some View {
        List {
            if let master = content.losMaster {
                let overall = StudyPlannerStats.overall(master: master, statuses: statuses)

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LOS Study Pal")
                            .font(.title2.bold())
                        Text("\(overall.mastered) of \(overall.total) statements mastered")
                        if overall.reviewing > 0 {
                            Text("\(overall.reviewing) in review")
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: overall.total == 0 ? 0 : Double(overall.mastered) / Double(overall.total))
                            .tint(Theme.accent)
                        Text("\(Formatting.daysUntilExam()) days until Feb 20, 2027")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Curriculum areas") {
                    ForEach(StudyPlannerStats.areaProgress(master: master, statuses: statuses)) { area in
                        if let curriculumArea = master.areas.first(where: { $0.id == area.areaID }) {
                            NavigationLink {
                                StudyAreaDetailView(area: curriculumArea)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(area.name)
                                        .font(.headline)
                                    Text("\(area.mastered)/\(area.total) mastered")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ProgressView(value: area.masteredFraction)
                                        .tint(Theme.accent)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                Section {
                    Text("Converted from your CFA Level 3 LOS Study Pal review sheet. Each reading includes your R01–R25 study notes plus an LOS checklist.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let error = content.loadError {
                Text(error)
            } else {
                ProgressView("Loading curriculum…")
            }
        }
        .navigationTitle("Study")
    }
}
