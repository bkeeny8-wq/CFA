import SwiftUI
import SwiftData

/// A single pass through a deck: show the prompt, reveal on tap, then rate.
/// The rating feeds the same SM-2 scheduler the question review uses, so a
/// card's next appearance is earned rather than fixed.
struct FlashcardSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var progress: [FlashcardProgress]

    let title: String

    /// A SNAPSHOT, taken once. The deck arrives from an expression the parent
    /// recomputes on every body evaluation, and rating a card invalidates the
    /// parent's @Query — so a plain `let` meant each rating rebuilt the deck
    /// underneath the index walking it, skipping cards and shuffling the rest.
    @State private var cards: [Flashcard]

    init(title: String, cards: [Flashcard]) {
        self.title = title
        _cards = State(initialValue: cards)
    }

    @State private var index = 0
    @State private var isRevealed = false
    @State private var ratedCount = 0

    private var current: Flashcard? {
        guard index >= 0, index < cards.count else { return nil }
        return cards[index]
    }

    private var progressByCard: [String: FlashcardProgress] {
        Dictionary(progress.map { ($0.cardId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "checkmark.circle",
                    description: Text("This session has no cards. Go back and pick a deck, or start today's mix when cards are due.")
                )
            } else if let card = current {
                cardScreen(card)
            } else {
                summary
            }
        }
        .navigationTitle(title)
        .hidesStudySelector()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if current != nil {
                    Text("\(index + 1) / \(cards.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("flashcard.progress")
                        .accessibilityLabel("Card \(index + 1) of \(cards.count)")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let card = current {
                    Button {
                        toggleFlag(card)
                    } label: {
                        Image(systemName: progressByCard[card.id]?.flaggedForReview == true
                              ? "flag.fill" : "flag")
                    }
                    .accessibilityLabel(
                        progressByCard[card.id]?.flaggedForReview == true
                        ? "Remove flag" : "Flag for review"
                    )
                    .accessibilityIdentifier("flashcard.flag")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if current != nil {
                    Button(AttemptHost.skipTitle) {
                        if let card = current { skipAndFlag(card) }
                    }
                    .accessibilityIdentifier("flashcard.skip")
                }
            }
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func cardScreen(_ card: Flashcard) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                if isRevealed {
                    cardBody(card)
                } else {
                    // A real Button, not a tap gesture on a container: the
                    // gesture was invisible to VoiceOver, which had no way to
                    // reveal an answer at all.
                    Button {
                        sitAnimation { isRevealed = true }
                    } label: {
                        cardBody(card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("flashcard.reveal")
                    .accessibilityLabel("Reveal answer")
                    .accessibilityHint(card.front)
                }
            }

            if isRevealed {
                ratingBar(card)
            }
        }
    }

    /// The card itself. Used as a Button's label before the answer is shown
    /// and as plain content after, so the revealed text stays selectable.
    private func cardBody(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            typeBadge(card)

            Text(card.front)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRevealed {
                Divider()

                if let formula = card.formula, !formula.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(formula)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.subtleFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }

                Text(card.back)
                    .font(.body)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let m = card.mnemonic, !m.trimmingCharacters(in: .whitespaces).isEmpty {
                    Label(m, systemImage: "brain")
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Tap to reveal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .padding(.horizontal)
        // A card answer set across the full 1032pt runs to about 968pt of text
        // per line, which is roughly twice a comfortable measure and makes the
        // eye lose its place between lines.
        .readableContentWidth()
        .padding(.top, 12)
    }

    private func typeBadge(_ card: Flashcard) -> some View {
        HStack(spacing: 8) {
            Label(card.type.displayName, systemImage: card.type.symbolName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.accent.opacity(0.15)))
                .foregroundStyle(Theme.accent)

            if card.difficulty == .stretch {
                Text("Stretch")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.warning.opacity(0.18)))
                    .foregroundStyle(Theme.warning)
            }
            Spacer()
        }
    }

    // MARK: - Rating

    private func ratingBar(_ card: Flashcard) -> some View {
        let row = progressByCard[card.id]
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ratingButton("Again", quality: 1, tint: Theme.danger, row: row, card: card)
                ratingButton("Hard", quality: 3, tint: Theme.warning, row: row, card: card)
                ratingButton("Good", quality: 4, tint: Theme.accent, row: row, card: card)
                ratingButton("Easy", quality: 5, tint: Theme.success, row: row, card: card)
            }
            Button(AttemptHost.skipTitle) {
                skipAndFlag(card)
            }
            .font(.footnote.weight(.medium))
            .accessibilityIdentifier("flashcard.skip.rate")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func ratingButton(
        _ label: String, quality: Int, tint: Color,
        row: FlashcardProgress?, card: Flashcard
    ) -> some View {
        Button {
            rate(card, quality: quality)
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.footnote.weight(.semibold))
                Text(intervalLabel(row: row, quality: quality))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.14)))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("flashcard.rate.\(label.lowercased())")
    }

    private func intervalLabel(row: FlashcardProgress?, quality: Int) -> String {
        guard let row else { return quality < 3 ? "1d" : "1d" }
        return "\(ReviewScheduler.previewInterval(item: row, quality: quality))d"
    }

    private func rate(_ card: Flashcard, quality: Int) {
        let row = progressByCard[card.id] ?? {
            let new = FlashcardProgress(
                cardId: card.id, readingId: card.readingID, areaId: card.areaID
            )
            modelContext.insert(new)
            return new
        }()
        // Stamp the first rating before the scheduler runs: this is the only
        // record that the card was introduced, and it drives the daily pace.
        // `isBeingIntroduced` carries the reasoning and the test.
        if row.isBeingIntroduced { row.firstAttemptedAt = .now }
        ReviewScheduler.update(item: row, quality: quality)
        try? modelContext.save()

        ratedCount += 1
        advance()
    }

    private func skipAndFlag(_ card: Flashcard) {
        let row = row(for: card)
        row.flaggedForReview = true
        try? modelContext.save()
        advance()
    }

    private func toggleFlag(_ card: Flashcard) {
        let row = row(for: card)
        row.flaggedForReview.toggle()
        try? modelContext.save()
    }

    private func row(for card: Flashcard) -> FlashcardProgress {
        progressByCard[card.id] ?? {
            let new = FlashcardProgress(
                cardId: card.id, readingId: card.readingID, areaId: card.areaID
            )
            modelContext.insert(new)
            return new
        }()
    }

    private func sitAnimation(_ body: () -> Void) {
        withSittingAnimation(reduceMotion, body)
    }

    private func advance() {
        sitAnimation {
            isRevealed = false
            index += 1
        }
    }

    // MARK: - Done

    private var summary: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.success)
            Text("Deck complete")
                .font(.title3.weight(.semibold))
            Text("\(ratedCount) card\(ratedCount == 1 ? "" : "s") reviewed and rescheduled.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryCTA())
                .padding(.horizontal, 40)
                .padding(.top, 6)
        }
        .padding()
    }
}
