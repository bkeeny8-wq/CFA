import SwiftUI
import SwiftData

struct LOSDrillAttemptView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var cards: [ReviewCard]

    let drill: DrillQuestion
    var standalone: Bool = true
    var sessionProgress: (current: Int, total: Int)?

    @State private var selectedOption: String?
    @State private var startedAt = Date()
    @State private var clockStarted = false
    @State private var submittedAttempt: Attempt?
    @State private var showResult = false

    private var question: Question { drill.asQuestion }
    private var reviewCard: ReviewCard? {
        cards.first { $0.questionId == drill.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let sessionProgress {
                    Text("\(sessionProgress.current) / \(sessionProgress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label("LOS Drill", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)

                Text(drill.stem)
                    .font(.body)

                MultipleChoiceInput(
                    options: drill.options ?? [:],
                    sortedKeys: question.sortedOptionKeys,
                    selected: $selectedOption
                )

                Button("Check answer") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(selectedOption == nil)
            }
            .readableContentWidth()
            .padding()
        }
        .navigationTitle("Drill Q\(drill.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFlag()
                } label: {
                    Image(systemName: reviewCard?.flaggedForReview == true ? "flag.fill" : "flag")
                }
                .accessibilityLabel(
                    reviewCard?.flaggedForReview == true
                        ? "Remove review flag"
                        : "Flag for review"
                )
            }
        }
        // First appearance only, exactly as in QuestionAttemptView. `onAppear`
        // fires again whenever this view comes back — from the result screen,
        // or from another tab — and restarting the clock there restarted the
        // pacing display mid-question and made durationSeconds count only from
        // the last reappearance. Drills are 2,667 of the 3,157 questions, so
        // fixing this in the bank view alone fixed the smaller half.
        .onAppear {
            if !clockStarted {
                startedAt = .now
                clockStarted = true
            }
        }
        .navigationDestination(isPresented: $showResult) {
            if let submittedAttempt {
                GradingResultView(
                    attempt: submittedAttempt,
                    question: question,
                    caseStudy: nil,
                    standalone: standalone
                )
            }
        }
    }

    private func submit() {
        let duration = max(1, Int(Date().timeIntervalSince(startedAt)))
        let wasCorrect = drill.correct.map { selectedOption == $0 }

        let attempt = Attempt(
            questionId: drill.id,
            caseId: DrillAttemptContext.caseId(readingID: drill.readingID),
            topicId: drill.areaID,
            durationSeconds: duration,
            selectedOption: selectedOption,
            wasCorrect: wasCorrect
        )
        modelContext.insert(attempt)
        try? modelContext.save()
        submittedAttempt = attempt
        showResult = true
    }

    private func toggleFlag() {
        if let card = reviewCard {
            card.flaggedForReview.toggle()
        } else {
            let card = ReviewCard(
                questionId: drill.id,
                caseId: DrillAttemptContext.caseId(readingID: drill.readingID),
                topicId: drill.areaID,
                readingIds: [drill.readingID],
                losIds: [drill.primaryLOS]
            )
            card.flaggedForReview = true
            modelContext.insert(card)
        }
        try? modelContext.save()
    }
}
