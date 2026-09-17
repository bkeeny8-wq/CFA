import Foundation

/// The flashcard counterpart to `ReviewQueue`, and it exists for the same
/// reason: `bootstrapFlashcardProgress` seeds a row per card with
/// `dueDate = .now`, and a card with no row at all also read as due, so the
/// Cards tab announced the whole deck on a fresh install. "Due" meant "exists".
///
/// It is a separate type rather than a reuse of `ReviewQueue` because the two
/// derive "introduced today" from different places. Questions have `Attempt`
/// rows carrying timestamps; flashcard ratings write none, so a card records
/// its own `firstAttemptedAt`. Sharing one service would have meant one of the
/// two queues silently computing against no data.
enum FlashcardQueue {

    static let sessionCap = 60
    static let defaultDailyNewLimit = 20
    static let newLimitOptions = [0, 5, 10, 15, 20, 30, 40, 60]
    static let minNewSlotsPerSession = 15

    struct Plan {
        let dueCount: Int
        let notStartedCount: Int
        let introducedToday: Int
        let dailyNewLimit: Int
        let newRemainingToday: Int

        let sessionIDs: [String]
        let dueInSession: Int
        let newInSession: Int
        let overflowDue: Int

        /// The gate for any button starting this session — it is the payload,
        /// so an enabled control always has cards to show.
        var isEmpty: Bool { sessionIDs.isEmpty }

        /// The user switched intake off; nothing resumes tomorrow.
        var isNewOff: Bool { dailyNewLimit == 0 && notStartedCount > 0 }

        /// Today's ration is spent but more arrives tomorrow. Distinct from
        /// `isNewOff`, which otherwise satisfies the same condition and made
        /// the UI promise a batch that would never come.
        var isNewExhausted: Bool {
            dailyNewLimit > 0 && dueCount == 0 && notStartedCount > 0 && newRemainingToday == 0
        }

        static let empty = Plan(
            dueCount: 0, notStartedCount: 0, introducedToday: 0,
            dailyNewLimit: 0, newRemainingToday: 0,
            sessionIDs: [], dueInSession: 0, newInSession: 0, overflowDue: 0
        )
    }

    /// Cards first rated today, from the recorded first-rating date. A card
    /// rated twice in one day spends one slot because it has one row.
    static func introducedToday(progress: [FlashcardProgress], now: Date = .now) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        return progress.reduce(into: 0) { count, row in
            if let first = row.firstAttemptedAt, first >= dayStart, first < dayEnd { count += 1 }
        }
    }

    /// `cards` is the deck already narrowed by whatever the screen is showing
    /// (a card-type filter, one reading), so every number the caller displays
    /// describes the same set the session will serve.
    static func plan(
        cards: [Flashcard],
        progress: [FlashcardProgress],
        dailyNewLimit: Int,
        now: Date = .now
    ) -> Plan {
        guard !cards.isEmpty else { return .empty }

        let rows = Dictionary(progress.map { ($0.cardId, $0) }, uniquingKeysWith: { a, _ in a })

        var due: [(card: Flashcard, dueDate: Date)] = []
        var notStarted: [Flashcard] = []
        for card in cards {
            // No row yet means the deck was added after the last bootstrap —
            // never seen, so it belongs in the metered lane, not in "due".
            guard let row = rows[card.id], row.totalAttempts > 0 else {
                notStarted.append(card)
                continue
            }
            if row.dueDate <= now { due.append((card, row.dueDate)) }
        }

        // Deterministic: bootstrap gives every row the same dueDate, so
        // without a tie-break the session reshuffles between launches.
        due.sort { ($0.dueDate, $0.card.id) < ($1.dueDate, $1.card.id) }
        // Keep a reading's cards together so a day's new material reads as
        // coherent material rather than a scatter across the curriculum.
        notStarted.sort { ($0.readingID, $0.id) < ($1.readingID, $1.id) }

        let introduced = introducedToday(progress: progress, now: now)
        let remaining = max(0, dailyNewLimit - introduced)

        let newWanted = min(remaining, notStarted.count)
        let newSlots = min(newWanted, max(minNewSlotsPerSession, sessionCap - due.count))
        let dueSlots = min(due.count, sessionCap - newSlots)

        let sessionIDs = ReviewQueue.interleave(
            reviews: due.prefix(dueSlots).map(\.card.id),
            new: notStarted.prefix(newSlots).map(\.id)
        )

        return Plan(
            dueCount: due.count,
            notStartedCount: notStarted.count,
            introducedToday: introduced,
            dailyNewLimit: dailyNewLimit,
            newRemainingToday: remaining,
            sessionIDs: sessionIDs,
            dueInSession: dueSlots,
            newInSession: newSlots,
            overflowDue: max(0, due.count - dueSlots)
        )
    }
}

/// What counts as the user's OWN progress, as opposed to rows the app seeds
/// for itself at launch.
///
/// Both reset buttons gate on this and the erase summary counts it. It was
/// written inline in the Settings view, which left the test guarding it able
/// only to re-implement the same conditions and compare them with themselves
/// — green regardless of what the buttons actually did.
///
/// The distinction is the whole point: a `ReviewCard` exists for all 3,157
/// questions and a `FlashcardProgress` for every card from first launch, so
/// their existence says nothing. Only a RATED card counts.
enum ResetScope {
    /// "Clear quiz attempts" — attempt history, sessions, review schedules.
    static func hasQuizHistory(attempts: [Attempt], sessions: [Session]) -> Bool {
        !attempts.isEmpty || !sessions.isEmpty
    }

    /// "Erase all progress" — the above, plus what Clear deliberately keeps.
    static func hasAnyProgress(
        attempts: [Attempt],
        sessions: [Session],
        dayCompletions: [DayCompletion],
        losStatuses: [LOSStudyStatus],
        flashcards: [FlashcardProgress]
    ) -> Bool {
        hasQuizHistory(attempts: attempts, sessions: sessions)
            || !dayCompletions.isEmpty
            || !losStatuses.isEmpty
            || flashcards.contains { $0.totalAttempts > 0 }
    }
}

extension FlashcardProgress {
    /// Whether rating this row now is the card's INTRODUCTION.
    ///
    /// Not simply "it has no date". A row written before `firstAttemptedAt`
    /// existed has no date but plenty of history, and treating that as an
    /// introduction dated an old card as new — spending a slot from today's
    /// new-card allowance on a card introduced months ago.
    var isBeingIntroduced: Bool {
        firstAttemptedAt == nil && totalAttempts == 0
    }
}
