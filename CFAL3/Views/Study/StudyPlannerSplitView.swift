import SwiftUI
import SwiftData

/// Two-pane Notes library. Nested `NavigationSplitView` inside the Daybook
/// sidebar hid the books column the same way Cases used to.
struct StudyPlannerSplitView: View {
    var accessibilityHidden = false

    @Environment(ContentLoader.self) private var content
    @Query private var statuses: [LOSStudyStatus]
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]

    @State private var selectedAreaID: String?
    @State private var selectedReadingID: String?

    private var master: LOSMaster? { content.losMaster }

    private var selectedArea: CurriculumArea? {
        guard let selectedAreaID, let master else { return nil }
        return master.areas.first { $0.id == selectedAreaID }
    }

    private var selectedReading: Reading? {
        guard let selectedReadingID, let area = selectedArea else { return nil }
        return area.readings.first { $0.id == selectedReadingID }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                booksColumn
                    .frame(width: 320)
                    .accessibilityHidden(accessibilityHidden)
                Rectangle()
                    .fill(Theme.pine.opacity(0.1))
                    .frame(width: 1)
                    .ignoresSafeArea()
                readingsColumn
                    .accessibilityHidden(accessibilityHidden)
            }
            .background(Theme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: showReading) {
                if let area = selectedArea, let reading = selectedReading {
                    StudyReadingDetailView(area: area, reading: reading)
                        .toolbar(.visible, for: .navigationBar)
                }
            }
        }
        .onAppear { seedAreaIfNeeded() }
        .onChange(of: selectedAreaID) { _, _ in
            selectedReadingID = nil
        }
    }

    private var showReading: Binding<Bool> {
        Binding(
            get: { selectedReadingID != nil },
            set: { if !$0 { selectedReadingID = nil } }
        )
    }

    @ViewBuilder
    private var booksColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(Theme.serif(.largeTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("notes.library")
                Text("Book → reading → notes and LOS checklist.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dust)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if let master {
                let areas = StudyPlannerStats.areaProgress(master: master, statuses: statuses)
                ScrollView {
                    VStack(spacing: 12) {
                        StudyMasteryHeaderCard(master: master, statuses: statuses)
                        ForEach(areas) { areaProgress in
                            if let curriculumArea = master.areas.first(where: { $0.id == areaProgress.areaID }) {
                                Button {
                                    selectedAreaID = curriculumArea.id
                                } label: {
                                    StudyAreaBookCard(
                                        area: areaProgress,
                                        readingCount: curriculumArea.readings.count,
                                        selected: selectedAreaID == curriculumArea.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            } else if let error = content.loadError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Theme.copper)
                    .padding(20)
            } else {
                ProgressView("Loading curriculum…")
                    .padding(20)
            }
        }
        .background(Theme.paper)
    }

    @ViewBuilder
    private var readingsColumn: some View {
        if let area = selectedArea {
            let highlightedReadingID = StudyDisplay.firstInProgressReadingID(
                in: area,
                statuses: statuses,
                attempts: attempts,
                content: content
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(ProgressDisplay.shortName(area.id, fallback: area.name))
                    .font(Theme.serif(.title2, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(area.readings) { reading in
                            Button {
                                selectedReadingID = reading.id
                            } label: {
                                StudyReadingRowCard(
                                    area: area,
                                    reading: reading,
                                    statuses: statuses,
                                    attempts: attempts,
                                    highlightInProgress: reading.id == highlightedReadingID
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .background(Theme.paper)
        } else {
            ContentUnavailableView(
                "Select a book",
                systemImage: "books.vertical",
                description: Text("Choose a book to see its readings.")
            )
            .foregroundStyle(Theme.dust)
        }
    }

    private func seedAreaIfNeeded() {
        guard let master, !master.areas.isEmpty else { return }
        if selectedAreaID == nil {
            selectedAreaID = master.areas[0].id
        }
    }
}
