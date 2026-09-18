import SwiftUI
import SwiftData

/// Exam-booklet analogue: vignette pinned, every question on one page,
/// submit-all, then one grade pass. One-by-one sittings remain the mock path.
struct CaseAnswerSheetView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(ClaudeGrader.self) private var grader
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let caseStudy: CaseStudy

    @State private var vignetteExpanded = true
    @State private var clock = AttemptClock()
    @State private var mcAnswers: [String: String] = [:]
    @State private var essayAnswers: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var results: [String: Attempt] = [:]
    @State private var selectedResultID: UUID?
    @State private var submitTask: Task<Void, Never>?

    private var questions: [Question] { caseStudy.questions }
    private var isGraded: Bool { !results.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VignetteView(vignette: caseStudy.vignette, isExpanded: $vignetteExpanded)
                    .cfaCard()

                PacingTimer(
                    startedAt: clock.startedAt,
                    targetSeconds: ExamPacing.targetSeconds(for: questions)
                )
                Text("\(Formatting.duration(seconds: ExamPacing.targetSeconds(for: questions))) case · 90s/point")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(questions) { question in
                    questionBlock(question)
                }

                if let submitError {
                    Text(submitError)
                        .foregroundStyle(Theme.danger)
                        .font(.footnote)
                }

                if isSubmitting {
                    HStack {
                        ProgressView()
                        Text("Grading the booklet…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            submitTask?.cancel()
                            submitTask = nil
                            isSubmitting = false
                        }
                        .buttonStyle(.bordered)
                    }
                } else if !isGraded {
                    Button(canSubmit ? "Submit all" : "Answer every question to submit") {
                        submitTask = Task { await submitAll() }
                    }
                    .buttonStyle(PrimaryCTA())
                    .disabled(!canSubmit)
                    .accessibilityHint(canSubmit
                        ? "Grades every question in this booklet"
                        : "Answer every question before submitting")
                } else {
                    Text(scoreLine)
                        .font(.headline)
                    if let elapsed = bookletElapsed {
                        Text(paceLine(elapsed: elapsed))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryCTA())
                }
            }
            .readableContentWidth()
            .padding()
        }
        .navigationTitle("Answer sheet")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { selectedResultID != nil },
            set: { if !$0 { selectedResultID = nil } }
        )) {
            if let id = selectedResultID,
               let attempt = results.values.first(where: { $0.id == id }),
               let question = content.question(id: attempt.questionId) {
                GradingResultView(
                    attempt: attempt,
                    question: question,
                    caseStudy: caseStudy,
                    standalone: true
                )
            }
        }
        .onAppear {
            clock.appear()
            vignetteExpanded = VignetteExpansionStore.isExpanded(caseID: caseStudy.id)
        }
        .onChange(of: vignetteExpanded) { _, expanded in
            VignetteExpansionStore.setExpanded(expanded, caseID: caseStudy.id)
        }
        .onDisappear {
            submitTask?.cancel()
            submitTask = nil
        }
    }

    private var bookletElapsed: Int? {
        guard isGraded else { return nil }
        let total = results.values.reduce(0) { $0 + $1.durationSeconds }
        return total > 0 ? total : nil
    }

    private var canSubmit: Bool {
        questions.allSatisfy { question in
            switch question.type {
            case .mc: return mcAnswers[question.id] != nil
            case .essay:
                return !(essayAnswers[question.id] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private func paceLine(elapsed: Int) -> String {
        let target = ExamPacing.targetSeconds(for: questions)
        let delta = elapsed - target
        let vs: String
        if delta == 0 {
            vs = "on the 90s/point pace"
        } else if delta > 0 {
            vs = "\(Formatting.duration(seconds: delta)) over 90s/point"
        } else {
            vs = "\(Formatting.duration(seconds: -delta)) under 90s/point"
        }
        return "\(Formatting.duration(seconds: elapsed)) elapsed · \(Formatting.duration(seconds: target)) target · \(vs)"
    }

    private var scoreLine: String {
        let mc = questions.filter { $0.type == .mc }
        let correct = mc.filter { results[$0.id]?.wasCorrect == true }.count
        let essays = questions.filter { $0.type == .essay }
        let earned = essays.compactMap { results[$0.id]?.pointsEarned }.reduce(0, +)
        let possible = essays.compactMap { results[$0.id]?.pointsPossible }.reduce(0, +)
        var parts: [String] = []
        if !mc.isEmpty { parts.append("\(correct)/\(mc.count) MC") }
        if possible > 0 { parts.append("\(earned)/\(possible) essay points") }
        return parts.isEmpty ? "Submitted" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func questionBlock(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Q\(question.number)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(question.stem)
                .font(.body)
            if let points = question.pointValue {
                Text("\(points) points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if question.type == .mc {
                MultipleChoiceInput(
                    options: question.options ?? [:],
                    sortedKeys: question.sortedOptionKeys,
                    selected: Binding(
                        get: { mcAnswers[question.id] },
                        set: { mcAnswers[question.id] = $0 }
                    )
                )
                .disabled(isGraded)
            } else {
                EssayInput(
                    text: Binding(
                        get: { essayAnswers[question.id] ?? "" },
                        set: { essayAnswers[question.id] = $0 }
                    )
                )
                .disabled(isGraded)
            }

            if let attempt = results[question.id] {
                Button {
                    selectedResultID = attempt.id
                } label: {
                    Text(resultCaption(question, attempt))
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .cfaCard()
    }

    private func resultCaption(_ question: Question, _ attempt: Attempt) -> String {
        if question.type == .mc {
            return attempt.wasCorrect == true ? "Correct — view result" : "Incorrect — view result"
        }
        if let e = attempt.pointsEarned, let p = attempt.pointsPossible, p > 0 {
            return "\(e)/\(p) points — view result"
        }
        if attempt.grade == nil {
            return "Grader unavailable — view bundled key"
        }
        return "View result"
    }

    @MainActor
    private func submitAll() async {
        guard !isSubmitting, results.isEmpty else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        var graded: [String: Attempt] = [:]
        let elapsed = clock.durationSeconds()
        let slices = ExamPacing.allocate(
            elapsedSeconds: elapsed,
            weights: questions.map { ExamPacing.weight(for: $0) }
        )
        for (question, duration) in zip(questions, slices) {
            if Task.isCancelled { return }
            let attempt = await grade(question, durationSeconds: duration)
            modelContext.insert(attempt)
            graded[question.id] = attempt
        }
        try? modelContext.save()
        results = graded
    }

    @MainActor
    private func grade(_ question: Question, durationSeconds: Int) async -> Attempt {
        let ctx = content.context(for: question.id)
        switch question.type {
        case .mc:
            let selected = mcAnswers[question.id]
            return Attempt(
                questionId: question.id,
                caseId: caseStudy.id,
                topicId: ctx?.topicId ?? caseStudy.topicID,
                durationSeconds: durationSeconds,
                selectedOption: selected,
                wasCorrect: question.correct.map { selected == $0 }
            )
        case .essay:
            let text = essayAnswers[question.id] ?? ""
            var grade: Int?
            var pointsEarned: Int?
            var pointsPossible: Int? = question.pointValue
            var feedback: String?
            do {
                let stream = grader.gradeEssay(
                    vignette: caseStudy.vignette,
                    stem: question.stem,
                    essayText: text,
                    canonicalAnswer: question.modelAnswer,
                    points: question.pointValue
                )
                let raw = try await grader.collectStream(stream)
                let parsed = try GradingResponseParser.parse(raw)
                grade = parsed.grade
                pointsEarned = parsed.pointsEarned
                pointsPossible = parsed.pointsPossible ?? question.pointValue
                feedback = parsed.feedbackMarkdown
            } catch {
                if !Task.isCancelled {
                    feedback = "Grading unavailable: \(error.localizedDescription). The bundled guideline answer is shown instead."
                }
            }
            return Attempt(
                questionId: question.id,
                caseId: caseStudy.id,
                topicId: ctx?.topicId ?? caseStudy.topicID,
                durationSeconds: durationSeconds,
                essayText: text,
                grade: grade,
                claudeFeedback: feedback,
                pointsEarned: pointsEarned,
                pointsPossible: pointsPossible
            )
        }
    }
}
