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
                partScoresCard
                graderNotesCard
                guidelineAnswerCard
                yourAnswerCard
                footerRow
            }
            .padding()
            // The CONTENT is capped, not the scroll view. Capping the
            // ScrollView itself left the ~330pt either side of it outside the
            // scrollable area, so a flick started in the margin — most of the
            // screen on an iPad — did nothing at all.
            .readableContentWidth(700)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("Result")
        .navigationBarBackButtonHidden(!standalone && sessionCoordinator.isActive)
        .onAppear {
            selectedQuality = ReviewRating.nearest(defaultQuality).rawValue
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
    private var partScoresCard: some View {
        if !partScoreLines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Part scores")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(partScoreLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(line)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cfaCard()
        }
    }

    @ViewBuilder
    private var graderNotesCard: some View {
        if hasGraderNotes {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grader notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let feedback = graderNotesBody, !feedback.isEmpty {
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

    /// Split out of `claudeFeedback` so the part list is a first-class card
    /// rather than a buried markdown heading, and so grader notes do not
    /// repeat it.
    private var partScoreLines: [String] {
        Self.partScoreLines(in: attempt.claudeFeedback)
    }

    private var graderNotesBody: String? {
        Self.feedbackWithoutPartScores(attempt.claudeFeedback)
    }

    private var hasGraderNotes: Bool {
        if let feedback = graderNotesBody, !feedback.isEmpty { return true }
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
        } else if question.type == .essay, let model = question.modelAnswer, !model.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(attempt.grade == nil ? "Bundled guideline answer" : "Guideline answer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                markdownText(model)
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
        VStack(alignment: .leading, spacing: 10) {
            NamedQualitySelector(
                selected: Binding(
                    get: { selectedQuality ?? defaultQuality },
                    set: { selectedQuality = $0 }
                ),
                card: reviewCard
            )
            HStack {
                Spacer(minLength: 0)
                Button(nextButtonTitle) {
                    saveQualityAndContinue()
                }
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.accent)
            }
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
        if question.type == .essay, attempt.grade == nil {
            return "Grader unavailable"
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
        if question.type == .essay, attempt.grade == nil {
            return "The bundled key is shown below"
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

    /// Grader feedback is built as sections separated by blank lines, with
    /// bulleted points inside each. The default markdown parsing is
    /// inline-only and discards every newline, so the whole critique rendered
    /// as one run-on paragraph — "…required two.**Strengths**Correctly
    /// identifies…". Preserving whitespace keeps the structure.
    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    static func partScoreLines(in feedback: String?) -> [String] {
        guard let feedback, !feedback.isEmpty else { return [] }
        var lines: [String] = []
        var inSection = false
        for raw in feedback.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("**Part scores**") {
                inSection = true
                continue
            }
            if inSection {
                if line.hasPrefix("**") { break }
                if line.hasPrefix("- ") {
                    lines.append(String(line.dropFirst(2)))
                }
            }
        }
        return lines
    }

    static func feedbackWithoutPartScores(_ feedback: String?) -> String? {
        guard let feedback, !feedback.isEmpty else { return nil }
        var kept: [String] = []
        var inSection = false
        for raw in feedback.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("**Part scores**") {
                inSection = true
                continue
            }
            if inSection {
                if trimmed.hasPrefix("**") {
                    inSection = false
                } else {
                    continue
                }
            }
            kept.append(raw)
        }
        let text = kept.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func saveQualityAndContinue() {
        guard !savedQuality else { return }
        let quality = ReviewRating.nearest(selectedQuality ?? defaultQuality).rawValue
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

/// Same four named ratings as flashcards (Again / Hard / Good / Easy), mapped
/// onto SM-2 quality 1 / 3 / 4 / 5. Unlabeled 0–5 boxes were too easy to mash.
private enum ReviewRating: Int, CaseIterable {
    case again = 1
    case hard = 3
    case good = 4
    case easy = 5

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    var tint: Color {
        switch self {
        case .again: return Theme.danger
        case .hard: return Theme.warning
        case .good: return Theme.accent
        case .easy: return Theme.success
        }
    }

    static func nearest(_ quality: Int) -> ReviewRating {
        switch quality {
        case ...2: return .again
        case 3: return .hard
        case 5: return .easy
        default: return .good
        }
    }
}

private struct NamedQualitySelector: View {
    @Binding var selected: Int
    let card: ReviewCard?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ReviewRating.allCases, id: \.rawValue) { rating in
                Button {
                    selected = rating.rawValue
                } label: {
                    VStack(spacing: 2) {
                        Text(rating.label)
                            .font(.footnote.weight(.semibold))
                        Text(intervalLabel(for: rating))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(rating.tint.opacity(selected == rating.rawValue ? 0.22 : 0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(
                                selected == rating.rawValue ? rating.tint : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    .foregroundStyle(rating.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(rating.label), \(intervalLabel(for: rating))")
                .accessibilityIdentifier("result.rate.\(rating.label.lowercased())")
            }
        }
    }

    private func intervalLabel(for rating: ReviewRating) -> String {
        guard let card else { return "1d" }
        return "\(ReviewScheduler.previewInterval(item: card, quality: rating.rawValue))d"
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
