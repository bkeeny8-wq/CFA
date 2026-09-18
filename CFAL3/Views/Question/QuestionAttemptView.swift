import SwiftUI
import SwiftData

struct QuestionAttemptView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(ClaudeGrader.self) private var grader
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var cards: [ReviewCard]

    let questionID: String
    var standalone: Bool = false
    var sessionProgress: (current: Int, total: Int)?
    /// Session sittings pass a binding so consecutive questions on the same
    /// case keep the vignette open (or hidden) together. Standalone sittings
    /// fall back to `localVignetteExpanded`.
    var vignetteExpansion: Binding<Bool>? = nil

    @State private var selectedOption: String?
    @State private var essayText = ""
    @State private var reasoningText = ""
    @State private var explainReasoning = false
    @State private var localVignetteExpanded = true
    @State private var clock = AttemptClock()
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
    private var isVignetteExpanded: Binding<Bool> {
        vignetteExpansion ?? $localVignetteExpanded
    }

    var body: some View {
        Group {
            if let question, let caseStudy {
                sittingBody(question: question, caseStudy: caseStudy)
            } else {
                ContentUnavailableView(
                    "Question missing",
                    systemImage: "questionmark.circle",
                    description: Text("This item isn't in the current build. Go back to continue.")
                )
            }
        }
        .navigationTitle(question.map { "Q\($0.number)" } ?? "Question")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if standalone {
                if question?.type == .mc {
                    ToolbarItem(placement: .topBarLeading) {
                        Toggle("Reasoning", isOn: $explainReasoning)
                            .toggleStyle(.button)
                            .accessibilityLabel("Explain reasoning")
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
                    .accessibilityIdentifier("attempt.flag")
                }
            }
        }
        .onAppear {
            // First appearance only. `onAppear` fires again every time this
            // view comes back — returning from the result screen, or leaving
            // for another tab and coming back — and restarting the clock there
            // both reset the pacing timer mid-question and made
            // Attempt.durationSeconds report only the time since the last
            // reappearance. Measured on device: a question open for 55 seconds
            // recorded 19.
            clock.appear()
            if standalone, let caseStudy {
                localVignetteExpanded = VignetteExpansionStore.isExpanded(caseID: caseStudy.id)
            }
            restoreDraft()
        }
        .onChange(of: localVignetteExpanded) { _, expanded in
            guard standalone, let caseStudy else { return }
            VignetteExpansionStore.setExpanded(expanded, caseID: caseStudy.id)
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

    @ViewBuilder
    private func sittingBody(question: Question, caseStudy: CaseStudy) -> some View {
        let split = horizontalSizeClass == .regular && sessionProgress != nil
        if split {
            HStack(alignment: .top, spacing: 16) {
                vignetteColumn(caseStudy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                questionColumn(question: question, caseStudy: caseStudy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(16)
            .background(Theme.paper)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    vignetteColumn(caseStudy)
                    questionColumn(question: question, caseStudy: caseStudy)
                }
                .readableContentWidth()
                .padding()
            }
            .background(Theme.paper)
        }
    }

    private func vignetteColumn(_ caseStudy: CaseStudy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Item set", systemImage: "pin.fill")
                        .font(Theme.serif(.title3, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                if isVignetteExpanded.wrappedValue {
                    VignetteView(
                        vignette: caseStudy.vignette,
                        isExpanded: isVignetteExpanded,
                        showsToggle: standalone
                    )
                }
                if sessionProgress != nil {
                    Label("Stay open for this case", systemImage: "pin")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                        .frame(maxWidth: .infinity)
                }
            }
            .cfaCard(radius: Theme.sittingCardRadius, padding: 22)
        }
    }

    private func questionColumn(question: Question, caseStudy: CaseStudy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if let sessionProgress {
                        Text("Q\(sessionProgress.current)")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.pine))
                            .foregroundStyle(.white)
                        Text("of \(sessionProgress.total)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.dust)
                    }
                    Spacer()
                    if let points = question.pointValue {
                        Text("\(points) points · \(question.type == .essay ? "constructed response" : "item set")")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().strokeBorder(Theme.pine.opacity(0.25)))
                            .foregroundStyle(Theme.dust)
                    }
                }

                Text(question.stem)
                    .font(Theme.serif(.body, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                PacingTimer(
                    startedAt: clock.startedAt,
                    targetSeconds: ExamPacing.targetSeconds(points: question.pointValue)
                )

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
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Grading your answer…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.dust)
                        Spacer()
                        Button("Cancel") { cancelSubmission() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Grading your answer")
                } else {
                    HStack(spacing: 12) {
                        if sessionProgress != nil {
                            Button {
                                skipAndFlag(question: question, caseStudy: caseStudy)
                            } label: {
                                Label(AttemptHost.skipTitle, systemImage: "flag")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.pine)
                            .accessibilityIdentifier("attempt.skip")
                        }
                        Button(submitTitle(for: question)) {
                            submitTask?.cancel()
                            submitTask = Task {
                                await submit(question: question, caseStudy: caseStudy)
                            }
                        }
                        .buttonStyle(PrimaryCTA())
                        .disabled(!canSubmit(question: question) || (question.type == .mc && !question.canGradeMC && explainReasoning))
                    }
                }
            }
            .cfaCard(radius: Theme.sittingCardRadius, padding: 22)
        }
    }

    /// Only reached when not submitting — the in-flight state is its own row
    /// with a spinner and a cancel control.
    private func submitTitle(for question: Question) -> String {
        QuestionSubmitCopy.title(
            type: question.type,
            canGradeMC: question.canGradeMC,
            explainReasoning: explainReasoning,
            hasReasoningText: !reasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
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

        let duration = clock.durationSeconds()
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
                // Record the sitting anyway and show the bundled key. Leaving
                // without an Attempt made "grader down" look like the answer
                // vanished, and hid the guideline the candidate still needs.
                if Task.isCancelled { return }
                feedback = "Grading unavailable: \(error.localizedDescription). The bundled guideline answer is shown instead."
                pointsPossible = question.pointValue
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

    private func skipAndFlag(question: Question, caseStudy: CaseStudy) {
        guard submittedAttempt == nil, !isSubmitting else { return }
        let ctx = content.context(for: questionID)
        AttemptHost.flagForSkip(
            questionId: questionID,
            caseId: caseStudy.id,
            topicId: ctx?.topicId ?? caseStudy.topicID,
            readingIds: question.primaryReadingIDs,
            losIds: question.candidateLOS,
            existing: reviewCard,
            context: modelContext
        )
        clearDraft()
        if standalone || !sessionCoordinator.isActive {
            dismiss()
            return
        }
        _ = sessionCoordinator.skipCurrent()
    }

    private func toggleFlag() {
        let ctx = content.context(for: questionID)
        AttemptHost.setFlagged(
            !(reviewCard?.flaggedForReview ?? false),
            questionId: questionID,
            caseId: ctx?.caseId ?? caseStudy?.id ?? "",
            topicId: ctx?.topicId ?? caseStudy?.topicID ?? "",
            readingIds: question?.primaryReadingIDs ?? [],
            losIds: question?.candidateLOS ?? [],
            existing: reviewCard,
            context: modelContext
        )
    }
}

/// "Grade" on a local key-check sounded like the Claude path. Keep that word
/// for the network critique; a plain MC check is just a check.
enum QuestionSubmitCopy {
    static func title(
        type: QuestionType,
        canGradeMC: Bool,
        explainReasoning: Bool,
        hasReasoningText: Bool
    ) -> String {
        switch type {
        case .mc where explainReasoning && hasReasoningText:
            return "Grade reasoning"
        case .mc:
            return canGradeMC ? "Check answer" : "Submit answer"
        case .essay:
            return "Submit for grading"
        }
    }
}
