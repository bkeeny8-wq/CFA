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
    /// Held so leaving the screen cancels the in-flight grading call. An
    /// unstructured Task outlives the view, so backing out kept a paid request
    /// running and then wrote an attempt for a question already abandoned.
    @State private var submitTask: Task<Void, Never>?

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
                                .foregroundStyle(Theme.danger)
                                .font(.footnote)
                        }

                        if isSubmitting {
                            // Grading was a dead, disabled "Submitting…" with
                            // no spinner and no way out, so a slow or stalled
                            // request looked like a frozen screen.
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Grading your answer…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Cancel") { cancelSubmission() }
                                    .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Grading your answer")
                        } else {
                            Button(submitTitle(for: question)) {
                                submitTask?.cancel()
                                submitTask = Task {
                                    await submit(question: question, caseStudy: caseStudy)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .disabled(!canSubmit(question: question) || (question.type == .mc && !question.canGradeMC && explainReasoning))
                        }
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
                .accessibilityLabel(
                    reviewCard?.flaggedForReview == true
                        ? "Remove review flag"
                        : "Flag for review"
                )
            }
        }
        .onAppear {
            startedAt = .now
            vignetteExpanded = false
            restoreDraft()
        }
        .onDisappear {
            submitTask?.cancel()
            submitTask = nil
            saveDraft()
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

    /// Only reached when not submitting — the in-flight state is its own row
    /// with a spinner and a cancel control.
    private func submitTitle(for question: Question) -> String {
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
        // One answer, one Attempt. Returning to an already-submitted question
        // left the answer in place and the button live, so a second tap wrote
        // a duplicate row and aged the card twice.
        guard submittedAttempt == nil, !isSubmitting else { return }
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
                    // The multiple-choice result is computed locally and owes
                    // the network nothing. Aborting here threw away a correct
                    // answer because an OPTIONAL reasoning critique failed.
                    if Task.isCancelled { return }
                    feedback = "Reasoning feedback unavailable: \(error.localizedDescription)"
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
                // An essay has no locally-computable result, so there is
                // nothing to record — but say so rather than failing silently.
                if !Task.isCancelled { submitError = error.localizedDescription }
                return
            }
        }

        guard !Task.isCancelled else { return }

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

        clearDraft()
        submittedAttempt = attempt
        showResult = true
    }

    /// Stop waiting on the grader. The in-flight call is cancelled and the
    /// controls come back immediately; `submit` bails at its cancellation
    /// guards rather than writing an attempt after the fact.
    private func cancelSubmission() {
        submitTask?.cancel()
        submitTask = nil
        isSubmitting = false
        submitError = nil
    }

    // MARK: - Drafts

    // An in-progress essay lived only in @State, so a back tap or an edge
    // swipe destroyed it with no warning. Persisting beats confirming: it also
    // survives the app being killed, and needs no navigation interception.

    private var draftKey: String { "draft.answer.\(questionID)" }
    private var draftReasoningKey: String { "draft.reasoning.\(questionID)" }

    private func restoreDraft() {
        guard submittedAttempt == nil else { return }
        let defaults = UITestMode.defaults
        if essayText.isEmpty, let saved = defaults.string(forKey: draftKey) {
            essayText = saved
        }
        if reasoningText.isEmpty, let saved = defaults.string(forKey: draftReasoningKey) {
            reasoningText = saved
            if !saved.isEmpty { explainReasoning = true }
        }
    }

    private func saveDraft() {
        let defaults = UITestMode.defaults
        guard submittedAttempt == nil else { return clearDraft() }
        let answer = essayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoning = reasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
        answer.isEmpty ? defaults.removeObject(forKey: draftKey)
                       : defaults.set(essayText, forKey: draftKey)
        reasoning.isEmpty ? defaults.removeObject(forKey: draftReasoningKey)
                          : defaults.set(reasoningText, forKey: draftReasoningKey)
    }

    private func clearDraft() {
        UITestMode.defaults.removeObject(forKey: draftKey)
        UITestMode.defaults.removeObject(forKey: draftReasoningKey)
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
