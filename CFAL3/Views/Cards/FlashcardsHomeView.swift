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

    private var list: some View {
        let plan = plan
        let byID = Dictionary(
            content.allFlashcards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cards")
                        .font(Theme.serif(.largeTitle, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("One idea per back. Same Again / Hard / Good / Easy as questions.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dust)
                }

                ParchmentGroup {
                    Button {
                        router.presentFlashcards(
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
                                .foregroundStyle(plan.isEmpty ? Theme.dust : Theme.accent)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(plan.isEmpty)
                    .accessibilityIdentifier("cards.today")
                    .accessibilityHint(plan.isEmpty ? todayFooter(plan) : "\(plan.sessionIDs.count) cards in today's mix")

                    Button {
                        router.presentFlashcards(title: "Shuffle all", cards: scopedCards.shuffled())
                    } label: {
                        HStack {
                            Label("Shuffle all", systemImage: "shuffle")
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(scopedCards.count)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(Theme.dust)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Picker("Card type", selection: $typeFilter) {
                        Text("All").tag(FlashcardType?.none)
                        ForEach(FlashcardType.allCases) { t in
                            Text(t.displayName).tag(FlashcardType?.some(t))
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 8)

                    Text(todayFooter(plan))
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                }

                BookReadingPicker(
                    areas: areas,
                    selection: $selectedReadings,
                    bookAccessibilityPrefix: "cards.book",
                    readingAccessibilityPrefix: "cards.reading"
                )
            }
            .padding(24)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
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
