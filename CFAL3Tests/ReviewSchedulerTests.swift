import XCTest
@testable import CFAL3

final class ReviewSchedulerTests: XCTestCase {
    func testFailedReviewResetsRepetitionsAndSetsOneDayInterval() {
        let card = ReviewCard(
            questionId: "q1",
            caseId: "c1",
            topicId: "t1",
            readingIds: [],
            losIds: []
        )
        card.repetitions = 3
        card.interval = 15
        card.easeFactor = 2.4

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        ReviewScheduler.update(card: card, quality: 2, now: now)

        XCTAssertEqual(card.repetitions, 0)
        XCTAssertEqual(card.interval, 1)
        XCTAssertEqual(card.totalAttempts, 1)
        XCTAssertEqual(card.totalCorrect, 0)
        XCTAssertEqual(card.dueDate, Calendar.current.date(byAdding: .day, value: 1, to: now))
    }

    func testFirstSuccessfulReviewSetsOneDayInterval() {
        let card = makeCard()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        ReviewScheduler.update(card: card, quality: 3, now: now)

        XCTAssertEqual(card.repetitions, 1)
        XCTAssertEqual(card.interval, 1)
        XCTAssertEqual(card.totalCorrect, 1)
    }

    func testSecondSuccessfulReviewSetsSixDayInterval() {
        let card = makeCard()
        card.repetitions = 1
        card.interval = 1

        ReviewScheduler.update(card: card, quality: 4)

        XCTAssertEqual(card.repetitions, 2)
        XCTAssertEqual(card.interval, 6)
    }

    func testThirdSuccessfulReviewMultipliesIntervalByEaseFactor() {
        let card = makeCard()
        card.repetitions = 2
        card.interval = 6
        card.easeFactor = 2.5

        ReviewScheduler.update(card: card, quality: 5)

        XCTAssertEqual(card.repetitions, 3)
        XCTAssertEqual(card.interval, 15)
    }

    func testEaseFactorFloorAtOnePointThree() {
        let card = makeCard()
        card.easeFactor = 1.31

        ReviewScheduler.update(card: card, quality: 0)

        XCTAssertGreaterThanOrEqual(card.easeFactor, 1.3)
    }

    func testEaseFactorIsPenalizedOnFailure_deliberateSM2Deviation() {
        let card = ReviewCard(questionId: "q", caseId: "c", topicId: "t",
                              readingIds: [], losIds: [])
        let efBefore = card.easeFactor          // 2.5
        ReviewScheduler.update(card: card, quality: 1)
        XCTAssertLessThan(card.easeFactor, efBefore,
            "EF must drop on failure; see deviation comment in ReviewScheduler")
        XCTAssertEqual(card.repetitions, 0)
        XCTAssertEqual(card.interval, 1)
    }

    private func makeCard() -> ReviewCard {
        ReviewCard(
            questionId: "q1",
            caseId: "c1",
            topicId: "t1",
            readingIds: [],
            losIds: []
        )
    }
}
