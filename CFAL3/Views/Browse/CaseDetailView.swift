import SwiftUI
import SwiftData

struct CaseDetailView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var attempts: [Attempt]
    @Query private var cards: [ReviewCard]

    let caseID: String
    @State private var vignetteExpanded = true

    private var caseStudy: CaseStudy? { content.caseStudy(id: caseID) }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .navigationTitle(caseStudy?.title ?? "Case")
        .onAppear {
            if UserDefaults.standard.object(forKey: "visited_\(caseID)") != nil {
                vignetteExpanded = false
            }
            UserDefaults.standard.set(true, forKey: "visited_\(caseID)")
        }
    }

    private var compactLayout: some View {
        List {
            caseContent
        }
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                if let caseStudy {
                    VignetteView(vignette: caseStudy.vignette, isExpanded: $vignetteExpanded)
                        .readableContentWidth()
                        .padding()
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            List {
                if caseStudy != nil {
                    Section("Questions") {
                        questionRows
                    }
                }
            }
            .frame(width: 400)
        }
    }

    @ViewBuilder
    private var caseContent: some View {
        if let caseStudy {
            Section {
                VignetteView(vignette: caseStudy.vignette, isExpanded: $vignetteExpanded)
            }

            Section("Questions") {
                questionRows
            }
        }
    }

    @ViewBuilder
    private var questionRows: some View {
        if let caseStudy {
            ForEach(caseStudy.questions) { question in
                NavigationLink {
                    QuestionAttemptView(questionID: question.id, standalone: true)
                } label: {
                    QuestionRowLabel(
                        question: question,
                        attempts: attempts,
                        card: cards.first { $0.questionId == question.id }
                    )
                }
            }
        }
    }
}

private struct QuestionRowLabel: View {
    let question: Question
    let attempts: [Attempt]
    let card: ReviewCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Q\(question.number)")
                    .font(.headline)
                if question.isIncomplete {
                    Text("⚠ Incomplete solution")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                statusPill
            }
            Text(Formatting.truncatedStem(question.stem))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusPill: some View {
        let stats = ProgressStats.cardStats(for: question.id, attempts: attempts, card: card)
        if stats.attempts == 0 {
            Text("Not attempted")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        } else if stats.correct > 0 {
            Text("Correct \(stats.correct)×")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
        } else {
            Text("Missed")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.15))
                .clipShape(Capsule())
        }
    }
}
