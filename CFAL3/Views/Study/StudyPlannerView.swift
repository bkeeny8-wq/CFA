import SwiftUI
import SwiftData

struct StudyPlannerView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var statuses: [LOSStudyStatus]
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]
    @State private var expandedBookIDs: Set<String> = []

    var body: some View {
        Group {
            if let master = content.losMaster {
                library(master: master)
            } else if let error = content.loadError {
                ContentUnavailableView(
                    "Content failed to load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView("Loading curriculum…")
            }
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Notes")
    }

    private func library(master: LOSMaster) -> some View {
        let areas = StudyPlannerStats.areaProgress(master: master, statuses: statuses)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(Theme.serif(.largeTitle, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("notes.library")
                    Text("Book → reading → notes and LOS checklist.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dust)
                }

                StudyMasteryHeaderCard(master: master, statuses: statuses)

                ForEach(areas) { areaProgress in
                    if let curriculumArea = master.areas.first(where: { $0.id == areaProgress.areaID }) {
                        let name = ProgressDisplay.shortName(
                            areaProgress.areaID,
                            fallback: areaProgress.name
                        )
                        BookDisclosureSection(
                            title: name,
                            subtitle: "\(areaProgress.mastered)/\(areaProgress.total) LOS · \(curriculumArea.readings.count) readings",
                            accessibilityID: "notes.book.\(name)",
                            isExpanded: $expandedBookIDs[curriculumArea.id]
                        ) {
                            notesReadings(area: curriculumArea)
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
    }

    private func notesReadings(area: CurriculumArea) -> some View {
        let highlightedReadingID = StudyDisplay.firstInProgressReadingID(
            in: area,
            statuses: statuses,
            attempts: attempts,
            content: content
        )
        return VStack(spacing: 10) {
            ForEach(area.readings) { reading in
                NavigationLink {
                    StudyReadingDetailView(area: area, reading: reading)
                } label: {
                    StudyReadingRowCard(
                        area: area,
                        reading: reading,
                        statuses: statuses,
                        attempts: attempts,
                        highlightInProgress: reading.id == highlightedReadingID
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
