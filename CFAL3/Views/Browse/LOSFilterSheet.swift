import SwiftUI

struct LOSFilterSheet: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLOS: Set<String>
    @State private var draftSelection: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(content.losMaster?.areas ?? []) { area in
                    Section(area.name) {
                        ForEach(area.readings) { reading in
                            ForEach(reading.los) { los in
                                Button {
                                    toggle(los.id)
                                } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: draftSelection.contains(los.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(Theme.accent)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(los.letter.uppercased()). \(los.text)")
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.leading)
                                            Text(reading.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter by LOS")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { draftSelection = [] }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        selectedLOS = draftSelection
                        dismiss()
                    }
                }
            }
            .onAppear { draftSelection = selectedLOS }
        }
    }

    private func toggle(_ id: String) {
        if draftSelection.contains(id) {
            draftSelection.remove(id)
        } else {
            draftSelection.insert(id)
        }
    }
}
