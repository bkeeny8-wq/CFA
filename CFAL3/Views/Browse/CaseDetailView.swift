import SwiftUI
import SwiftData

struct CaseDetailView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var attempts: [Attempt]
    @Query private var cards: [ReviewCard]

    let caseID: String
    var splitColumnVisibility: Binding<NavigationSplitViewVisibility>?

    @State private var vignetteExpanded = true
    @State private var showSession = false

    init(
        caseID: String,
        splitColumnVisibility: Binding<NavigationSplitViewVisibility>? = nil
    ) {
        self.caseID = caseID
        self.splitColumnVisibility = splitColumnVisibility
    }

    private var caseStudy: CaseStudy? { content.caseStudy(id: caseID) }

    var body: some View {
        verticalLayout
        .navigationTitle(caseStudy?.title ?? "Case")
        .navigationDestination(isPresented: $showSession) {
            SessionRunnerView()
        }
        .toolbar {
            if let splitColumnVisibility, horizontalSizeClass == .regular {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation {
                            splitColumnVisibility.wrappedValue =
                                splitColumnVisibility.wrappedValue == .detailOnly ? .all : .detailOnly
                        }
                    } label: {
                        Label("Show sidebar", systemImage: "sidebar.left")
                    }
                }
            }
        }
        .onAppear {
            if UserDefaults.standard.object(forKey: "visited_\(caseID)") != nil {
                vignetteExpanded = false
            }
            UserDefaults.standard.set(true, forKey: "visited_\(caseID)")
            collapseSplitColumnsIfNeeded()
        }
    }

    private var verticalLayout: some View {
        ScrollView {
            if let caseStudy {
                VStack(alignment: .leading, spacing: 12) {
                    headerCard(caseStudy)
                    workCaseButton(caseStudy)
                    vignetteCard(caseStudy)
                    questionsSection(caseStudy)
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? LayoutMetrics.studyReadingMaxWidth : nil)
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }

    @ViewBuilder
    private func headerCard(_ caseStudy: CaseStudy) -> some View {
        let meta = caseMetadata(caseStudy)
        let bookName = ProgressDisplay.shortName(
            caseStudy.topicID,
            fallback: content.topic(id: caseStudy.topicID)?.shortName ?? "Case"
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(caseStudy.title)
                    .font(.headline)
                Spacer(minLength: 8)
                CapsuleBadge(text: bookName)
            }
            Text("\(meta.questionCount) questions · \(meta.essayCount) essays · ~\(meta.minutes) min")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cfaCard()
    }

    private func workCaseButton(_ caseStudy: CaseStudy) -> some View {
        Button {
            sessionCoordinator.start(
                questionIDs: caseStudy.questions.map(\.id),
                mode: .random,
                filterDescription: caseStudy.title
            )
            showSession = true
        } label: {
            Text("Work this case")
        }
        .buttonStyle(PrimaryCTA())
    }

    private func vignetteCard(_ caseStudy: CaseStudy) -> some View {
        VignetteView(vignette: caseStudy.vignette, isExpanded: $vignetteExpanded)
            .lineSpacing(horizontalSizeClass == .regular ? 3 : 0)
            .cfaCard()
    }

    @ViewBuilder
    private func questionsSection(_ caseStudy: CaseStudy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Questions")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(caseStudy.questions) { question in
                NavigationLink {
                    QuestionAttemptView(questionID: question.id, standalone: true)
                } label: {
                    QuestionRowLabel(
                        question: question,
                        attempts: attempts,
                        card: cards.first { $0.questionId == question.id }
                    )
                    .padding(10)
                    .cfaCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func caseMetadata(_ caseStudy: CaseStudy) -> (questionCount: Int, essayCount: Int, minutes: Int) {
        let essays = caseStudy.questions.filter { $0.type == .essay }.count
        let mc = caseStudy.questions.count - essays
        let minutes = Int(ceil(Double(mc) * 1.5 + Double(essays) * 4.0))
        return (caseStudy.questions.count, essays, minutes)
    }

    private func collapseSplitColumnsIfNeeded() {
        guard horizontalSizeClass == .regular,
              let splitColumnVisibility,
              splitColumnVisibility.wrappedValue != .detailOnly else { return }
        withAnimation {
            splitColumnVisibility.wrappedValue = .detailOnly
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
                Spacer()
                statusPill
            }
            Text(Formatting.truncatedStem(question.stem))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
