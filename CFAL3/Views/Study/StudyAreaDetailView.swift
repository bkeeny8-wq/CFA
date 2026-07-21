import SwiftUI
import SwiftData

struct StudyAreaDetailView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var statuses: [LOSStudyStatus]
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]

    let area: CurriculumArea

    private var highlightedReadingID: String? {
        StudyDisplay.firstInProgressReadingID(
            in: area,
            statuses: statuses,
            attempts: attempts,
            content: content
        )
    }

    var body: some View {
        List {
            Section {
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
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(area.name)
    }
}
