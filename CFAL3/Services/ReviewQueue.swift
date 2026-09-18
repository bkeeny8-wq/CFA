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
/// on a fresh install all 3,164 are "due" at once — a number that is true by
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
    /// 3,164 questions across a typical study period.
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
        /// Flagged items that would not otherwise appear (skipped-unseen or
        /// flagged-but-not-yet-due). Skip-and-flag used to write the flag and
        /// then wait on the daily new ration or the SM-2 due date.
        let flaggedCount: Int
        let flaggedInSession: Int

        /// The gate for every button that starts this session. It is the
        /// payload itself, so an enabled button always has something to run.
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
            sessionIDs: [], dueInSession: 0, newInSession: 0, overflowDue: 0,
            flaggedCount: 0, flaggedInSession: 0
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
        var flaggedExtra: [ReviewCard] = []
        for card in eligible {
            let seen = isSeen(card)
            let isDueReview = seen && card.dueDate <= now
            if card.flaggedForReview && !isDueReview {
                // Already-due flagged items ride the due lane. Everything
                // else that was flagged — a skip that never wrote an
                // Attempt, or a future-due card the candidate marked —
                // comes back now, without spending the new-question ration.
                flaggedExtra.append(card)
            }
            if seen {
                if isDueReview { due.append(card) }
            } else {
                // dueDate is ignored for unseen cards: bootstrap sets it to
                // .now for every one of them, so it carries no information.
                notStarted.append(card)
            }
        }
        let newPool = notStarted.filter { !$0.flaggedForReview }

        // Deterministic orders. Thousands of cards share a bootstrap dueDate
        // and the dictionary they came from has no stable iteration order, so
        // without a tie-break the session reshuffles on every launch.
        let introduced = introducedToday(attempts: attempts, now: now)
        let remaining = max(0, dailyNewLimit - introduced)

        // Reserve a floor for new material so a backlog cannot starve it, but
        // never at the cost of reviews: when due.count <= cap - floor, the
        // second line still admits every due card.
        let flaggedSlots = min(flaggedExtra.count, sessionCap)
        let flaggedIDs = smallestK(flaggedExtra, k: flaggedSlots) { _ in 0 }
            .map(\.questionId)
        let remainingCap = sessionCap - flaggedSlots

        let newWanted = min(remaining, newPool.count)
        let newFloor = min(minNewSlotsPerSession, remainingCap)
        let newSlots = remainingCap == 0
            ? 0
            : min(newWanted, max(newFloor, remainingCap - due.count))
        let dueSlots = min(due.count, max(0, remainingCap - newSlots))

        // Select only the slots we need instead of sorting every card. This
        // runs on each body evaluation of two screens, so a full O(n log n)
        // sort of 3,164 cards — with set operations inside the comparator —
        // was showing up as scroll hitching.
        let dueIDs = smallestK(due, k: dueSlots) { $0.dueDate.timeIntervalSinceReferenceDate }
            .map(\.questionId)
        let newIDs = smallestK(newPool, k: newSlots) {
            startedReadings.isDisjoint(with: $0.readingIds) ? 1.0 : 0.0
        }.map(\.questionId)

        let sessionIDs = flaggedIDs + interleave(reviews: dueIDs, new: newIDs)

        return Plan(
            dueCount: due.count,
            notStartedCount: notStarted.count,
            introducedToday: introduced,
            dailyNewLimit: dailyNewLimit,
            newRemainingToday: remaining,
            sessionIDs: sessionIDs,
            dueInSession: dueSlots,
            newInSession: newSlots,
            overflowDue: max(0, due.count - dueSlots),
            flaggedCount: flaggedExtra.count,
            flaggedInSession: flaggedSlots
        )
    }

    /// The `k` cards with the lowest rank, ties broken by questionId so the
    /// result is identical across launches (bootstrap gives thousands of cards
    /// the same dueDate, and the collection they came from has no stable
    /// order). O(n log k) with the rank computed once per card, rather than
    /// sorting everything and discarding all but the first few.
    static func smallestK(
        _ cards: [ReviewCard],
        k: Int,
        rank: (ReviewCard) -> Double
    ) -> [ReviewCard] {
        guard k > 0 else { return [] }
        guard cards.count > k else {
            return cards
                .map { (rank($0), $0) }
                .sorted { ($0.0, $0.1.questionId) < ($1.0, $1.1.questionId) }
                .map(\.1)
        }

        var best: [(rank: Double, card: ReviewCard)] = []
        best.reserveCapacity(k + 1)
        for card in cards {
            let r = rank(card)
            if best.count == k, let worst = best.last,
               (r, card.questionId) >= (worst.rank, worst.card.questionId) { continue }
            let entry = (rank: r, card: card)
            let index = best.firstIndex {
                (r, card.questionId) < ($0.rank, $0.card.questionId)
            } ?? best.count
            best.insert(entry, at: index)
            if best.count > k { best.removeLast() }
        }
        return best.map(\.card)
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
        if plan.flaggedInSession > 0 && plan.dueInSession == 0 && plan.newInSession == 0 {
            return "Flagged review"
        }
        if plan.dueInSession > 0 && plan.newInSession > 0 { return "Review + new" }
        if plan.newInSession > 0 { return "New questions" }
        return "Due review"
    }

    /// Home caption: when unseen material will finish at the current new-per-day
    /// pace, or that it will not finish before exam day.
    static func projectedFinishLine(
        notStarted: Int,
        dailyNewLimit: Int,
        from: Date = .now
    ) -> String? {
        guard notStarted > 0 else { return nil }
        let days = Formatting.daysUntilExam(from: from)
        if dailyNewLimit <= 0 {
            return "New questions are off — unseen won't finish before the exam"
        }
        let neededDays = Int((Double(notStarted) / Double(dailyNewLimit)).rounded(.up))
        if days > 0, neededDays > days {
            return "At \(dailyNewLimit)/day, unseen won't finish before the exam"
        }
        guard let finish = Calendar.current.date(
            byAdding: .day,
            value: neededDays,
            to: Calendar.current.startOfDay(for: from)
        ) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "Unseen finish ~\(formatter.string(from: finish))"
    }
}

