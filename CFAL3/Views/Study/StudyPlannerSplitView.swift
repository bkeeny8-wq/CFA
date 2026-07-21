import SwiftUI
import SwiftData

/// Three-column study planner for iPad: areas → readings → notes / drills / checklist.
///
/// Interaction model: columns visible = browsing; TAPPING a reading = reading.
/// Every tap on a reading row collapses to the full-screen detail — including
/// re-tapping the already-selected reading — because the collapse is driven by
/// the tap itself, never by selection *change* detection. No reading is ever
/// auto-selected, so the user always chooses when to enter full screen.
struct StudyPlannerSplitView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ContentLoader.self) private var content
    @Query private var statuses: [LOSStudyStatus]
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]

    @State private var selectedAreaID: String?
    @State private var selectedReadingID: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            areasColumn
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
                .toolbar(removing: .sidebarToggle)
        } content: {
            readingsColumn
                .navigationSplitViewColumnWidth(min: 240, ideal: 270)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detailColumn
                .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            seedAreaIfNeeded()
        }
        .onChange(of: selectedAreaID) { _, _ in
            // Switching areas never auto-opens a reading; clear a selection
            // that no longer belongs to the visible area.
            if let area = selectedArea {
                if !area.readings.contains(where: { $0.id == selectedReadingID }) {
                    selectedReadingID = nil
                }
            } else {
                selectedReadingID = nil
            }
        }
    }

    // MARK: - Columns

    @ViewBuilder
    private var areasColumn: some View {
        if let master {
            let areas = StudyPlannerStats.areaProgress(master: master, statuses: statuses)

            ScrollView {
                VStack(spacing: 12) {
                    StudyMasteryHeaderCard(master: master, statuses: statuses)

                    StudyAreaBookGrid(areas: areas, master: master) { curriculumArea, areaProgress in
                        Button {
                            selectedAreaID = curriculumArea.id
                        } label: {
                            StudyAreaBookCard(
                                area: areaProgress,
                                readingCount: curriculumArea.readings.count
                            )
                            .overlay {
                                if selectedAreaID == curriculumArea.id {
                                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                                        .strokeBorder(Theme.accent, lineWidth: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Study")
        } else if let error = content.loadError {
            Text(error)
        } else {
            ProgressView("Loading curriculum…")
        }
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

            List {
                Section {
                    ForEach(area.readings) { reading in
                        Button {
                            open(reading)
                        } label: {
                            StudyReadingRowCard(
                                area: area,
                                reading: reading,
                                statuses: statuses,
                                attempts: attempts,
                                highlightInProgress: reading.id == highlightedReadingID
                            )
                            .overlay {
                                if selectedReadingID == reading.id {
                                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                                        .strokeBorder(Theme.accent, lineWidth: 2)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(area.name)
            .toolbar {
                // Book switching must never depend on the areas column being
                // visible — the split view can resolve to two columns on its
                // own, which previously stranded the user inside one book.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(master?.areas ?? []) { candidate in
                            Button {
                                selectedAreaID = candidate.id
                            } label: {
                                if candidate.id == selectedAreaID {
                                    Label(candidate.name, systemImage: "checkmark")
                                } else {
                                    Text(candidate.name)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                    .accessibilityLabel("Switch book")
                }
            }
        } else {
            ContentUnavailableView(
                "Select an area",
                systemImage: "books.vertical",
                description: Text("Choose a curriculum area to see its readings.")
            )
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let area = selectedArea, let reading = selectedReading {
            NavigationStack {
                StudyReadingDetailView(
                    area: area,
                    reading: reading,
                    splitColumnVisibility: $columnVisibility
                )
            }
        } else {
            ContentUnavailableView(
                "Select a reading",
                systemImage: "doc.text",
                description: Text("Pick a reading to open notes, drills, and the LOS checklist.")
            )
        }
    }

    // MARK: - Interaction

    /// Tap = read. Sets the selection and, at regular width, collapses the
    /// columns unconditionally — same-row taps included.
    private func open(_ reading: Reading) {
        selectedReadingID = reading.id
        guard horizontalSizeClass == .regular else { return }
        withAnimation(.snappy) {
            columnVisibility = .detailOnly
        }
    }

    /// Only the AREA is seeded so the readings column has content on first
    /// launch. Readings are never auto-selected — entering full screen is
    /// always a user action.
    private func seedAreaIfNeeded() {
        guard let master, !master.areas.isEmpty else { return }
        if selectedAreaID == nil {
            selectedAreaID = master.areas[0].id
        }
    }
}
