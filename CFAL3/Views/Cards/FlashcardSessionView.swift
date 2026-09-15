import SwiftUI
import SwiftData

/// A single pass through a deck: show the prompt, reveal on tap, then rate.
/// The rating feeds the same SM-2 scheduler the question review uses, so a
/// card's next appearance is earned rather than fixed.
struct FlashcardSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
                    description: Text("This deck has no cards due right now.")
                )
            } else if let card = current {
                cardScreen(card)
            } else {
                summary
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if current != nil {
                    Text("\(index + 1) / \(cards.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func cardScreen(_ card: Flashcard) -> some View {
        VStack(spacing: 0) {
            ScrollView {
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
                .padding(.top, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isRevealed { withAnimation(.snappy) { isRevealed = true } }
                }
            }

            if isRevealed {
                ratingBar(card)
            }
        }
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
        return HStack(spacing: 8) {
            ratingButton("Again", quality: 1, tint: Theme.danger, row: row, card: card)
            ratingButton("Hard", quality: 3, tint: Theme.warning, row: row, card: card)
            ratingButton("Good", quality: 4, tint: Theme.accent, row: row, card: card)
            ratingButton("Easy", quality: 5, tint: Theme.success, row: row, card: card)
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
        if row.firstAttemptedAt == nil { row.firstAttemptedAt = .now }
        ReviewScheduler.update(item: row, quality: quality)
        try? modelContext.save()

        ratedCount += 1
        withAnimation(.snappy) {
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
