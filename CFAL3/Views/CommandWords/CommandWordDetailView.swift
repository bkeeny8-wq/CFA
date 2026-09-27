import SwiftUI

/// One command word, one page.
///
/// The sections run in the order a candidate needs them: what is being asked,
/// what earns marks, what earns none, how the answer should look on the page,
/// a real bank essay to try it on, the ways it goes wrong, and the verbs it is
/// mistaken for.
struct CommandWordDetailView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(TabRouter.self) private var router

    let word: CommandWord
    /// Supplied by the guide so "easy to confuse with" can move to that word's
    /// page. Nil renders those rows as plain text rather than dead buttons.
    var onSelectWord: ((String) -> Void)?

    private var example: Question? { content.question(id: word.workedExample.id) }

    private var exampleCase: CaseStudy? {
        content.context(for: word.workedExample.id)
            .flatMap { content.caseStudy(id: $0.caseId) }
    }

    /// Bank essays that actually use this verb. Empty is a real answer for
    /// five of the seventeen words, and the page says so.
    private var essaysUsingWord: [Question] {
        content.essays(forCommandWord: word.word)
    }

    private var bankHasNoEssay: Bool { essaysUsingWord.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                askingSection
                bulletSection("What to highlight", key: "highlight", items: word.highlight)
                bulletSection("What to leave out", key: "leaveout", items: word.leaveOut)
                shapeSection
                workedExampleSection
                bulletSection("Common point-losers", key: "pointlosers", items: word.pointLosers)
                confusedSection
            }
            .readableContentWidth(LayoutMetrics.studyReadingMaxWidth)
            .padding(24)
            .textSelection(.enabled)
        }
        .background(Theme.paper)
        .navigationTitle(word.displayWord)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(word.displayWord)
                .font(Theme.serif(.largeTitle, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("commandwords.page.\(word.word)")
            Text(CommandWordDisplay.losHeadline(word, total: content.losMaster?.losFlat.count))
                .font(.subheadline)
                .foregroundStyle(Theme.dust)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var askingSection: some View {
        CommandWordSection(title: "What it’s asking for", key: "asking") {
            Text(word.asking)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bulletSection(_ title: String, key: String, items: [String]) -> some View {
        CommandWordSection(title: title, key: key) {
            CommandWordBullets(items: items)
        }
    }

    private var shapeSection: some View {
        CommandWordSection(title: "How to shape the answer", key: "shape") {
            VStack(alignment: .leading, spacing: 10) {
                shapeRow("Length", value: word.shape.length)
                shapeRow("Structure", value: word.shape.structure)
                HStack(spacing: 8) {
                    ShapeFlagBadge(
                        required: word.shape.requiresCalculation,
                        requiredText: "Calculation required",
                        absentText: "No calculation"
                    )
                    ShapeFlagBadge(
                        required: word.shape.requiresJustification,
                        requiredText: "Justification required",
                        absentText: "No justification"
                    )
                }
            }
        }
    }

    private func shapeRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.dust)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Worked example and practice

    private var workedExampleSection: some View {
        CommandWordSection(title: "Worked example", key: "example") {
            VStack(alignment: .leading, spacing: 12) {
                if bankHasNoEssay {
                    bankGapNotice
                }
                if let example {
                    exampleCard(example)
                    exampleActions(example)
                } else {
                    missingExampleNotice
                }
            }
        }
    }

    private func exampleCard(_ example: Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(exampleCase?.title ?? "Bank essay")
                    .font(Theme.serif(.headline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if let points = example.pointValue {
                    CapsuleBadge(text: "\(points) points")
                }
            }
            Text(example.stem)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(word.workedExample.note)
                .font(.footnote)
                .foregroundStyle(Theme.dust)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Worked example")
    }

    @ViewBuilder
    private func exampleActions(_ example: Question) -> some View {
        VStack(spacing: 8) {
            Button {
                sit([example.id], describedAs: bankHasNoEssay ? "closest-shaped essay" : "worked example")
            } label: {
                Text(bankHasNoEssay ? "Sit the closest-shaped essay" : "Sit this essay")
            }
            .buttonStyle(CompactCTA())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("commandwords.example.sit")
            .accessibilityHint("Opens a sitting with this one essay")

            if let exampleCase {
                NavigationLink {
                    CaseDetailView(caseID: exampleCase.id)
                } label: {
                    Text("Open the case")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.pine)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("commandwords.example.case")
                .accessibilityLabel("Open the case")
                .accessibilityHint("Shows the vignette this essay belongs to")
            }

            // Only when there is more than the one essay already offered
            // above, so the page never shows two buttons for the same sitting.
            if essaysUsingWord.count > 1 {
                Button {
                    sit(essaysUsingWord.map(\.id), describedAs: "\(essaysUsingWord.count) bank essays")
                } label: {
                    Text("Practice all \(essaysUsingWord.count) essays that use “\(word.displayWord)”")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.pine)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("commandwords.practice")
                .accessibilityLabel("Practice all \(essaysUsingWord.count) essays that use \(word.word)")
                .accessibilityHint("Opens a sitting of every bank essay whose stem uses this word")
            }
        }
    }

    /// The honest version of a gap: the content file gives these words a
    /// closest-shaped example, and the page has to say that rather than let
    /// the example pass for a real item.
    private var bankGapNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No essay in the bank uses this word")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Nothing in the question bank sets “\(word.word)” as its command word, so the example below is the closest match in shape rather than a real \(word.word) question. The note says which substitution was made.")
                .font(.footnote)
                .foregroundStyle(Theme.dust)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.copper.opacity(0.18))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("commandwords.gap.\(word.word)")
    }

    /// Only reachable if the bundled guide cites an id the bank does not have.
    /// The repo's checker refuses that, but a build can still be assembled
    /// from mismatched files, and silence would be worse than a notice.
    private var missingExampleNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Worked example missing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("This word cites essay \(word.workedExample.id), which isn’t in the bundled question bank.")
                .font(.footnote)
                .foregroundStyle(Theme.dust)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.copper.opacity(0.18))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("commandwords.example.missing")
    }

    private func sit(_ ids: [String], describedAs description: String) {
        router.startQuestions(
            sessionCoordinator,
            ids: ids,
            mode: .losDrill,
            description: "\(word.displayWord) · \(description)"
        )
    }

    // MARK: - Easy to confuse with

    private var confusedSection: some View {
        CommandWordSection(title: "Easy to confuse with", key: "confusedwith") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(word.confusedWith, id: \.word) { other in
                    confusedRow(other)
                }
            }
        }
    }

    private func confusedRow(_ other: CommandWordConfusion) -> some View {
        let target = content.commandWord(other.word)
        let canOpen = target != nil && onSelectWord != nil

        return Button {
            onSelectWord?(other.word)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(target?.displayWord ?? other.word.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(canOpen ? Theme.pine : Theme.ink)
                    if canOpen {
                        Image(systemName: "arrow.forward")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.pine)
                            .accessibilityHidden(true)
                    }
                }
                Text(other.difference)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .frame(minHeight: 44)
        .accessibilityIdentifier("commandwords.confused.\(other.word)")
        .accessibilityLabel("\(other.word.capitalized). \(other.difference)")
        .accessibilityHint(canOpen ? "Opens the \(other.word) page" : "This word has no page of its own")
    }
}

