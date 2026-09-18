import SwiftUI
import SwiftData

/// Deck browser for the Cards half of the Study tab: what's due now, then
/// every book and its readings with per-deck counts. It shares Study's
/// book → reading shape, which is why the two fold together behind one menu.
struct FlashcardsHomeView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Query private var progress: [FlashcardProgress]

    @Environment(PracticeBuilderPreference.self) private var practicePref
    @State private var typeFilter: FlashcardType?
    /// See HomeView: the daily new-card allowance is a function of "today".
    @State private var dayToken = 0

    private var areas: [CurriculumArea] { content.losMaster?.areas ?? [] }

    /// Built ONCE per body evaluation and threaded through the rows. As a
    /// computed property it was rebuilt on every `isDue` call — every card
    /// reconstructing a dictionary of the whole deck, on the main thread.
    private func makeRows() -> [String: FlashcardProgress] {
        Dictionary(progress.map { ($0.cardId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func matchesFilter(_ card: Flashcard) -> Bool {
        typeFilter == nil || card.type == typeFilter
    }

    /// Only a card that has actually been rated can come back as due. A card
    /// with no row, or a row with no ratings, has never been seen — counting
    /// those as due made a fresh install announce the entire deck.
    private func isDue(
        _ card: Flashcard,
        rows: [String: FlashcardProgress],
        now: Date = .now
    ) -> Bool {
        guard let row = rows[card.id], row.totalAttempts > 0 else { return false }
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
                    "No flashcards in this copy",
                    systemImage: "rectangle.on.rectangle.angled",
                    description: Text("The card deck didn't ship with this build. Reinstall the app from the project.")
                )
            } else {
                list
            }
        }
        .navigationTitle("Cards")
        .onAppear { content.bootstrapFlashcardProgress(context: modelContext) }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            // No .id() here: mutating this @State already re-runs body, and
            // re-identifying the view would tear down the hierarchy — popping
            // an in-progress session at midnight.
            dayToken &+= 1
        }
    }

    private var list: some View {
        // Both maps built once here and threaded down, rather than rebuilt
        // inside every row.
        let rows = makeRows()
        let plan = plan
        let byID = Dictionary(
            content.allFlashcards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }
        )
        return List {
            Section {
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
                .accessibilityIdentifier("cards.today")

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
                            deckRow(reading, rows: rows)
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
        if plan.isNewOff { return "New cards are switched off" }
        if plan.isNewExhausted { return "Today's new cards are done" }
        return "All caught up"
    }

    /// Always states the real due total and any overflow. Showing only the
    /// session size hid the backlog completely once every card was started.
    private func todayFooter(_ plan: FlashcardQueue.Plan) -> String {
        let base = "Cards use the same spaced-repetition schedule as question review, tracked separately."
        var parts: [String] = []
        if plan.dueCount > 0 { parts.append("\(plan.dueCount.formatted()) due") }
        if plan.overflowDue > 0 { parts.append("\(plan.overflowDue.formatted()) after this session") }
        if plan.notStartedCount > 0 { parts.append("\(plan.notStartedCount.formatted()) not started") }

        if plan.isNewOff {
            parts.append("new cards are off — turn them on in Settings")
        } else if plan.isNewExhausted {
            parts.append("\(plan.dailyNewLimit) new resume tomorrow")
        }
        return parts.isEmpty ? base : parts.joined(separator: " · ") + ". " + base
    }

    private func deckRow(_ reading: Reading, rows: [String: FlashcardProgress]) -> some View {
        let deck = cards(for: reading)
        let due = deck.filter { isDue($0, rows: rows) }.count
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
