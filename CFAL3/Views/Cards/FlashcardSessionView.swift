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

    var dueCount: Int = 0

    /// A SNAPSHOT, taken once. The deck arrives from an expression the parent
    /// recomputes on every body evaluation, and rating a card invalidates the
    /// parent's @Query — so a plain `let` meant each rating rebuilt the deck
    /// underneath the index walking it, skipping cards and shuffling the rest.
    @State private var cards: [Flashcard]

    init(title: String, cards: [Flashcard], dueCount: Int = 0) {
        self.dueCount = dueCount
        _cards = State(initialValue: cards)
        _ = title
    }

    @State private var index = 0
    @State private var isRevealed = false
    @State private var ratedCount = 0
    @State private var skippedCount = 0

    private var current: Flashcard? {
        guard index >= 0, index < cards.count else { return nil }
        return cards[index]
    }

    private var progressByCard: [String: FlashcardProgress] {
        Dictionary(progress.map { ($0.cardId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var remainingDue: Int {
        max(0, dueCount - ratedCount)
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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .hidesStudySelector()
        .background(Theme.paper)
        .safeAreaInset(edge: .top, spacing: 0) {
            if current != nil {
                sittingChrome
            }
        }
    }

    private var sittingChrome: some View {
        let currentIndex = min(index + 1, max(cards.count, 1))
        return SittingTopBar(
            title: "Cards · \(currentIndex) of \(cards.count)",
            progressCurrent: currentIndex,
            progressTotal: cards.count,
            showDots: false,
            hideStem: nil,
            flagged: current.map { progressByCard[$0.id]?.flaggedForReview == true } ?? false,
            onFlag: { if let card = current { toggleFlag(card) } },
            onEnd: { dismiss() },
            clock: nil,
            status: remainingDue > 0 ? "\(remainingDue) due" : nil,
            showsMeter: false,
            progressAccessibilityIdentifier: "flashcard.progress",
            progressAccessibilityLabel: "Card \(currentIndex) of \(cards.count)",
            flagIdentifier: "flashcard.flag",
            onSkip: { if let card = current { skipAndFlag(card) } },
            skipIdentifier: "flashcard.skip"
        )
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
                    .keyboardShortcut(.space, modifiers: [])
                }
            }

            ratingBar(card)
        }
    }

    /// The card itself. Used as a Button's label before the answer is shown
    /// and as plain content after, so the revealed text stays selectable.
    private func cardBody(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            typeBadge(card)

            Text(card.front)
                .font(Theme.serif(.title, weight: .semibold))
                .foregroundStyle(Theme.ink)
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
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .textSelection(.enabled)
                }

                Text(card.back)
                    .font(Theme.serif(.title3))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let m = card.mnemonic, !m.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(m)
                        .font(.callout)
                        .foregroundStyle(Theme.dust)
                        .padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Tap to reveal")
                    .font(.footnote)
                    .foregroundStyle(Theme.dust)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.sittingCardRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 6)
        .padding(.horizontal, 20)
        .readableContentWidth()
        .padding(.top, 8)
    }

    private func typeBadge(_ card: Flashcard) -> some View {
        HStack(spacing: 8) {
            Text(card.type.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().strokeBorder(Theme.pine.opacity(0.45), lineWidth: 1))
                .foregroundStyle(Theme.pine)

            if card.difficulty == .stretch {
                Text("Stretch")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.copper.opacity(0.18)))
                    .foregroundStyle(Theme.copper)
            }
            Spacer()
        }
    }

    // MARK: - Rating

    private func ratingBar(_ card: Flashcard) -> some View {
        let row = progressByCard[card.id]
        return HStack(spacing: 10) {
            ratingButton("Again", quality: 1, tint: Theme.copper, shortcut: "1", row: row, card: card)
            ratingButton("Hard", quality: 3, tint: Theme.ink, shortcut: "2", row: row, card: card)
            ratingButton("Good", quality: 4, tint: Theme.pine, shortcut: "3", row: row, card: card)
            ratingButton("Easy", quality: 5, tint: Theme.pine, shortcut: "4", row: row, card: card)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .opacity(isRevealed ? 1 : 0.38)
        .allowsHitTesting(isRevealed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isRevealed ? "Rate this card" : "Rate after you reveal")
    }

    private func ratingButton(
        _ label: String, quality: Int, tint: Color, shortcut: KeyEquivalent,
        row: FlashcardProgress?, card: Flashcard
    ) -> some View {
        Button {
            rate(card, quality: quality)
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(Theme.serif(.title3, weight: .semibold))
                Text(intervalLabel(row: row, quality: quality))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.dust)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.55), lineWidth: 1.5)
            )
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: [])
        .frame(minHeight: 64)
        .accessibilityLabel("\(label), \(intervalLabel(row: row, quality: quality))")
        .accessibilityIdentifier("flashcard.rate.\(label.lowercased())")
    }

    private func intervalLabel(row: FlashcardProgress?, quality: Int) -> String {
        if quality < 3 { return "10m" }
        guard let row else { return "1d" }
        return "\(ReviewScheduler.previewInterval(item: row, quality: quality))d"
    }

    private func rate(_ card: Flashcard, quality: Int) {
        guard isRevealed else { return }
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
        skippedCount += 1
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
                .accessibilityAddTraits(.isHeader)
            Text(deckCompleteCopy)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryCTA())
                .padding(.horizontal, 40)
                .padding(.top, 6)
        }
        .padding()
    }

    private var deckCompleteCopy: String {
        let reviewed = "\(ratedCount) card\(ratedCount == 1 ? "" : "s") reviewed and rescheduled"
        if skippedCount == 0 { return "\(reviewed)." }
        return "\(reviewed). \(skippedCount) skipped & flagged."
    }
}
