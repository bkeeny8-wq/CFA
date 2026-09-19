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

    /// Scope is chosen exactly as Practice chooses it: three rows that open
    /// the same sheets, narrowing book → reading → LOS. Cards used to hang the
    /// whole book list inline down the page, which is a different interaction
    /// for the same job on two screens that sit next to each other.
    ///
    /// The selections are this screen's own, not Practice's: they scope
    /// different corpora (2,997 cards vs 3,164 questions) and narrowing one
    /// has no business narrowing the other.
    @State private var selectedTopics: Set<String> = []
    @State private var selectedReadings: Set<String> = []
    @State private var selectedLOS: Set<String> = []
    @State private var showTopics = false
    @State private var showReadings = false
    @State private var showLOS = false
    /// See HomeView: the daily new-card allowance is a function of "today".
    @State private var dayToken = 0

    private var areas: [CurriculumArea] { content.losMaster?.areas ?? [] }

    private func matchesFilter(_ card: Flashcard) -> Bool {
        typeFilter == nil || card.type == typeFilter
    }

    private var allFiltered: [Flashcard] { content.allFlashcards.filter(matchesFilter) }

    /// Empty selection means everything, at every level — Practice's "All".
    /// Narrowest wins, same precedence the Practice filter uses.
    private var scopedCards: [Flashcard] {
        allFiltered.filter { card in
            if !selectedTopics.isEmpty, !selectedTopics.contains(card.areaID) { return false }
            if !selectedReadings.isEmpty, !selectedReadings.contains(card.readingID) { return false }
            if !selectedLOS.isEmpty, !selectedLOS.contains(card.losID) { return false }
            return true
        }
    }

    private var topicsSummary: String {
        selectedTopics.isEmpty ? "All" : "\(selectedTopics.count)"
    }

    private var readingsSummary: String {
        selectedReadings.isEmpty ? "All" : "\(selectedReadings.count)"
    }

    private var losSummary: String {
        selectedLOS.isEmpty ? "All" : "\(selectedLOS.count)"
    }

    /// Narrowing the books narrows what a reading or LOS can mean, so drop the
    /// picks that just fell out of scope. `PracticeScope` is the same cascade
    /// the Practice builder runs.
    private func pruneScope() {
        let kept = PracticeScope.pruned(
            areas: areas,
            topics: selectedTopics,
            readings: selectedReadings,
            los: selectedLOS
        )
        if kept.readings != selectedReadings { selectedReadings = kept.readings }
        if kept.los != selectedLOS { selectedLOS = kept.los }
    }

    private func pruneLOS() {
        guard !selectedReadings.isEmpty || !selectedTopics.isEmpty else { return }
        let allowed = PracticeScope.los(
            in: areas, readings: selectedReadings, topics: selectedTopics
        )
        let kept = selectedLOS.intersection(allowed)
        if kept != selectedLOS { selectedLOS = kept }
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

                ParchmentGroup(title: "Scope") {
                    ParchmentActionRow(title: "Books", trailing: topicsSummary) {
                        showTopics = true
                    }
                    .accessibilityIdentifier("cards.scope.books")
                    ParchmentActionRow(title: "Readings", trailing: readingsSummary) {
                        showReadings = true
                    }
                    .accessibilityIdentifier("cards.scope.readings")
                    ParchmentActionRow(title: "LOS", trailing: losSummary) {
                        showLOS = true
                    }
                    .accessibilityIdentifier("cards.scope.los")

                    Label(scopeSummary(plan), systemImage: "line.3.horizontal.decrease")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                        // Combined, or a screen reader announces the symbol's
                        // own name ("Filter") instead of the summary — same
                        // reason as Practice's.
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(scopeSummary(plan))
                        .accessibilityIdentifier("cards.scopeSummary")
                }

                Text(todayFooter(plan))
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
            }
            .padding(24)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) { startBar(plan) }
        .onChange(of: selectedTopics) { _, _ in pruneScope() }
        .onChange(of: selectedReadings) { _, _ in pruneLOS() }
        .sheet(isPresented: $showTopics) {
            TopicMultiSelectSheet(
                selection: $selectedTopics,
                bookAccessibilityPrefix: "cards.topic"
            )
        }
        .sheet(isPresented: $showReadings) {
            ReadingMultiSelectSheet(
                selection: $selectedReadings,
                scopeTopics: selectedTopics,
                bookAccessibilityPrefix: "cards.book",
                readingAccessibilityPrefix: "cards.reading"
            )
        }
        .sheet(isPresented: $showLOS) {
            LOSFilterSheet(
                selectedLOS: $selectedLOS,
                readingScope: selectedReadings,
                topicScope: selectedTopics
            )
        }
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
                selectedTopics = []
                selectedReadings = []
                selectedLOS = []
            }
            .font(.subheadline.weight(.medium))
            .disabled(
                typeFilter == nil && selectedTopics.isEmpty
                    && selectedReadings.isEmpty && selectedLOS.isEmpty
            )
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
    /// Names the narrowest active level, since that is what is really deciding.
    private func scopeSummary(_ plan: FlashcardQueue.Plan) -> String {
        let scope: String
        if !selectedLOS.isEmpty {
            scope = "\(selectedLOS.count) LOS"
        } else if !selectedReadings.isEmpty {
            scope = "\(selectedReadings.count) reading\(selectedReadings.count == 1 ? "" : "s")"
        } else if !selectedTopics.isEmpty {
            scope = "\(selectedTopics.count) book\(selectedTopics.count == 1 ? "" : "s")"
        } else {
            scope = "Whole curriculum"
        }
        var parts = ["\(scope) → \(scopedCards.count.formatted()) cards"]
        if plan.dueCount > 0 { parts.append("\(plan.dueCount.formatted()) due") }
        if plan.notStartedCount > 0 { parts.append("\(plan.notStartedCount.formatted()) not started") }
        return parts.joined(separator: " · ")
    }

    /// Why the button is off, in the same place Practice explains it.
    private func emptyHint(_ plan: FlashcardQueue.Plan) -> String {
        if scopedCards.isEmpty {
            return "Widen the card type, book, reading, or LOS filters to find matching cards."
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
