import SwiftUI
import SwiftData

/// Deck browser for Cards: today's mix, then Practice’s reading selector
/// (Select all / Clear, books collapsed until expanded).
struct FlashcardsHomeView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(TabRouter.self) private var router
    @Query private var progress: [FlashcardProgress]

    @Environment(PracticeBuilderPreference.self) private var practicePref
    @State private var typeFilter: FlashcardType?
    @State private var selectedReadings: Set<String> = []
    /// See HomeView: the daily new-card allowance is a function of "today".
    @State private var dayToken = 0

    private var areas: [CurriculumArea] { content.losMaster?.areas ?? [] }

    private func matchesFilter(_ card: Flashcard) -> Bool {
        typeFilter == nil || card.type == typeFilter
    }

    private var allFiltered: [Flashcard] { content.allFlashcards.filter(matchesFilter) }

    /// Empty selection means every reading, matching Practice’s “All”.
    private var scopedCards: [Flashcard] {
        guard !selectedReadings.isEmpty else { return allFiltered }
        return allFiltered.filter { selectedReadings.contains($0.readingID) }
    }

    /// The count shown and the deck handed to the session are the same value.
    private var plan: FlashcardQueue.Plan {
        FlashcardQueue.plan(
            cards: scopedCards,
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
        .toolbar(.hidden, for: .navigationBar)
        .background(Theme.paper)
        .onAppear { content.bootstrapFlashcardProgress(context: modelContext) }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            // No .id() here: mutating this @State already re-runs body, and
            // re-identifying the view would tear down the hierarchy — popping
            // an in-progress session at midnight.
            dayToken &+= 1
        }
    }

    /// Laid out like Practice, deliberately: header with a Reset, one settings
    /// card, the scope picker, a one-line scope summary, and the action pinned
    /// to the bottom.
    ///
    /// The starting actions used to be rows at the TOP, above the book list.
    /// That reads fine on a phone, but this is an iPad app: choosing books
    /// scrolls the thing you are choosing them FOR off the top of the screen.
    /// Practice already solved that with a pinned CTA, so Cards uses the same
    /// shape.
    private var list: some View {
        let plan = plan
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(alignment: .leading, spacing: 16) {
                    Picker("Card type", selection: $typeFilter) {
                        Text("All").tag(FlashcardType?.none)
                        ForEach(FlashcardType.allCases) { t in
                            Text(t.displayName).tag(FlashcardType?.some(t))
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("New cards per day", selection: Bindable(practicePref).dailyNewFlashcardLimit) {
                        ForEach(FlashcardQueue.newLimitOptions, id: \.self) { limit in
                            Text(limit == 0 ? "Off" : "\(limit)").tag(limit)
                        }
                    }
                    .pickerStyle(.menu)

                    ParchmentActionRow(title: "Shuffle all", trailing: scopedCards.count.formatted()) {
                        router.presentFlashcards(title: "Shuffle all", cards: scopedCards.shuffled())
                    }
                    .disabled(scopedCards.isEmpty)
                    .accessibilityIdentifier("cards.shuffleAll")
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.cardFill)
                        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
                )

                BookReadingPicker(
                    areas: areas,
                    selection: $selectedReadings,
                    bookAccessibilityPrefix: "cards.book",
                    readingAccessibilityPrefix: "cards.reading"
                )

                Label(scopeSummary(plan), systemImage: "line.3.horizontal.decrease")
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
                    // Combined, or a screen reader announces the symbol's own
                    // name ("Filter") instead of the summary — same reason as
                    // Practice's.
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(scopeSummary(plan))
                    .accessibilityIdentifier("cards.scopeSummary")

                Text(todayFooter(plan))
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
            }
            .padding(24)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) { startBar(plan) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cards")
                    .font(Theme.serif(.largeTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("One idea per back. Same Again / Hard / Good / Easy as questions.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dust)
            }
            Spacer()
            Button("Reset", role: .destructive) {
                typeFilter = nil
                selectedReadings = []
            }
            .font(.subheadline.weight(.medium))
            .disabled(typeFilter == nil && selectedReadings.isEmpty)
            .accessibilityIdentifier("cards.reset")
        }
    }

    /// The same bottom bar as Practice: one primary action, the hint above it
    /// when there is nothing to start, and the whole thing capped to the width
    /// of the form it belongs to.
    private func startBar(_ plan: FlashcardQueue.Plan) -> some View {
        let byID = Dictionary(
            content.allFlashcards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }
        )
        return VStack(spacing: 8) {
            if plan.isEmpty {
                Text(emptyHint(plan))
                    .font(.footnote)
                    .foregroundStyle(Theme.dust)
                    .multilineTextAlignment(.center)
            }
            Button {
                router.presentFlashcards(
                    title: plan.newInSession > 0 && plan.dueInSession == 0 ? "New cards" : "Today's cards",
                    cards: plan.sessionIDs.compactMap { byID[$0] }
                )
            } label: {
                Text(plan.isEmpty ? todayLabel(plan) : "\(todayLabel(plan)) · \(plan.sessionIDs.count)")
            }
            .buttonStyle(PrimaryCTA())
            .disabled(plan.isEmpty)
            .accessibilityIdentifier("cards.today")
            .accessibilityHint(plan.isEmpty ? emptyHint(plan) : "\(plan.sessionIDs.count) cards in today's mix")
        }
        .padding(.horizontal)
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .background(Theme.paper)
    }

    /// One line, like Practice's "5 per book in scope → 30 questions".
    private func scopeSummary(_ plan: FlashcardQueue.Plan) -> String {
        let scope = selectedReadings.isEmpty
            ? "All readings"
            : "\(selectedReadings.count) reading\(selectedReadings.count == 1 ? "" : "s")"
        var parts = ["\(scope) → \(scopedCards.count.formatted()) cards"]
        if plan.dueCount > 0 { parts.append("\(plan.dueCount.formatted()) due") }
        if plan.notStartedCount > 0 { parts.append("\(plan.notStartedCount.formatted()) not started") }
        return parts.joined(separator: " · ")
    }

    /// Why the button is off, in the same place Practice explains it.
    private func emptyHint(_ plan: FlashcardQueue.Plan) -> String {
        if scopedCards.isEmpty {
            return "Widen the card type or book selection to find matching cards."
        }
        if plan.isNewOff {
            return "New cards are switched off. Turn them back on above, or in Settings."
        }
        if plan.isNewExhausted {
            return "Today's new cards are done. \(plan.dailyNewLimit) more resume tomorrow."
        }
        return "Nothing is due in this scope yet."
    }

    private func todayLabel(_ plan: FlashcardQueue.Plan) -> String {
        if plan.flaggedInSession > 0 && plan.dueInSession == 0 && plan.newInSession == 0 {
            return "Review flagged"
        }
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
        if plan.flaggedCount > 0 { parts.append("\(plan.flaggedCount.formatted()) flagged") }
        if plan.notStartedCount > 0 { parts.append("\(plan.notStartedCount.formatted()) not started") }

        if plan.isNewOff {
            parts.append("new cards are off — turn them on in Settings")
        } else if plan.isNewExhausted {
            parts.append("\(plan.dailyNewLimit) new resume tomorrow")
        }
        return parts.isEmpty ? base : parts.joined(separator: " · ") + ". " + base
    }
}
