import SwiftUI
import SwiftData

/// Deck browser for the Cards tab: what's due now, then every book and its
/// readings with per-deck counts. Mirrors the Study tab's book → reading shape
/// so the two tabs navigate the same way.
struct FlashcardsHomeView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Query private var progress: [FlashcardProgress]

    @Environment(PracticeBuilderPreference.self) private var practicePref
    @State private var typeFilter: FlashcardType?

    private var areas: [CurriculumArea] { content.losMaster?.areas ?? [] }

    private var rowsByCard: [String: FlashcardProgress] {
        Dictionary(progress.map { ($0.cardId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func matchesFilter(_ card: Flashcard) -> Bool {
        typeFilter == nil || card.type == typeFilter
    }

    /// Only a card that has actually been rated can come back as due. A card
    /// with no row, or a row with no ratings, has never been seen — counting
    /// those as due made a fresh install announce the entire deck.
    private func isDue(_ card: Flashcard, now: Date = .now) -> Bool {
        guard let row = rowsByCard[card.id], row.totalAttempts > 0 else { return false }
        return row.dueDate <= now
    }

    private func cards(for reading: Reading) -> [Flashcard] {
        content.flashcards(forReading: reading.id).filter(matchesFilter)
    }

    private var allFiltered: [Flashcard] { content.allFlashcards.filter(matchesFilter) }

    /// The count shown and the deck handed to the session are the same value.
    private var plan: FlashcardQueue.Plan {
        FlashcardQueue.plan(
            cards: allFiltered,
            progress: progress,
            dailyNewLimit: practicePref.dailyNewFlashcardLimit
        )
    }

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
                let plan = plan
                let byID = Dictionary(
                    content.allFlashcards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }
                )
                NavigationLink {
                    FlashcardSessionView(
                        title: plan.newInSession > 0 && plan.dueInSession == 0 ? "New cards" : "Today's cards",
                        cards: plan.sessionIDs.compactMap { byID[$0] }
                    )
                } label: {
                    HStack {
                        Label(todayLabel(plan), systemImage: "bolt.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Text("\(plan.sessionIDs.count)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(plan.isEmpty ? .secondary : Theme.accent)
                    }
                }
                .disabled(plan.isEmpty)

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
                Text(todayFooter(plan))
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

    private func todayLabel(_ plan: FlashcardQueue.Plan) -> String {
        if plan.dueInSession > 0 && plan.newInSession > 0 { return "Review + new" }
        if plan.newInSession > 0 { return "Start new cards" }
        if plan.dueInSession > 0 { return "Review due" }
        if plan.isNewExhausted { return "Today's new cards are done" }
        return "All caught up"
    }

    private func todayFooter(_ plan: FlashcardQueue.Plan) -> String {
        let base = "Cards use the same spaced-repetition schedule as question review, tracked separately."
        if plan.isNewExhausted {
            return "\(plan.dailyNewLimit) new cards resume tomorrow · \(plan.notStartedCount.formatted()) not started. " + base
        }
        if plan.notStartedCount > 0 {
            return "\(plan.dueCount.formatted()) due · \(plan.notStartedCount.formatted()) not started. " + base
        }
        return base
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
