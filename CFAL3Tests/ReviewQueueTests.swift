import XCTest
@testable import CFAL3

/// Pins the behaviour of the shared review queue. The bug these guard against:
/// every card is seeded `dueDate = .now`, so "due" meant "exists", and the
/// count a screen displayed was computed by a different predicate than the
/// session it launched.
final class ReviewQueueTests: XCTestCase {

    private func card(
        _ id: String,
        attempts: Int = 0,
        due: Date = .now,
        readings: [String] = ["r1"],
        caseId: String = "c1"
    ) -> ReviewCard {
        let c = ReviewCard(
            questionId: id, caseId: caseId, topicId: "t1",
            readingIds: readings, losIds: ["los1"]
        )
        c.totalAttempts = attempts
        c.dueDate = due
        return c
    }

    private func attempt(_ questionID: String, at timestamp: Date) -> Attempt {
        Attempt(
            questionId: questionID, caseId: "c1", topicId: "t1",
            timestamp: timestamp, durationSeconds: 30
        )
    }

    private let allEligible: (String) -> Bool = { _ in true }

    private func plan(
        cards: [ReviewCard],
        attempts: [Attempt] = [],
        limit: Int = 20,
        eligible: @escaping (String) -> Bool = { _ in true },
        now: Date = .now
    ) -> ReviewQueue.Plan {
        ReviewQueue.plan(
            cards: cards, attempts: attempts,
            dailyNewLimit: limit, isEligible: eligible, now: now
        )
    }

    // MARK: - The reported bug

    func testFreshInstallHasNothingDueAndEverythingNotStarted() {
        let p = plan(cards: (1...3).map { card("q\($0)") })
        XCTAssertEqual(p.dueCount, 0, "a never-answered question is not 'due'")
        XCTAssertEqual(p.notStartedCount, 3)
        XCTAssertEqual(p.sessionIDs.count, 3)
    }

    func testDailyLimitCapsHowMuchNewMaterialEnters() {
        let p = plan(cards: (1...3_115).map { card("q\($0)") })
        XCTAssertEqual(p.newRemainingToday, 20)
        XCTAssertEqual(p.sessionIDs.count, 20)
        XCTAssertEqual(p.notStartedCount, 3_115)
    }

    func testOnceTodaysAllowanceIsSpentTheQueueIsEmptyButNotCaughtUp() {
        let cards = (1...100).map { card("q\($0)", attempts: $0 <= 20 ? 1 : 0,
                                          due: $0 <= 20 ? .now.addingTimeInterval(86_400) : .now) }
        let attempts = (1...20).map { attempt("q\($0)", at: .now) }
        let p = plan(cards: cards, attempts: attempts)
        XCTAssertEqual(p.newRemainingToday, 0)
        XCTAssertTrue(p.isEmpty)
        XCTAssertTrue(p.isNewExhausted, "should say 'come back tomorrow', not 'all caught up'")
    }

    // MARK: - Deriving today's introductions

    func testSameQuestionTwiceInADaySpendsOneSlot() {
        let attempts = [attempt("q1", at: .now), attempt("q1", at: .now)]
        XCTAssertEqual(ReviewQueue.introducedToday(attempts: attempts), 1)
    }

