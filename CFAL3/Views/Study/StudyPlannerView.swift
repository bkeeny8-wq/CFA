import SwiftUI
import SwiftData

struct StudyPlannerView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var statuses: [LOSStudyStatus]

    var body: some View {
        Group {
            if let master = content.losMaster {
                let areas = StudyPlannerStats.areaProgress(master: master, statuses: statuses)

                ScrollView {
                    VStack(spacing: 12) {
                        StudyMasteryHeaderCard(master: master, statuses: statuses)

                        StudyAreaBookGrid(areas: areas, master: master) { curriculumArea, areaProgress in
                            NavigationLink {
                                StudyAreaDetailView(area: curriculumArea)
                            } label: {
                                StudyAreaBookCard(
                                    area: areaProgress,
                                    readingCount: curriculumArea.readings.count
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            } else if let error = content.loadError {
                Text(error)
                    .padding()
            } else {
                ProgressView("Loading curriculum…")
            }
        }
        .navigationTitle("Study")
    }
}
