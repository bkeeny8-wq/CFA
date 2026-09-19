import SwiftUI
import SwiftData

struct TopicListView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var attempts: [Attempt]

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
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cases")
                        .font(Theme.serif(.largeTitle, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("cases.library")
                    Text("Open a case to read its vignette, then sit its questions as one timed set.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dust)
                }

                ParchmentGroup(title: "Books") {
                    CasesBookList(topics: content.questionBank?.topics ?? [], attempts: attempts)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
    }
}

/// Owns expand state so toggling a book does not recompute every topic’s
/// case progress.
private struct CasesBookList: View {
    let topics: [BankTopic]
    let attempts: [Attempt]
    @State private var expandedBookIDs: Set<String> = []

    var body: some View {
        ForEach(topics) { topic in
            let name = ProgressDisplay.shortName(topic.id, fallback: topic.shortName)
            let progress = ProgressStats.caseProgress(topic: topic, attempts: attempts)
            BookDisclosureSection(
                title: name,
                subtitle: "\(progress.total) case questions · \(Formatting.percent(progress.correctRate)) correct",
                trailing: ProgressDisplay.examWeights[topic.id],
                accessibilityID: "cases.book.\(name)",
                isExpanded: $expandedBookIDs[topic.id]
            ) {
                CaseBookItems(topicID: topic.id)
            }
        }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !selectedLOS.isEmpty {
                    Text("Filtered by \(selectedLOS.count) LOS")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                }
                Spacer()
                Button("Filter by LOS") {
                    showLOSFilter = true
                }
                .font(.caption)
                .foregroundStyle(Theme.pine)
                .accessibilityLabel("Filter by LOS")
            }
            .padding(.vertical, 8)

            if cases.isEmpty {
                Text(selectedLOS.isEmpty
                     ? "This book has no case studies yet."
                     : "No case in this book covers the selected LOS.")
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
                    .padding(.vertical, 8)
            } else {
                ForEach(cases) { caseStudy in
                    NavigationLink {
                        CaseDetailView(caseID: caseStudy.id)
                    } label: {
                        BookChildRow(
                            title: caseStudy.title,
                            subtitle: CaseStudyRowLabel.caption(for: caseStudy, attempts: attempts)
                        )
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
