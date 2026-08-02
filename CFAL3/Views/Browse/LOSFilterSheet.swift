import SwiftUI

/// LOS filter, rebuilt: scoped to one book when opened from a topic (no more
/// all-curriculum dump), grouped by reading with per-reading select-all and
/// collapse, compact letter rows, and live selection counts so Apply always
/// shows what it is about to do.
struct LOSFilterSheet: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLOS: Set<String>
    /// When non-nil, only readings from this curriculum area are offered.
    var areaID: String? = nil
    /// When non-empty, only these readings are offered (finest scope — wins).
    var readingScope: Set<String> = []
    /// When non-empty, only readings from these books are offered.
    var topicScope: Set<String> = []

    @State private var draftSelection: Set<String> = []
    @State private var expandedReadings: Set<String> = []

    /// Readings to offer, narrowed by the active scope. Precedence: an explicit
    /// reading selection wins, then a book (topic/area) scope, otherwise all.
    private var readings: [Reading] {
        let all = (content.losMaster?.areas ?? []).flatMap(\.readings)
        if !readingScope.isEmpty {
            return all.filter { readingScope.contains($0.id) }
        }
        if !topicScope.isEmpty {
            return all.filter { topicScope.contains($0.areaID) }
        }
        if let areaID {
            return all.filter { $0.areaID == areaID }
        }
        return all
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(readings) { reading in
                    readingSection(reading)
                }
            }
            .navigationTitle("Filter by LOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        draftSelection = []
                    }
                    .disabled(draftSelection.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draftSelection.isEmpty
                           ? "Show all"
                           : "Apply (\(draftSelection.count))") {
                        selectedLOS = draftSelection
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftSelection = selectedLOS
                // Open the sections that already have selections so the
                // current filter is visible at a glance.
                expandedReadings = Set(
                    readings
                        .filter { r in r.los.contains { draftSelection.contains($0.id) } }
                        .map(\.id)
                )
                if expandedReadings.isEmpty, let first = readings.first {
                    expandedReadings = [first.id]
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func readingSection(_ reading: Reading) -> some View {
        let selectedCount = reading.los.filter { draftSelection.contains($0.id) }.count
        let allSelected = selectedCount == reading.los.count && !reading.los.isEmpty

        Section {
            if expandedReadings.contains(reading.id) {
                ForEach(reading.los) { los in
                    losRow(los)
                }
            }
        } header: {
            HStack(spacing: 8) {
                Button {
                    toggleExpanded(reading.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expandedReadings.contains(reading.id)
                              ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                        Text(reading.name)
                            .lineLimit(1)
                        if selectedCount > 0 {
                            Text("\(selectedCount)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.accent.opacity(0.15)))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(allSelected ? "None" : "All") {
                    if allSelected {
                        for los in reading.los { draftSelection.remove(los.id) }
                    } else {
                        for los in reading.los { draftSelection.insert(los.id) }
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            .textCase(nil)
        }
    }

    private func losRow(_ los: LOS) -> some View {
        Button {
            if draftSelection.contains(los.id) {
                draftSelection.remove(los.id)
            } else {
                draftSelection.insert(los.id)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(los.letter.uppercased())
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(draftSelection.contains(los.id)
                                      ? Theme.accent
                                      : Color(.systemGray5))
                    )
                    .foregroundStyle(draftSelection.contains(los.id) ? .white : .secondary)

                Text(los.text)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                Spacer()

                if draftSelection.contains(los.id) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleExpanded(_ id: String) {
        if expandedReadings.contains(id) {
            expandedReadings.remove(id)
        } else {
            expandedReadings.insert(id)
        }
    }
}
