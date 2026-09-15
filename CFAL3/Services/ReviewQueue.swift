import Foundation

/// Builds the review session for every screen that offers one.
///
/// This exists because the count a screen displayed and the session that
/// screen started were computed by two different predicates: the count was
/// raw `dueDate <= now`, the session applied a type filter and a gradability
/// gate on top. So a button could advertise thousands of questions, be
/// enabled, and do nothing when tapped. Now both read the same `Plan` — the
/// number shown IS `sessionIDs.count`'s pool, so they cannot drift.
///
/// It also meters how much unseen material enters a session.
/// `bootstrapReviewCards` seeds a card per question with `dueDate = .now`, so
/// on a fresh install all 3,115 are "due" at once — a number that is true by
/// the letter and useless in practice. Cards the user has never answered are
/// a separate lane, rationed per day.
///
/// Pure by design: no SwiftData fetches, no ContentLoader, no SwiftUI. It
/// takes what the caller already has in scope and returns a value.
///
/// NOT reusable for flashcards. `FlashcardsHomeView` has the same
/// everything-is-due shape, but flashcard ratings never write an `Attempt`,
/// so the first-seen signal this service derives from does not exist there.
enum ReviewQueue {

    /// Questions per session. Was a named constant in one view and a bare
    /// literal in another; they had already drifted apart in spirit.
    static let sessionCap = 60

    /// Never-seen questions introduced per day. Roughly the pace that covers
    /// 3,115 questions across a typical study period.
    static let defaultDailyNewLimit = 20

    static let newLimitOptions = [0, 5, 10, 15, 20, 30, 40, 60]

    /// Even with a large backlog, some unseen material still gets in — or a
    /// user who falls behind never sees the rest of the curriculum.
    static let minNewSlotsPerSession = 15

    // MARK: - Plan

    struct Plan {
        /// Already-answered questions whose interval has elapsed, after the
        /// eligibility gate. Reviews are never rationed.
        let dueCount: Int
        /// Questions never answered, after the eligibility gate.
        let notStartedCount: Int
        let introducedToday: Int
        let dailyNewLimit: Int
        let newRemainingToday: Int

        let sessionIDs: [String]
        let dueInSession: Int
        let newInSession: Int
        /// Due questions that did not fit under the cap.
        let overflowDue: Int

        /// The gate for every button that starts this session. It is the
        /// payload itself, so an enabled button always has something to run.
        var isEmpty: Bool { sessionIDs.isEmpty }

        /// True when there is unseen material left but today's ration is
        /// spent — "come back tomorrow", not "all caught up".
        var isNewExhausted: Bool {
            dueCount == 0 && notStartedCount > 0 && newRemainingToday == 0
        }

        static let empty = Plan(
            dueCount: 0, notStartedCount: 0, introducedToday: 0,
            dailyNewLimit: 0, newRemainingToday: 0,
            sessionIDs: [], dueInSession: 0, newInSession: 0, overflowDue: 0
        )
    }

    // MARK: - Eligibility

    /// The one copy of a predicate that used to be duplicated verbatim in two
    /// views. An unknown id returns false, which also quietly drops orphan
    /// cards left behind by a question that a content update removed —
    /// otherwise they stay due forever and can never be answered.
    static func eligibility(
        content: ContentLoader,
        typeFilter: QuestionTypeFilter
    ) -> (String) -> Bool {
        { questionID in
            if let q = content.question(id: questionID) {
                return typeFilter.allows(q.type) && (q.type != .mc || q.canGradeMC)
            }
            if let d = content.drillQuestion(id: questionID) {
                return typeFilter.allows(d.type) && d.correct != nil
            }
            return false
        }
    }

    // MARK: - Daily allowance

