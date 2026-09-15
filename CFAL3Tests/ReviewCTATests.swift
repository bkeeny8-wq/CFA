import XCTest
@testable import CFAL3

/// Covers the decisions the screens make about the queue, as opposed to the
/// queue itself.
///
/// Every other test in this project is value-in/value-out over a pure service,
/// and the queues were correct throughout — yet three user-visible bugs
/// shipped anyway, all of them in the code reading the plan: a launch-window
/// guard whose condition could never be true, a tile that printed one number
/// and started a different session, and copy promising a batch that would
/// never arrive. These are the cases that class of bug lives in.
final class ReviewCTATests: XCTestCase {

    private func plan(
        due: Int = 0,
        notStarted: Int = 0,
        limit: Int = 20,
        remaining: Int? = nil,
        session: Int? = nil,
        dueInSession: Int? = nil,
        newInSession: Int? = nil,
        overflow: Int = 0
    ) -> ReviewQueue.Plan {
        let dIn = dueInSession ?? min(due, ReviewQueue.sessionCap)
        let nIn = newInSession ?? min(notStarted, remaining ?? limit)
        let count = session ?? (dIn + nIn)
        return ReviewQueue.Plan(
            dueCount: due,
            notStartedCount: notStarted,
            introducedToday: limit - (remaining ?? limit),
            dailyNewLimit: limit,
            newRemainingToday: remaining ?? limit,
            sessionIDs: (0..<count).map { "q\($0)" },
            dueInSession: dIn,
            newInSession: nIn,
            overflowDue: overflow
        )
    }

    // MARK: - The launch window

    /// The bug: the guard read `reviewCards.isEmpty && content.isLoaded`, and
    /// isLoaded is precisely FALSE while loading — so every cold launch opened
    /// on a greyed-out "All caught up" for the length of the decode.
    func testDoesNotClaimCaughtUpBeforeContentHasLoaded() {
        let input = ReviewCTA.Inputs(
            plan: plan(), contentIsLoaded: false, hasSeededCards: false
        )
        XCTAssertEqual(ReviewCTA.title(input), "Preparing your review queue")
        XCTAssertNotEqual(ReviewCTA.title(input), "All caught up")
        XCTAssertEqual(ReviewCTA.subtitle(input), "Loading your questions…")
    }

    /// Content decoded, but the cards are not seeded yet — the window right
    /// after a wipe, before the re-seed runs.
    func testDoesNotClaimCaughtUpBeforeCardsAreSeeded() {
        let input = ReviewCTA.Inputs(
            plan: plan(), contentIsLoaded: true, hasSeededCards: false
        )
        XCTAssertEqual(ReviewCTA.title(input), "Preparing your review queue")
    }

    func testOnlySaysCaughtUpWhenTheQueueGenuinelyExistsAndIsClear() {
        let input = ReviewCTA.Inputs(plan: plan(), contentIsLoaded: true, hasSeededCards: true)
        XCTAssertEqual(ReviewCTA.title(input), "All caught up")
    }

    func testFailedContentIsNotReportedAsPreparing() {
        let input = ReviewCTA.Inputs(
            plan: plan(), contentIsLoaded: false, contentFailed: true, hasSeededCards: false
        )
        XCTAssertEqual(ReviewCTA.title(input), "Content unavailable")
    }

    // MARK: - Off vs. spent

    func testSwitchedOffDoesNotPromiseAnythingTomorrow() {
        let p = plan(due: 0, notStarted: 500, limit: 0, remaining: 0, session: 0,
                     dueInSession: 0, newInSession: 0)
        XCTAssertTrue(p.isNewOff)
        let input = ReviewCTA.Inputs(plan: p)
        XCTAssertEqual(ReviewCTA.title(input), "New questions are switched off")
        XCTAssertFalse(ReviewCTA.subtitle(input).contains("tomorrow"),
                       "nothing resumes tomorrow when the limit is zero")
        XCTAssertTrue(ReviewCTA.subtitle(input).contains("Settings"),
                      "should point at the setting that turns it back on")
    }