/// What the review controls say, as a value.
///
/// This lives outside the views on purpose. Every test in this project used to
/// be value-in/value-out over a pure service, so the bugs that survived were
/// the ones where the plan was right and the screen reading it was wrong — a
/// launch-window guard whose condition could never be true, and a tile that
/// printed one number while starting a different session. Both are decisions,
/// not layout, so they belong somewhere a test can reach.
enum ReviewCTA {

    /// Everything the copy depends on, so a test can pose any situation
    /// without building a view or a store.
    struct Inputs {
        let plan: ReviewQueue.Plan
        /// Content finished decoding. False during the launch window.
        let contentIsLoaded: Bool
        /// Content failed to decode at all.
        let contentFailed: Bool
        /// Review cards have been seeded. False during launch and briefly
        /// after a wipe, before the re-seed runs.
        let hasSeededCards: Bool
        let typeFilter: QuestionTypeFilter
        let essaysInSession: Int

        init(
            plan: ReviewQueue.Plan,
            contentIsLoaded: Bool = true,
            contentFailed: Bool = false,
            hasSeededCards: Bool = true,
            typeFilter: QuestionTypeFilter = .mixed,
            essaysInSession: Int = 0
        ) {
            self.plan = plan
            self.contentIsLoaded = contentIsLoaded
            self.contentFailed = contentFailed
            self.hasSeededCards = hasSeededCards
            self.typeFilter = typeFilter
            self.essaysInSession = essaysInSession
        }

        /// The queue cannot be judged yet — nothing is decoded or seeded.
        var isPreparing: Bool { !contentFailed && (!contentIsLoaded || !hasSeededCards) }
    }

    static func title(_ input: Inputs) -> String {
        let plan = input.plan
        if plan.flaggedCount > 0 && plan.dueCount == 0 && plan.newInSession == 0 {
            return "Review flagged · \(plan.flaggedCount.formatted()) flagged"
        }
        if plan.dueCount > 0 && plan.newInSession > 0 {
            return "Start review · \(plan.dueCount.formatted()) due · \(plan.newInSession) new"
        }
        if plan.dueCount > 0 { return "Start review · \(plan.dueCount.formatted()) due" }
        if plan.newInSession > 0 { return "Start studying · \(plan.newInSession) new" }
        if plan.isNewOff { return "New questions are switched off" }
        if plan.isNewExhausted { return "Today's new questions are done" }
        if input.contentFailed { return "Content unavailable" }
        // Checked BEFORE "All caught up": claiming a clear queue while the
        // queue does not yet exist is the launch-window bug.
        if input.isPreparing { return "Preparing your review queue" }
        return "All caught up"
    }

    /// Large Today headline. Due/new counts when both exist; otherwise the
    /// honesty title (fresh install still reads "Start studying · N new").
    static func heroHeadline(_ input: Inputs) -> String {
        let plan = input.plan
        if plan.dueCount > 0 && plan.newInSession > 0 {
            return "\(plan.dueCount.formatted()) due · \(plan.newInSession) new"
        }
        return title(input)
    }

    static func subtitle(_ input: Inputs) -> String {
        let plan = input.plan
        guard !plan.isEmpty else {
            if input.isPreparing { return "Loading your questions…" }
            if plan.isNewOff {
                return "\(plan.notStartedCount.formatted()) not started · turn on new questions per day in Settings"
            }
            if plan.isNewExhausted {
                return "\(plan.dailyNewLimit) new resume tomorrow · \(plan.notStartedCount.formatted()) not started"
            }
            return "Build a practice session instead"
        }
        let minutes = max(5, Formatting.estimatedMinutes(
            mc: plan.sessionIDs.count - input.essaysInSession,
            essays: input.essaysInSession
        ))
        var parts = ["~\(minutes) min"]
        if plan.dueInSession > 0 && plan.newInSession > 0 {
            parts.append("\(plan.dueInSession) due + \(plan.newInSession) new")
        } else {
            parts.append("\(plan.sessionIDs.count) questions")
        }
        if plan.overflowDue > 0 { parts.append("\(plan.overflowDue.formatted()) more after this") }
        if plan.flaggedInSession > 0 { parts.append("\(plan.flaggedInSession.formatted()) flagged") }
        if input.typeFilter != .mixed { parts.append(input.typeFilter.displayName) }
        return parts.joined(separator: " · ")
    }

    /// The Progress tile. The value is the session the tile STARTS — printing
    /// the due count while gating on the session let it read a bold "0" and
    /// then run twenty questions.
    static func tile(for plan: ReviewQueue.Plan) -> (value: String, label: String) {
        guard !plan.isEmpty else { return ("0", "Nothing due") }
        let label: String
        if plan.flaggedInSession > 0 && plan.dueInSession == 0 && plan.newInSession == 0 {
            label = "Flagged"
        } else if plan.dueInSession > 0 && plan.newInSession > 0 {
            label = "Review + new"
        } else if plan.newInSession > 0 {
            label = "New today"
        } else {
            label = plan.overflowDue > 0 ? "Due (of \(plan.dueCount.formatted()))" : "Due today"
        }
        return (plan.sessionIDs.count.formatted(), label)
    }
}