    /// How many never-before-answered questions were first answered today.
    ///
    /// Derived, never stored: an "introduction" is the earliest `Attempt` for
    /// a questionId, and it counts if that earliest attempt falls inside
    /// today. Nothing to reset at midnight, nothing to desynchronize, and
    /// answering the same new question twice in a day spends one slot because
    /// it is one key.
    ///
    /// Deliberately NOT eligibility-filtered: if it were, switching the type
    /// filter mid-day would refund the day's allowance.
    static func introducedToday(attempts: [Attempt], now: Date = .now) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }

        var firstSeen: [String: Date] = [:]
        for attempt in attempts {
            if let existing = firstSeen[attempt.questionId] {
                if attempt.timestamp < existing { firstSeen[attempt.questionId] = attempt.timestamp }
            } else {
                firstSeen[attempt.questionId] = attempt.timestamp
            }
        }
        return firstSeen.values.reduce(into: 0) { count, first in
            if first >= dayStart && first < dayEnd { count += 1 }
        }
    }

    // MARK: - Plan construction

    static func plan(
        cards: [ReviewCard],
        attempts: [Attempt],
        dailyNewLimit: Int,
        isEligible: (String) -> Bool,
        now: Date = .now
    ) -> Plan {
        // A card counts as seen if EITHER source says so, and both halves are
        // load-bearing. `Attempt` is inserted when an answer is submitted, but
        // `totalAttempts` is only incremented later, when the grading screen
        // is dismissed forward — so backing out of grading leaves an Attempt
        // with totalAttempts still 0. Restoring a backup can do the reverse.
        let attemptedIDs = Set(attempts.map(\.questionId))
        func isSeen(_ card: ReviewCard) -> Bool {
            card.totalAttempts > 0 || attemptedIDs.contains(card.questionId)
        }

        let eligible = cards.filter { isEligible($0.questionId) }

        // Readings the user has already touched, so unseen questions from
        // material they are actually studying come first. Derived here rather
        // than queried, so both screens compute the same order for free.
        var startedReadings = Set<String>()
        for card in eligible where isSeen(card) {
            startedReadings.formUnion(card.readingIds)
        }

        var due: [ReviewCard] = []
        var notStarted: [ReviewCard] = []
        for card in eligible {
            if isSeen(card) {
                if card.dueDate <= now { due.append(card) }
            } else {
                // dueDate is ignored for unseen cards: bootstrap sets it to
                // .now for every one of them, so it carries no information.
                notStarted.append(card)
            }
        }

        // Deterministic orders. Thousands of cards share a bootstrap dueDate
        // and the dictionary they came from has no stable iteration order, so
        // without a tie-break the session reshuffles on every launch.
        due.sort { ($0.dueDate, $0.questionId) < ($1.dueDate, $1.questionId) }
        notStarted.sort {
            let lhs = (startedReadings.isDisjoint(with: $0.readingIds) ? 1 : 0, $0.caseId, $0.questionId)
            let rhs = (startedReadings.isDisjoint(with: $1.readingIds) ? 1 : 0, $1.caseId, $1.questionId)
            return lhs < rhs
        }

        let introduced = introducedToday(attempts: attempts, now: now)
        let remaining = max(0, dailyNewLimit - introduced)

        // Reserve a floor for new material so a backlog cannot starve it, but
        // never at the cost of reviews: when due.count <= cap - floor, the
        // second line still admits every due card.
        let newWanted = min(remaining, notStarted.count)
        let newSlots = min(newWanted, max(minNewSlotsPerSession, sessionCap - due.count))
        let dueSlots = min(due.count, sessionCap - newSlots)

        let sessionIDs = interleave(
            reviews: due.prefix(dueSlots).map(\.questionId),
            new: notStarted.prefix(newSlots).map(\.questionId)
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

    /// Spread new questions evenly through the session instead of stacking
    /// them at one end, preserving each lane's own order.
    static func interleave(reviews: [String], new: [String]) -> [String] {
        guard !new.isEmpty else { return reviews }
        guard !reviews.isEmpty else { return new }

        var out: [String] = []
        out.reserveCapacity(reviews.count + new.count)
        let step = Double(reviews.count + new.count) / Double(new.count)
        var nextNewAt = 0.0
        var r = 0, n = 0

        while r < reviews.count || n < new.count {
            if n < new.count, Double(out.count) >= nextNewAt {
                out.append(new[n]); n += 1; nextNewAt += step
            } else if r < reviews.count {
                out.append(reviews[r]); r += 1
            } else {
                out.append(new[n]); n += 1; nextNewAt += step
            }
        }
        return out
    }

    /// What to call the session in history, so an all-new session is not
    /// filed as "Due review".
    static func sessionLabel(for plan: Plan) -> String {
        if plan.dueInSession > 0 && plan.newInSession > 0 { return "Review + new" }
        if plan.newInSession > 0 { return "New questions" }
        return "Due review"
    }
}
