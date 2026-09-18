import SwiftUI
import SwiftData

struct TopicListView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            if let error = content.loadError {
                ContentUnavailableView(
                    "Content failed to load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cases")
                        .font(Theme.serif(.largeTitle, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("cases.library")
                    Text("Open a case to read its vignette, then sit its questions as one timed set.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dust)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(content.questionBank?.topics ?? []) { topic in
                        let progress = ProgressStats.caseProgress(topic: topic, attempts: attempts)
                        let name = ProgressDisplay.shortName(topic.id, fallback: topic.shortName)
                        NavigationLink {
                            CaseListView(topicID: topic.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    ProgressRing(
                                        fraction: progress.total == 0
                                            ? 0
                                            : Double(progress.attempted) / Double(progress.total)
                                    )
                                    Spacer()
                                    if let w = ProgressDisplay.examWeights[topic.id] {
                                        CapsuleBadge(text: w)
                                    }
                                }
                                Text(name)
                                    .font(Theme.serif(.headline, weight: .semibold))
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.ink)
                                // "case questions", not "questions": the Progress
                                // tab counts this book's drills too, and the two
                                // numbers must not read as the same measure.
                                Text("\(progress.total) case questions · \(Formatting.percent(progress.correctRate)) correct")
                                    .font(.caption)
                                    .foregroundStyle(Theme.dust)
                            }
                            .cfaCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cases.book.\(name)")
                        .accessibilityLabel(name)
                    }
                }
                .padding()
            }
        }
        .background(Theme.paper)
        .navigationTitle("Cases")
    }

}
