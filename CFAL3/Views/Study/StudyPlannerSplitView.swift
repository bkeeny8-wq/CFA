import SwiftUI
import SwiftData

/// Three-column study planner for iPad: areas → readings → notes / drills / checklist.
struct StudyPlannerSplitView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var statuses: [LOSStudyStatus]

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
        } content: {
            readingsColumn
                .navigationSplitViewColumnWidth(min: 240, ideal: 270)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { seedSelectionIfNeeded() }
        .onChange(of: selectedAreaID) { _, _ in
            if let area = selectedArea {
                if !area.readings.contains(where: { $0.id == selectedReadingID }) {
                    selectedReadingID = area.readings.first?.id
                }
            } else {
                selectedReadingID = nil
            }
        }
    }

    @ViewBuilder
    private var areasColumn: some View {
        if let master {
            let overall = StudyPlannerStats.overall(master: master, statuses: statuses)
            List(selection: $selectedAreaID) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LOS Study Pal")
                            .font(.title3.bold())
                        Text("\(overall.mastered) of \(overall.total) statements mastered")
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
                            .tag(curriculumArea.id as String?)
                        }
                    }
                }
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
            List(selection: $selectedReadingID) {
                let areaProgress = StudyPlannerStats.areaProgress(
                    master: LOSMaster(areas: [area], losFlat: area.readings.flatMap(\.los)),
                    statuses: statuses
                ).first

                Section {
                    Text("\(areaProgress?.mastered ?? 0)/\(areaProgress?.total ?? 0) LOS mastered")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Readings") {
                    ForEach(area.readings) { reading in
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
                        .tag(reading.id as String?)
                    }
                }
            }
            .navigationTitle(area.name)
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
                StudyReadingDetailView(area: area, reading: reading)
            }
        } else {
            ContentUnavailableView(
                "Select a reading",
                systemImage: "doc.text",
                description: Text("Pick a reading to open notes, drills, and the LOS checklist.")
            )
        }
    }

    private func seedSelectionIfNeeded() {
        guard let master, !master.areas.isEmpty else { return }
        if selectedAreaID == nil {
            selectedAreaID = master.areas[0].id
        }
        if selectedReadingID == nil, let area = selectedArea, !area.readings.isEmpty {
            selectedReadingID = area.readings[0].id
        }
    }
}