    func testAQuestionFirstSeenYesterdayIsNotAnIntroductionToday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let attempts = [attempt("q1", at: yesterday), attempt("q1", at: .now)]
        XCTAssertEqual(ReviewQueue.introducedToday(attempts: attempts), 0)
    }

    // MARK: - The seen test is a union, and both halves matter

    func testAttemptWithoutTotalAttemptsCountsAsSeen() {
        // Backing out of the grading screen persists an Attempt but never
        // increments totalAttempts. Such a card is a review, not new material.
        let p = plan(cards: [card("q1", attempts: 0)], attempts: [attempt("q1", at: .now)])
        XCTAssertEqual(p.notStartedCount, 0, "an answered question must not be offered as new")
        XCTAssertEqual(p.dueCount, 1)
    }

    func testTotalAttemptsWithoutAttemptRowsCountsAsSeen() {
        // A restored backup can carry card state without the Attempt rows.
        let p = plan(cards: [card("q1", attempts: 3)], attempts: [])
        XCTAssertEqual(p.notStartedCount, 0)
        XCTAssertEqual(p.dueCount, 1)
    }

    // MARK: - Session composition

    func testNewMaterialKeepsAFloorWhenTheBacklogIsLarge() {
        let due = (1...500).map { card("due\($0)", attempts: 1, due: .now.addingTimeInterval(-60)) }
        let fresh = (1...500).map { card("new\($0)") }
        let p = plan(cards: due + fresh)
        XCTAssertEqual(p.newInSession, 15, "a backlog must not starve new material")
        XCTAssertEqual(p.dueInSession, 45)
        XCTAssertEqual(p.sessionIDs.count, ReviewQueue.sessionCap)
        XCTAssertEqual(p.overflowDue, 455)
    }

    /// The split's contract, across the whole range, with new material always
    /// available so the floor is actually contested.
    func testSessionSplitHoldsBothFloorsAtEveryBacklogSize() {
        let cap = ReviewQueue.sessionCap
        let floor = ReviewQueue.minNewSlotsPerSession

        for dueCount in 0...(cap * 2) {
            let due = (0..<dueCount).map { card("due\($0)", attempts: 1, due: .now.addingTimeInterval(-60)) }
            let fresh = (0..<200).map { card("new\($0)") }
            let p = plan(cards: due + fresh, limit: 60)

            XCTAssertLessThanOrEqual(p.sessionIDs.count, cap, "cap held (due=\(dueCount))")
            XCTAssertEqual(p.dueInSession + p.newInSession, p.sessionIDs.count)

            // New material is never crowded out entirely, however big the backlog.
            XCTAssertGreaterThanOrEqual(p.newInSession, min(floor, 200),
                                        "new floor held (due=\(dueCount))")

            if dueCount <= cap - floor {
                // Below the floor's reach, every due card is served.
                XCTAssertEqual(p.dueInSession, dueCount,
                               "reviews not squeezed (due=\(dueCount))")
            } else {
                // Above it, reviews take everything the floor does not reserve.
                XCTAssertEqual(p.dueInSession, cap - floor,
                               "reviews get all but the new floor (due=\(dueCount))")
                XCTAssertEqual(p.overflowDue, dueCount - (cap - floor))
            }
        }
    }

    func testLimitOffStillServesReviews() {
        let due = (1...10).map { card("due\($0)", attempts: 1, due: .now.addingTimeInterval(-60)) }
        let p = plan(cards: due + [card("new1")], limit: 0)
        XCTAssertEqual(p.newInSession, 0)
        XCTAssertEqual(p.dueInSession, 10)
    }

    // MARK: - The gate and the payload are the same computation

    func testAnEligibilityFilterThatExcludesEverythingYieldsAnEmptyPlan() {
        // The exact bug: the button read a raw count while the tap filtered,
        // so it could be enabled with nothing to run.
        let cards = (1...50).map { card("q\($0)", attempts: 1, due: .now.addingTimeInterval(-60)) }
        let p = plan(cards: cards, eligible: { _ in false })
        XCTAssertTrue(p.isEmpty)
        XCTAssertEqual(p.dueCount, 0, "the displayed count must already be filtered")
    }

    func testDisplayedCountsNeverPromiseMoreThanTheSessionPoolHolds() {
        let cards = (1...100).map { card("q\($0)", attempts: 1, due: .now.addingTimeInterval(-60)) }
        let p = plan(cards: cards, eligible: { $0.hasSuffix("0") })
        XCTAssertEqual(p.dueCount, 10)
        XCTAssertEqual(p.sessionIDs.count, 10)
    }

    // MARK: - Determinism

    func testPlanIsStableRegardlessOfInputOrder() {
        let ids = (1...80).map { "q\($0)" }
        let a = plan(cards: ids.map { card($0) }, limit: 60)
        let b = plan(cards: ids.reversed().map { card($0) }, limit: 60)
        XCTAssertEqual(a.sessionIDs, b.sessionIDs,
                       "bootstrap gives thousands of identical dueDates; the tie-break must order them")
    }

    // MARK: - Interleaving

    func testNewQuestionsAreSpreadThroughTheSessionNotStacked() {
        let reviews = (1...40).map { "r\($0)" }
        let fresh = (1...20).map { "n\($0)" }
        let out = ReviewQueue.interleave(reviews: reviews, new: fresh)

        XCTAssertEqual(out.count, 60)
        XCTAssertEqual(Set(out).count, 60)
        XCTAssertEqual(out.filter { $0.hasPrefix("r") }, reviews, "review order preserved")
        XCTAssertEqual(out.filter { $0.hasPrefix("n") }, fresh, "new order preserved")

        for (a, b) in zip(out, out.dropFirst()) {
            XCTAssertFalse(a.hasPrefix("n") && b.hasPrefix("n"), "new cards should not clump")
        }
    }

    func testInterleaveHandlesEmptyLanes() {
        XCTAssertEqual(ReviewQueue.interleave(reviews: ["a"], new: []), ["a"])
        XCTAssertEqual(ReviewQueue.interleave(reviews: [], new: ["b"]), ["b"])
        XCTAssertEqual(ReviewQueue.interleave(reviews: [], new: []), [])
    }

    // MARK: - Labelling

    func testSessionIsNotFiledAsDueReviewWhenItIsAllNew() {
        let p = plan(cards: (1...5).map { card("q\($0)") })
        XCTAssertEqual(ReviewQueue.sessionLabel(for: p), "New questions")
    }
}
