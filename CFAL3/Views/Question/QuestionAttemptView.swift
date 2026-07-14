import SwiftUI
import SwiftData

struct QuestionAttemptView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(ClaudeGrader.self) private var grader
    @Environment(\.modelContext) private var modelContext
    @Query private var cards: [ReviewCard]

    let questionID: String
    var standalone: Bool = false
    var sessionProgress: (current: Int, total: Int)?

    @State private var selectedOption: String?
    @State private var essayText = ""
    @State private var reasoningText = ""
    @State private var explainReasoning = false
    @State private var vignetteExpanded = false
    @State private var startedAt = Date()
    @State private var submittedAttempt: Attempt?
    @State private var showResult = false
    @State private var isSubmitting = false
    @State private var submitError: String?

    private var question: Question? { content.question(id: questionID) }
    private var caseStudy: CaseStudy? {
        guard let ctx = content.context(for: questionID) else { return nil }
        return content.caseStudy(id: ctx.caseId)
    }
    private var reviewCard: ReviewCard? {
        cards.first { $0.questionId == questionID }
    }

    var body: some View {
        Group {
            if let question, let caseStudy {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let sessionProgress {
                            Text("\(sessionProgress.current) / \(sessionProgress.total)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VignetteView(vignette: caseStudy.vignette, isExpanded: $vignetteExpanded)

                        if question.isIncomplete {
                            Text("⚠ Incomplete solution")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Text(question.stem)
                            .font(.body)

                        if let points = question.pointValue {
                            Label("\(points) points", systemImage: "pencil.and.list.clipboard")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            PacingTimer(startedAt: startedAt, targetSeconds: points * 90)
                        }

                        if question.type == .mc {
                            if explainReasoning {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Explain your reasoning")
                                        .font(.headline)
                                    TextField("Your reasoning…", text: $reasoningText, axis: .vertical)
                                        .lineLimit(3...8)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }

                            MultipleChoiceInput(
                                options: question.options ?? [:],
                                sortedKeys: question.sortedOptionKeys,
                                selected: $selectedOption
                            )
                        } else {
                            EssayInput(text: $essayText)
                        }

                        if let submitError {
                            Text(submitError)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }

                        Button(submitTitle(for: question)) {
                            Task { await submit(question: question, caseStudy: caseStudy) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(!canSubmit(question: question) || isSubmitting || (question.type == .mc && !question.canGradeMC && explainReasoning))
                    }
                    .readableContentWidth()
                    .padding()
                }
            } else {
                ContentUnavailableView("Question not found", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(question.map { "Q\($0.number)" } ?? "Question")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if question?.type == .mc {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle("Reasoning", isOn: $explainReasoning)
                        .toggleStyle(.button)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFlag()
                } label: {
                    Image(systemName: reviewCard?.flaggedForReview == true ? "flag.fill" : "flag")
                }
            }
        }
        .onAppear {
            startedAt = .now
            vignetteExpanded = false
        }
        .navigationDestination(isPresented: $showResult) {
            if let submittedAttempt, let question {
                GradingResultView(
                    attempt: submittedAttempt,
                    question: question,
                    caseStudy: caseStudy,
                    standalone: standalone
                )
            }
        }
    }

    private func submitTitle(for question: Question) -> String {
        if isSubmitting { return "Submitting…" }
        switch question.type {
        case .mc where explainReasoning && !reasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return "Grade answer & reasoning"
        case .mc:
            return question.canGradeMC ? "Grade my MC answer" : "Submit answer"
        case .essay:
            return "Submit for grading"
        }
    }

    private func canSubmit(question: Question) -> Bool {
        switch question.type {
        case .mc:
            return selectedOption != nil
        case .essay:
            return !essayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @MainActor
    private func submit(question: Question, caseStudy: CaseStudy) async {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let duration = max(1, Int(Date().timeIntervalSince(startedAt)))
        let ctx = content.context(for: questionID)

        var wasCorrect: Bool?
        var grade: Int?
        var pointsEarned: Int?
        var pointsPossible: Int?
        var feedback: String?
        var reasoning: String?

        switch question.type {
        case .mc:
            wasCorrect = question.correct.map { selectedOption == $0 }
            if explainReasoning, !reasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reasoning = reasoningText
                do {
                    let stream = grader.gradeReasoning(
                        vignette: caseStudy.vignette,
                        stem: question.stem,
                        reasoning: reasoningText,
                        correctOption: question.correct ?? "",
                        correctRationale: question.rationales?[question.correct ?? ""] ?? ""
                    )
                    let raw = try await grader.collectStream(stream)
                    let parsed = try GradingResponseParser.parse(raw)
                    grade = parsed.grade
                    feedback = parsed.feedbackMarkdown
                } catch {
                    submitError = error.localizedDescription
                    return
                }
            }
        case .essay:
            do {
                let stream = grader.gradeEssay(
                    vignette: caseStudy.vignette,
                    stem: question.stem,
                    essayText: essayText,
                    canonicalAnswer: question.modelAnswer,
                    points: question.pointValue
                )
                let raw = try await grader.collectStream(stream)
                let parsed = try GradingResponseParser.parse(raw)
                grade = parsed.grade
                pointsEarned = parsed.pointsEarned
                pointsPossible = parsed.pointsPossible
                feedback = parsed.feedbackMarkdown
            } catch {
                submitError = error.localizedDescription
                return
            }
        }

        let attempt = Attempt(
            questionId: questionID,
            caseId: caseStudy.id,
            topicId: ctx?.topicId ?? caseStudy.topicID,
            durationSeconds: duration,
            selectedOption: selectedOption,
            wasCorrect: wasCorrect,
            essayText: question.type == .essay ? essayText : nil,
            grade: grade,
            claudeFeedback: feedback,
            reasoningText: reasoning,
            pointsEarned: pointsEarned,
            pointsPossible: pointsPossible
        )
        modelContext.insert(attempt)
        try? modelContext.save()

        submittedAttempt = attempt
        showResult = true
    }

    private func toggleFlag() {
        if let card = reviewCard {
            card.flaggedForReview.toggle()
        } else if let ctx = content.context(for: questionID), let question = content.question(id: questionID) {
            let card = ReviewCard(
                questionId: questionID,
                caseId: ctx.caseId,
                topicId: ctx.topicId,
                readingIds: question.primaryReadingIDs,
                losIds: question.candidateLOS
            )
            card.flaggedForReview = true
            modelContext.insert(card)
        }
        try? modelContext.save()
    }
}

private struct PacingTimer: View {
    let startedAt: Date
    let targetSeconds: Int

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startedAt))
            let over = elapsed > targetSeconds
            Label(
                "\(format(elapsed)) / \(format(targetSeconds)) target",
                systemImage: "timer"
            )
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(over ? .orange : .secondary)
        }
    }

    private func format(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}
