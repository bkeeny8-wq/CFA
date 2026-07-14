import SwiftUI
import SwiftData

struct CaseListView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    let topicID: String
    var initialLOSFilter: Set<String> = []
    var selectionMode: Bool = false
    var selectedCaseID: Binding<String?>? = nil

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
        Group {
            if selectionMode, let activeCaseSelection {
                caseList(selection: activeCaseSelection)
            } else {
                caseList(selection: nil)
            }
        }
        .navigationTitle(topic?.shortName ?? "Cases")
        .toolbar {
            Button("Filter by LOS") { showLOSFilter = true }
        }
        .sheet(isPresented: $showLOSFilter) {
            LOSFilterSheet(selectedLOS: $selectedLOS)
        }
        .onAppear {
            if !initialLOSFilter.isEmpty && selectedLOS.isEmpty {
                selectedLOS = initialLOSFilter
            }
            if selectionMode, activeCaseSelection?.wrappedValue == nil, let first = cases.first {
                activeCaseSelection?.wrappedValue = first.id
            }
        }
        .onChange(of: cases.map(\.id)) { _, ids in
            guard selectionMode,
                  let binding = activeCaseSelection,
                  let current = binding.wrappedValue,
                  !ids.contains(current),
                  let first = ids.first else { return }
            binding.wrappedValue = first
        }
    }

    @ViewBuilder
    private func caseList(selection: Binding<String?>?) -> some View {
        if let selection {
            List(selection: selection) {
                caseRows
            }
        } else {
            List {
                caseRows
            }
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
            let stats = caseStats(caseStudy)
            let label = VStack(alignment: .leading, spacing: 4) {
                Text(caseStudy.title)
                    .font(.headline)
                Text("\(caseStudy.questions.count) questions · \(stats.answered) answered · \(Formatting.percent(stats.correctRate)) correct")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if selectionMode {
                label.tag(caseStudy.id as String?)
            } else {
                NavigationLink {
                    CaseDetailView(caseID: caseStudy.id)
                } label: {
                    label
                }
            }
        }
    }

    private func caseStats(_ caseStudy: CaseStudy) -> (answered: Int, correctRate: Double) {
        let ids = Set(caseStudy.questions.map(\.id))
        let caseAttempts = attempts.filter { ids.contains($0.questionId) }
        let answered = Set(caseAttempts.map(\.questionId)).count
        let gradable = caseAttempts.filter { $0.wasCorrect != nil }
        let correct = gradable.filter { $0.wasCorrect == true }.count
        let rate = gradable.isEmpty ? 0 : Double(correct) / Double(gradable.count)
        return (answered, rate)
    }
}