/// One labelled block on a word's page. Same parchment card as the rest of the
/// app; the label is what makes the seven parts of the schema legible as parts.
private struct CommandWordSection<Content: View>: View {
    let title: String
    let key: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.dust)
                // The container below carries this as its label, so leaving
                // the heading visible to VoiceOver would read it twice.
                .accessibilityHidden(true)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cfaCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("commandwords.section.\(key)")
    }
}

private struct CommandWordBullets: View {
    let items: [String]

    /// Identified by position rather than by the string itself: two bullets
    /// that happened to share text would collide under `id: \.self`.
    private struct Bullet: Identifiable {
        let id: Int
        let text: String
    }

    private var bullets: [Bullet] {
        items.enumerated().map { Bullet(id: $0.offset, text: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(bullets) { bullet in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(Theme.pine.opacity(0.35))
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(bullet.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Both states are drawn rather than only the required one: "no calculation"
/// is information a candidate uses, and an absent badge reads as an oversight.
private struct ShapeFlagBadge: View {
    let required: Bool
    let requiredText: String
    let absentText: String

    var body: some View {
        Text(required ? requiredText : absentText)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(required ? Theme.sage : Theme.subtleFill))
            .foregroundStyle(required ? Theme.pine : Theme.dust)
            .accessibilityLabel(required ? requiredText : absentText)
    }
}
