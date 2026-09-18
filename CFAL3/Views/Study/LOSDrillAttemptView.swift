import SwiftUI
import SwiftData

struct LOSDrillAttemptView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(ContentLoader.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [ReviewCard]

    let drill: DrillQuestion
    var standalone: Bool = true
    var sessionProgress: (current: Int, total: Int)?

    @State private var selectedOption: String?
    @State private var clock = AttemptClock()
    @State private var submittedAttempt: Attempt?
    @State private var showResult = false

    private var question: Question { drill.asQuestion }
    private var reviewCard: ReviewCard? {
        cards.first { $0.questionId == drill.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                losChip

                Text(drill.stem)
                    .font(Theme.serif(.title3, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                MultipleChoiceInput(
                    options: drill.options ?? [:],
                    sortedKeys: question.sortedOptionKeys,
                    selected: $selectedOption
                )

                Button("Check answer") {
                    submit()
                }
                .buttonStyle(PrimaryCTA())
                .disabled(selectedOption == nil)

                if sessionProgress != nil {
                    Button {
                        skipAndFlag()
                    } label: {
                        Label(AttemptHost.skipTitle, systemImage: "flag")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.pine)
                    .accessibilityIdentifier("attempt.skip")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Rate after you check:")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                        .frame(maxWidth: .infinity)
                    NamedQualitySelector(
                        selected: .constant(ReviewRating.good.rawValue),
                        card: reviewCard,
                        enabled: false,
                        accessibilityPrefix: "drill"
                    )
                }
            }
            .readableContentWidth()
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("Drill Q\(drill.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if standalone {
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
                    .accessibilityIdentifier("attempt.flag")
                }
            }
        }
        // First appearance only, exactly as in QuestionAttemptView. `onAppear`
        // fires again whenever this view comes back — from the result screen,
        // or from another tab — and restarting the clock there restarted the
        // pacing display mid-question and made durationSeconds count only from
        // the last reappearance. Drills are 2,667 of the 3,164 questions, so
        // fixing this in the bank view alone fixed the smaller half.
        .onAppear {
            clock.appear()
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

    private var losChip: some View {
        let los = content.los(id: drill.primaryLOS)
        let label = los?.displayText ?? drill.primaryLOS
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "tree.fill")
                    .foregroundStyle(Theme.pine)
                Text(label)
                    .font(.headline)
                    .foregroundStyle(Theme.pine)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Capsule().fill(Theme.sage))
            if let reading = content.reading(id: drill.readingID) {
                Text(reading.reading.name)
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        let duration = clock.durationSeconds()
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

    private func skipAndFlag() {
        guard submittedAttempt == nil else { return }
        AttemptHost.flagForSkip(
            questionId: drill.id,
            caseId: DrillAttemptContext.caseId(readingID: drill.readingID),
            topicId: drill.areaID,
            readingIds: [drill.readingID],
            losIds: [drill.primaryLOS],
            existing: reviewCard,
            context: modelContext
        )
        if standalone || !sessionCoordinator.isActive {
            dismiss()
            return
        }
        _ = sessionCoordinator.skipCurrent()
    }

    private func toggleFlag() {
        AttemptHost.setFlagged(
            !(reviewCard?.flaggedForReview ?? false),
            questionId: drill.id,
            caseId: DrillAttemptContext.caseId(readingID: drill.readingID),
            topicId: drill.areaID,
            readingIds: [drill.readingID],
            losIds: [drill.primaryLOS],
            existing: reviewCard,
            context: modelContext
        )
    }
}
