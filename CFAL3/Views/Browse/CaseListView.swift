import SwiftUI
import SwiftData

struct CaseListView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    let topicID: String
    var initialLOSFilter: Set<String> = []
    var selectionMode: Bool = false
    var selectedCaseID: Binding<String?>? = nil
    /// Fired on EVERY tap of a case row in selection mode — including taps on
    /// the already-selected case. The split view uses this to collapse to the
    /// full-screen detail; selection-change detection cannot do that job.
    var onCaseSelected: ((String) -> Void)? = nil

    @State private var selectedLOS: Set<String> = []
    @State private var showLOSFilter = false
    @State private var internalSelectedCaseID: String?

    private var topic: BankTopic? { content.topic(id: topicID) }

    private var cases: [CaseStudy] {
        content.cases(forTopic: topicID, losFilter: selectedLOS)
    }

    private var activeCaseSelection: Binding<String?>? {
        selectionMode ? (selectedCaseID ?? $internalSelectedCaseID) : nil
    }

    var body: some View {
        List {
            caseRows
        }
        .navigationTitle(topic?.shortName ?? "Cases")
        .toolbar {
            Button {
                showLOSFilter = true
            } label: {
                Image(systemName: selectedLOS.isEmpty
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
            }
            .accessibilityLabel("Filter by LOS")
        }
        .sheet(isPresented: $showLOSFilter) {
            // topic IDs == curriculum area IDs since the six-book
            // restructure, so the sheet scopes to the book being browsed.
            LOSFilterSheet(selectedLOS: $selectedLOS, areaID: topicID)
        }
        .onAppear {
            if !initialLOSFilter.isEmpty && selectedLOS.isEmpty {
                selectedLOS = initialLOSFilter
            }
            // Intentionally NO auto-selection of a first case: entering the
            // full-screen detail is always a user tap, never a side effect.
        }
        .onChange(of: cases.map(\.id)) { _, ids in
            // If the LOS filter removes the selected case, return to browsing
            // rather than silently jumping to a different case.
            guard selectionMode,
                  let binding = activeCaseSelection,
                  let current = binding.wrappedValue,
                  !ids.contains(current) else { return }
            binding.wrappedValue = nil
        }
    }

    @ViewBuilder
    private var caseRows: some View {
        if !selectedLOS.isEmpty {
            Section {
                Text("Filtered by \(selectedLOS.count) LOS")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        ForEach(cases) { caseStudy in
            if selectionMode {
                Button {
                    activeCaseSelection?.wrappedValue = caseStudy.id
                    onCaseSelected?(caseStudy.id)
                } label: {
                    caseRowLabel(caseStudy)
                        .overlay {
                            if activeCaseSelection?.wrappedValue == caseStudy.id {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Theme.accent, lineWidth: 2)
                                    .padding(.vertical, -2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    CaseDetailView(caseID: caseStudy.id)
                } label: {
                    caseRowLabel(caseStudy)
                }
            }
        }
    }

    private func caseRowLabel(_ caseStudy: CaseStudy) -> some View {
        let meta = caseMetadata(caseStudy)
        return VStack(alignment: .leading, spacing: 3) {
            Text(caseStudy.title)
                .font(.body)
            Text("\(caseStudy.questions.count) questions · \(meta.essays) essays"
                 + " · \(meta.attempted)/\(meta.total) tried"
                 + (meta.accuracy.map { " · \(Formatting.percent($0))" } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func caseMetadata(_ caseStudy: CaseStudy) -> (essays: Int, attempted: Int, total: Int, accuracy: Double?) {
        let qIDs = Set(caseStudy.questions.map(\.id))
        let essays = caseStudy.questions.filter { $0.type == .essay }.count
        let mine = attempts.filter { qIDs.contains($0.questionId) }
        let attempted = Set(mine.map(\.questionId)).count
        let gradable = mine.filter { $0.wasCorrect != nil }
        let accuracy = gradable.isEmpty ? nil :
            Double(gradable.filter { $0.wasCorrect == true }.count) / Double(gradable.count)
        return (essays, attempted, qIDs.count, accuracy)
    }
}
