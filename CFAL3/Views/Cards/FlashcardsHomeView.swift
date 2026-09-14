import SwiftUI
import SwiftData

/// Deck browser for the Cards tab: what's due now, then every book and its
/// readings with per-deck counts. Mirrors the Study tab's book → reading shape
/// so the two tabs navigate the same way.
struct FlashcardsHomeView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Query private var progress: [FlashcardProgress]

    @State private var typeFilter: FlashcardType?

    private var areas: [CurriculumArea] { content.losMaster?.areas ?? [] }

    private var dueByCard: [String: FlashcardProgress] {
        Dictionary(progress.map { ($0.cardId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func matchesFilter(_ card: Flashcard) -> Bool {
        typeFilter == nil || card.type == typeFilter
    }

    /// A card with no progress row yet counts as due — a freshly added deck
    /// should never look empty.
    private func isDue(_ card: Flashcard, now: Date = .now) -> Bool {
        guard let row = dueByCard[card.id] else { return true }
        return row.dueDate <= now
    }

    private func cards(for reading: Reading) -> [Flashcard] {
        content.flashcards(forReading: reading.id).filter(matchesFilter)
    }

    private var allFiltered: [Flashcard] { content.allFlashcards.filter(matchesFilter) }
    private var dueCards: [Flashcard] { allFiltered.filter { isDue($0) } }

    var body: some View {
        Group {
            if content.allFlashcards.isEmpty {
                ContentUnavailableView(
                    "No cards bundled",
                    systemImage: "rectangle.on.rectangle.angled",
                    description: Text("flashcards.json isn't in this build.")
                )
            } else {
                list
            }
        }
        .navigationTitle("Cards")
        .onAppear { content.bootstrapFlashcardProgress(context: modelContext) }
    }

    private var list: some View {
        List {
            Section {
                NavigationLink {
                    FlashcardSessionView(
                        title: "Due now",
                        cards: dueCards.shuffled()
                    )
                } label: {
                    HStack {
                        Label("Review due", systemImage: "bolt.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Text("\(dueCards.count)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(dueCards.isEmpty ? .secondary : Theme.accent)
                    }
                }
                .disabled(dueCards.isEmpty)

                NavigationLink {
                    FlashcardSessionView(title: "Shuffle all", cards: allFiltered.shuffled())
                } label: {
                    HStack {
                        Label("Shuffle all", systemImage: "shuffle")
                        Spacer()
                        Text("\(allFiltered.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Cards are scheduled with the same spaced-repetition algorithm as question review, tracked separately.")
            }

            Section("Card type") {
                Picker("Card type", selection: $typeFilter) {
                    Text("All").tag(FlashcardType?.none)
                    ForEach(FlashcardType.allCases) { t in
                        Text(t.displayName).tag(FlashcardType?.some(t))
                    }
                }
                .pickerStyle(.segmented)
            }

            ForEach(areas) { area in
                let readings = area.readings.filter { !cards(for: $0).isEmpty }
                if !readings.isEmpty {
                    Section(area.name) {
                        ForEach(readings) { reading in
                            deckRow(reading)
                        }
                    }
                }
            }
        }
    }

    private func deckRow(_ reading: Reading) -> some View {
        let deck = cards(for: reading)
        let due = deck.filter { isDue($0) }.count
        return NavigationLink {
            FlashcardSessionView(title: reading.name, cards: deck)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reading.name)
                        .font(.subheadline)
                        .lineLimit(2)
                    Text("\(deck.count) card\(deck.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if due > 0 {
                    Text("\(due) due")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accent.opacity(0.15)))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
