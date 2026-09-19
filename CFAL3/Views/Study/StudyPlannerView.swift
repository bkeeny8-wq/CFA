import SwiftUI
import SwiftData

struct StudyPlannerView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var statuses: [LOSStudyStatus]
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]

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
            VStack(alignment: .leading, spacing: 18) {
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

                NotesBookList(master: master, areas: areas, statuses: statuses, attempts: attempts)
            }
            .padding(24)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
    }
}

/// Owns expand state so toggling a book does not rebuild the mastery card
/// or recompute every area’s progress.
private struct NotesBookList: View {
    @Environment(ContentLoader.self) private var content

    let master: LOSMaster
    let areas: [AreaStudyProgress]
    let statuses: [LOSStudyStatus]
    let attempts: [Attempt]
    @State private var expandedBookIDs: Set<String> = []

    var body: some View {
        ParchmentGroup(title: "Books") {
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
    }

    private func notesReadings(area: CurriculumArea) -> some View {
        VStack(spacing: 0) {
            ForEach(area.readings) { reading in
                let progress = StudyPlannerStats.readingProgress(reading: reading, statuses: statuses)
                let state = StudyDisplay.readingState(
                    reading: reading,
                    statuses: statuses,
                    attempts: attempts,
                    content: content
                )
                NavigationLink {
                    StudyReadingDetailView(area: area, reading: reading)
                } label: {
                    BookChildRow(
                        title: "R\(StudyDisplay.readingNumber(reading, content: content)) · \(StudyDisplay.readingShortTitle(reading, content: content))",
                        subtitle: "\(progress.mastered)/\(progress.total) LOS",
                        trailing: notesStateLabel(state)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("notes.reading.\(reading.id)")
            }
        }
    }

    private func notesStateLabel(_ state: ReadingStudyState) -> String {
        switch state {
        case .done: return "Done"
        case .inProgress: return "In progress"
        case .notStarted: return "Not started"
        }
    }
}
