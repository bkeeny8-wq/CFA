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
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(content.questionBank?.topics ?? []) { topic in
                        let progress = ProgressStats.caseProgress(topic: topic, attempts: attempts)
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
                                Text(ProgressDisplay.shortName(topic.id, fallback: topic.shortName))
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                // "case questions", not "questions": the Progress
                                // tab counts this book's drills too, and the two
                                // numbers must not read as the same measure.
                                Text("\(progress.total) case questions · \(Formatting.percent(progress.correctRate)) correct")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .cfaCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                Label(
                    "Open a case to read its vignette, then work all of its questions as one timed item set.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("Vignettes")
    }

}