    func testRationSpentDoesPromiseTomorrow() {
        let p = plan(due: 0, notStarted: 500, limit: 20, remaining: 0, session: 0,
                     dueInSession: 0, newInSession: 0)
        XCTAssertTrue(p.isNewExhausted)
        let input = ReviewCTA.Inputs(plan: p)
        XCTAssertEqual(ReviewCTA.title(input), "Today's new questions are done")
        XCTAssertTrue(ReviewCTA.subtitle(input).contains("resume tomorrow"))
    }

    // MARK: - The number and the action agree

    /// The regression: the tile printed plan.dueCount while its accent and
    /// enablement came from !plan.isEmpty, so on a fresh install it read a
    /// bold "0" as the screen's primary action and then ran 20 questions.
    func testTileValueIsAlwaysTheSessionItStarts() {
        for (due, notStarted) in [(0, 500), (5, 500), (200, 500), (0, 0), (60, 0)] {
            let p = plan(due: due, notStarted: notStarted)
            let tile = ReviewCTA.tile(for: p)
            if p.isEmpty {
                XCTAssertEqual(tile.value, "0")
                XCTAssertEqual(tile.label, "Nothing due")
            } else {
                XCTAssertEqual(tile.value, p.sessionIDs.count.formatted(),
                               "tile must show what tapping it runs (due=\(due))")
                XCTAssertNotEqual(tile.value, "0",
                                  "an enabled tile must never read zero (due=\(due))")
            }
        }
    }

    func testTileLabelNamesWhatIsInTheSession() {
        XCTAssertEqual(ReviewCTA.tile(for: plan(due: 0, notStarted: 100)).label, "New today")
        XCTAssertEqual(ReviewCTA.tile(for: plan(due: 10, notStarted: 0)).label, "Due today")
        XCTAssertEqual(ReviewCTA.tile(for: plan(due: 10, notStarted: 100)).label, "Review + new")
        XCTAssertTrue(
            ReviewCTA.tile(for: plan(due: 500, notStarted: 0, overflow: 455)).label
                .contains("500"),
            "a capped session should disclose the full backlog"
        )
    }

    // MARK: - Subtitle honesty

    func testSubtitleNamesTheSliceNotTheWholeQueue() {
        let p = plan(due: 500, notStarted: 0, dueInSession: 45, newInSession: 15, overflow: 455)
        let text = ReviewCTA.subtitle(ReviewCTA.Inputs(plan: p))
        XCTAssertTrue(text.contains("45 due + 15 new"))
        XCTAssertTrue(text.contains("455 more after this"),
                      "the overflow must be stated, not silently dropped")
    }

    func testSubtitleDisclosesANarrowingFilter() {
        let p = plan(due: 10, notStarted: 0)
        let mixed = ReviewCTA.subtitle(ReviewCTA.Inputs(plan: p, typeFilter: .mixed))
        let essays = ReviewCTA.subtitle(ReviewCTA.Inputs(plan: p, typeFilter: .essaysOnly))
        XCTAssertFalse(mixed.contains("only"))
        XCTAssertTrue(essays.contains(QuestionTypeFilter.essaysOnly.displayName),
                      "a filtered queue must say so, since the filter is set on another tab")
    }

    /// Essays cost far more than MCs; pricing a session flat understated an
    /// all-essay hour by up to four times.
    func testEstimateIsPricedByQuestionType() {
        let p = plan(due: 20, notStarted: 0)
        let allMC = ReviewCTA.subtitle(ReviewCTA.Inputs(plan: p, essaysInSession: 0))
        let allEssay = ReviewCTA.subtitle(ReviewCTA.Inputs(plan: p, essaysInSession: 20))
        XCTAssertNotEqual(allMC, allEssay)
        XCTAssertEqual(Formatting.estimatedMinutes(mc: 20, essays: 0), 30)
        XCTAssertEqual(Formatting.estimatedMinutes(mc: 0, essays: 20), 80)
    }
}
