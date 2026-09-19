import SwiftUI
import SwiftData

struct TopicListView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var attempts: [Attempt]
    @State private var expandedBookIDs: Set<String> = []

    var body: some View {
        Group {
            if let error = content.loadError {
                ContentUnavailableView(
                    "Content failed to load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                library
            }
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Cases")
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cases")
                        .font(Theme.serif(.largeTitle, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("cases.library")
                    Text("Open a case to read its vignette, then sit its questions as one timed set.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dust)
                }

                ForEach(content.questionBank?.topics ?? []) { topic in
                    let name = ProgressDisplay.shortName(topic.id, fallback: topic.shortName)
                    let progress = ProgressStats.caseProgress(topic: topic, attempts: attempts)
                    let weight = ProgressDisplay.examWeights[topic.id]
                    BookDisclosureSection(
                        title: name,
                        subtitle: [
                            weight,
                            "\(progress.total) case questions · \(Formatting.percent(progress.correctRate)) correct"
                        ].compactMap { $0 }.joined(separator: " · "),
                        accessibilityID: "cases.book.\(name)",
                        isExpanded: $expandedBookIDs[topic.id]
                    ) {
                        CaseBookItems(topicID: topic.id)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
    }
}

/// Cases that belong to one book, shown only after that book is expanded.
private struct CaseBookItems: View {
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    let topicID: String

    @State private var selectedLOS: Set<String> = []
    @State private var showLOSFilter = false

    private var cases: [CaseStudy] {
        content.cases(forTopic: topicID, losFilter: selectedLOS)
    }

    private var filterSymbol: String {
        selectedLOS.isEmpty
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                if !selectedLOS.isEmpty {
                    Text("Filtered by \(selectedLOS.count) LOS")
                        .font(.footnote)
                        .foregroundStyle(Theme.dust)
                }
                Spacer()
                Button {
                    showLOSFilter = true
                } label: {
                    Image(systemName: filterSymbol)
                        .font(.body)
                        .foregroundStyle(Theme.pine)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Filter by LOS")
            }

            if cases.isEmpty {
                ContentUnavailableView(
                    "No cases match",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(selectedLOS.isEmpty
                        ? "This book has no case studies yet."
                        : "No case in this book covers the selected LOS. Sit that letter's drills from Study instead.")
                )
                .padding(.vertical, 12)
            } else {
                ForEach(cases) { caseStudy in
                    NavigationLink {
                        CaseDetailView(caseID: caseStudy.id)
                    } label: {
                        CaseStudyRowLabel(caseStudy: caseStudy, attempts: attempts)
                            .cfaCard(padding: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cases.item.\(caseStudy.id)")
                }
            }
        }
        .sheet(isPresented: $showLOSFilter) {
            LOSFilterSheet(selectedLOS: $selectedLOS, areaID: topicID)
        }
    }
}
