import SwiftUI
import SwiftData

struct GradingResultView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Query private var cards: [ReviewCard]

    let attempt: Attempt
    let question: Question
    let caseStudy: CaseStudy?
    let standalone: Bool

    @State private var selectedQuality: Int?
    @State private var showAllRationales = false
    @State private var savedQuality = false

    private var reviewCard: ReviewCard? {
        cards.first { $0.questionId == attempt.questionId }
    }

    private var defaultQuality: Int {
        if let grade = attempt.grade {
            return ReviewScheduler.suggestedQuality(essayGrade: grade)
        }
        if let wasCorrect = attempt.wasCorrect {
            return ReviewScheduler.suggestedQuality(wasCorrect: wasCorrect)
        }
        return 3
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                verdictCard
                graderNotesCard
                guidelineAnswerCard
                yourAnswerCard
                footerRow
            }
            .padding()
        }
        .readableContentWidth(700)
        .frame(maxWidth: .infinity)
        .navigationTitle("Result")
        .navigationBarBackButtonHidden(!standalone && sessionCoordinator.isActive)
        .onAppear {
            selectedQuality = defaultQuality
        }
    }

    @ViewBuilder
    private var verdictCard: some View {
        let tint = verdictTint
        VStack(spacing: 4) {
            if let icon = verdictIcon {
                Image(systemName: icon)
                    .font(.title2)
            }
            Text(verdictHeadline)
                .font(.title2.weight(.semibold))
            if let subtitle = verdictSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(tint.opacity(0.14))
        )
        .foregroundStyle(tint)
    }

    @ViewBuilder
    private var graderNotesCard: some View {
        if hasGraderNotes {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grader notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let feedback = attempt.claudeFeedback, !feedback.isEmpty {
                    markdownText(feedback)
                } else if question.type == .mc, let correct = question.correct,
                          let rationale = question.rationales?[correct] {
                    Text(rationale)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cfaCard()
        }
    }

    private var hasGraderNotes: Bool {
        if let feedback = attempt.claudeFeedback, !feedback.isEmpty { return true }
        if question.type == .mc, let correct = question.correct,
           let rationale = question.rationales?[correct], !rationale.isEmpty {
            return true
        }
        return false
    }

    @ViewBuilder
    private var guidelineAnswerCard: some View {
        if question.type == .mc, let correct = question.correct {
            VStack(alignment: .leading, spacing: 8) {
                Text("Guideline answer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("**\(correct).** \(question.options?[correct] ?? "")")
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cfaCard()
        }
    }

    private var yourAnswerCard: some View {
        DisclosureGroup("Your answer") {
            VStack(alignment: .leading, spacing: 8) {
                if question.type == .mc, let selected = attempt.selectedOption {
                    Text("**\(selected).** \(question.options?[selected] ?? "")")
                } else if let essay = attempt.essayText {
                    Text(essay)
                }
                if let reasoning = attempt.reasoningText, !reasoning.isEmpty {
                    Text("Reasoning: \(reasoning)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if question.type == .mc, let rationales = question.rationales {
                    DisclosureGroup("All rationales", isExpanded: $showAllRationales) {
                        ForEach(question.sortedOptionKeys, id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("**\(key).** \(question.options?[key] ?? "")")
                                Text(rationales[key] ?? "")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .cfaCard()
    }

    private var footerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            InlineQualitySelector(selected: Binding(
                get: { selectedQuality ?? defaultQuality },
                set: { selectedQuality = $0 }
            ))
            Spacer(minLength: 8)
            Button(nextButtonTitle) {
                saveQualityAndContinue()
            }
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.accent)
        }
        .padding(.top, 4)
    }

    private var verdictTint: Color {
        if question.type == .essay,
           let earned = attempt.pointsEarned,
           let possible = attempt.pointsPossible,
           possible > 0 {
            let ratio = Double(earned) / Double(possible)
            if ratio >= 0.7 { return Theme.success }
            if ratio >= 0.4 { return Theme.warning }
            return Theme.danger
        }
        if let wasCorrect = attempt.wasCorrect {
            return wasCorrect ? Theme.success : Theme.danger
        }
        if question.type == .essay, let grade = attempt.grade {
            if grade >= 4 { return Theme.success }
            if grade >= 3 { return Theme.warning }
            return Theme.danger
        }
        return Theme.accent
    }

    private var verdictIcon: String? {
        if question.type == .essay, attempt.pointsEarned != nil {
            return "star.circle.fill"
        }
        if let wasCorrect = attempt.wasCorrect {
            return wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        return nil
    }

    private var verdictHeadline: String {
        if question.type == .essay,
           let earned = attempt.pointsEarned,
           let possible = attempt.pointsPossible,
           possible > 0 {
            return "\(earned)/\(possible) points"
        }
        if let wasCorrect = attempt.wasCorrect {
            return wasCorrect ? "Correct" : "Incorrect"
        }
        if question.type == .essay, let grade = attempt.grade {
            if let e = attempt.pointsEarned, let p = attempt.pointsPossible, p > 0 {
                return "\(e)/\(p) points"
            }
            return "Grade \(grade)/5"
        }
        return "Submitted"
    }

    private var verdictSubtitle: String? {
        if question.type == .essay,
           attempt.pointsEarned != nil,
           let grade = attempt.grade {
            return "Grade \(grade)/5"
        }
        if question.type == .mc,
           let selected = attempt.selectedOption,
           let correct = question.correct {
            return "You chose \(selected) · Answer \(correct)"
        }
        return nil
    }

    private var nextButtonTitle: String {
        if standalone || !sessionCoordinator.isActive {
            return "Done"
        }
        return sessionCoordinator.currentIndex + 1 < sessionCoordinator.questionIDs.count
            ? "Next →"
            : "Finish session"
    }

    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    private func saveQualityAndContinue() {
        guard !savedQuality else { return }
        let quality = selectedQuality ?? defaultQuality
        attempt.quality = quality

        if let card = reviewCard {
            ReviewScheduler.update(card: card, quality: quality)
        }

        sessionCoordinator.recordAttempt(attempt.id)
        try? modelContext.save()
        savedQuality = true

        if standalone || !sessionCoordinator.isActive {
            dismiss()
            return
        }

        if sessionCoordinator.advance() {
            dismiss()
        } else {
            dismiss()
        }
    }
}

private struct InlineQualitySelector: View {
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0...5, id: \.self) { value in
                Button {
                    selected = value
                } label: {
                    Text("\(value)")
                        .font(.caption.weight(.medium))
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected == value
                                      ? Theme.accent.opacity(0.15)
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    selected == value ? Theme.accent : Theme.hairline,
                                    lineWidth: selected == value ? 1.5 : 1
                                )
                        )
                        .foregroundStyle(selected == value ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Self-rate \(value)")
            }
        }
    }
}

struct QualitySelector: View {
    @Binding var selected: Int

    private let labels = [
        "0 — blank",
        "1 — wrong",
        "2 — wrong, primed",
        "3 — hesitant",
        "4 — minor hesitation",
        "5 — confident"
    ]

    var body: some View {
        ForEach(0...5, id: \.self) { value in
            Button {
                selected = value
            } label: {
                HStack {
                    Text(labels[value])
                    Spacer()
                    if selected == value {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
