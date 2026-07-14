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
        List {
            Section {
                resultBanner
            }

            Section("Your answer") {
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
            }

            if question.type == .mc, let correct = question.correct {
                Section("Correct answer") {
                    Text("**\(correct).** \(question.options?[correct] ?? "")")
                        .foregroundStyle(Theme.accent)
                }
            }

            Section("Rationale") {
                if let feedback = attempt.claudeFeedback, !feedback.isEmpty {
                    markdownText(feedback)
                } else if question.type == .mc, let correct = question.correct,
                          let rationale = question.rationales?[correct] {
                    Text(rationale)
                } else {
                    Text("No rationale available.")
                        .foregroundStyle(.secondary)
                }
            }

            if question.type == .mc, let rationales = question.rationales {
                Section {
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

            Section("Self-rate 0–5") {
                QualitySelector(selected: Binding(
                    get: { selectedQuality ?? defaultQuality },
                    set: { selectedQuality = $0 }
                ))
            }

            Section {
                Button(nextButtonTitle) {
                    saveQualityAndContinue()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .listStyle(.insetGrouped)
        .readableContentWidth()
        .frame(maxWidth: .infinity)
        .navigationTitle("Result")
        .navigationBarBackButtonHidden(!standalone && sessionCoordinator.isActive)
        .onAppear {
            selectedQuality = defaultQuality
        }
    }

    @ViewBuilder
    private var resultBanner: some View {
        if question.type == .essay, let grade = attempt.grade {
            let headline: String = {
                if let e = attempt.pointsEarned, let p = attempt.pointsPossible, p > 0 {
                    return "\(e)/\(p) points"
                }
                return "Grade \(grade)/5"
            }()
            Label(headline, systemImage: "star.circle.fill")
                .font(.title2)
                .foregroundStyle(grade >= 3 ? .green : .orange)
        } else if let wasCorrect = attempt.wasCorrect {
            Label(wasCorrect ? "Correct" : "Incorrect", systemImage: wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(wasCorrect ? .green : .red)
        } else {
            Text("Submitted")
                .font(.title2)
        }
    }

    private var nextButtonTitle: String {
        if standalone || !sessionCoordinator.isActive {
            return "Done"
        }
        return sessionCoordinator.currentIndex + 1 < sessionCoordinator.questionIDs.count ? "Next" : "Finish session"
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
