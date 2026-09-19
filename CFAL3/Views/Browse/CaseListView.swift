import SwiftUI
import SwiftData

struct CaseListView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    let topicID: String
    var initialLOSFilter: Set<String> = []
    /// Daybook’s two-pane library hides the stack’s nav bar, so the LOS
    /// filter has to live in the pane itself.
    var hidesNavigationChrome: Bool = false
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
        VStack(alignment: .leading, spacing: 0) {
            if hidesNavigationChrome {
                inlineHeader
            }
            ScrollView {
                VStack(spacing: 10) {
                    if !selectedLOS.isEmpty {
                        Text("Filtered by \(selectedLOS.count) LOS")
                            .font(.footnote)
                            .foregroundStyle(Theme.dust)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if cases.isEmpty {
                        ContentUnavailableView(
                            "No cases match",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(selectedLOS.isEmpty
                                ? "This book has no case studies yet."
                                : "No case in this book covers the selected LOS. Sit that letter's drills from Study instead.")
                        )
                        .padding(.top, 24)
                    } else {
                        ForEach(cases) { caseStudy in
                            caseCard(caseStudy)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(Theme.paper)
        .navigationTitle(topic?.shortName ?? "Cases")
        .toolbar {
            if !hidesNavigationChrome {
                Button {
                    showLOSFilter = true
                } label: {
                    Image(systemName: filterSymbol)
                }
                .accessibilityLabel("Filter by LOS")
            }
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

    private var filterSymbol: String {
        selectedLOS.isEmpty
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
    }

    private var inlineHeader: some View {
        HStack {
            Text(topic.map { ProgressDisplay.shortName($0.id, fallback: $0.shortName) } ?? "Cases")
                .font(Theme.serif(.title2, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                showLOSFilter = true
            } label: {
                Image(systemName: filterSymbol)
                    .font(.title3)
                    .foregroundStyle(Theme.pine)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Filter by LOS")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func caseCard(_ caseStudy: CaseStudy) -> some View {
        let selected = activeCaseSelection?.wrappedValue == caseStudy.id
        if selectionMode {
            Button {
                activeCaseSelection?.wrappedValue = caseStudy.id
                onCaseSelected?(caseStudy.id)
            } label: {
                CaseStudyRowLabel(caseStudy: caseStudy, attempts: attempts)
                    .cfaCard(padding: 16)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .strokeBorder(Theme.pine, lineWidth: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                CaseDetailView(caseID: caseStudy.id)
            } label: {
                CaseStudyRowLabel(caseStudy: caseStudy, attempts: attempts)
                    .cfaCard(padding: 16)
            }
            .buttonStyle(.plain)
        }
    }
}

struct CaseStudyRowLabel: View {
    let caseStudy: CaseStudy
    let attempts: [Attempt]

    var body: some View {
        let meta = metadata
        VStack(alignment: .leading, spacing: 6) {
            Text(caseStudy.title)
                .font(Theme.serif(.headline, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("\(caseStudy.questions.count) questions · \(meta.essays) essays"
                 + " · \(meta.attempted)/\(meta.total) tried"
                 + (meta.accuracy.map { " · \(Formatting.percent($0))" } ?? ""))
                .font(.caption)
                .foregroundStyle(Theme.dust)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: (essays: Int, attempted: Int, total: Int, accuracy: Double?) {
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
