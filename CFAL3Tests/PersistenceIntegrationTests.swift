import XCTest
import SwiftData
@testable import CFAL3

/// Exercises the real persistence layer against a real (in-memory) store.
///
/// Nothing in this suite used to construct a ModelContainer, so every defect
/// that lived in the interaction between bundled content, seeded rows and the
/// queues was invisible to it: a wipe that left the app claiming "all caught
/// up" over an untouched corpus, a backup that silently dropped every
/// flashcard, and seeded scaffolding counted as user progress.
final class PersistenceIntegrationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var content: ContentLoader!

    override func setUpWithError() throws {
        let schema = Schema([
            Attempt.self, ReviewCard.self, Session.self,
            LOSStudyStatus.self, DayCompletion.self, FlashcardProgress.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")
    }

    override func tearDown() {
        container = nil; context = nil; content = nil
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    // MARK: - Seeding

    func testBootstrapSeedsEveryAttemptableQuestionExactlyOnce() throws {
        content.bootstrapReviewCards(context: context)
        let cards = try fetch(ReviewCard.self)
        XCTAssertEqual(cards.count, content.totalBankAndDrillQuestions)
        XCTAssertEqual(Set(cards.map(\.questionId)).count, cards.count, "duplicate seeds")
    }

    /// It runs on every launch, so a second pass must add nothing — the unique
    /// constraint on questionId would otherwise fail the save.
    func testBootstrapIsIdempotent() throws {
        content.bootstrapReviewCards(context: context)
        content.bootstrapReviewCards(context: context)
        XCTAssertEqual(try fetch(ReviewCard.self).count, content.totalBankAndDrillQuestions)

        content.bootstrapFlashcardProgress(context: context)
        content.bootstrapFlashcardProgress(context: context)
        XCTAssertEqual(try fetch(FlashcardProgress.self).count, content.totalFlashcards)
    }

    // MARK: - A freshly seeded store is not a queue full of work

    func testFreshlySeededStoreOffersOnlyTheDailyAllowance() throws {
        content.bootstrapReviewCards(context: context)
        let plan = ReviewQueue.plan(
            cards: try fetch(ReviewCard.self),
            attempts: [],
            dailyNewLimit: ReviewQueue.defaultDailyNewLimit,
            isEligible: ReviewQueue.eligibility(content: content, typeFilter: .mixed)
        )
        XCTAssertEqual(plan.dueCount, 0, "seeded-but-unanswered is not due")
        XCTAssertEqual(plan.notStartedCount, content.totalBankAndDrillQuestions)
        XCTAssertEqual(plan.sessionIDs.count, ReviewQueue.defaultDailyNewLimit)
    }

    func testFreshlySeededFlashcardsOfferOnlyTheDailyAllowance() throws {
        content.bootstrapFlashcardProgress(context: context)
        let plan = FlashcardQueue.plan(
            cards: content.allFlashcards,
            progress: try fetch(FlashcardProgress.self),
            dailyNewLimit: FlashcardQueue.defaultDailyNewLimit
        )
        XCTAssertEqual(plan.dueCount, 0)
        XCTAssertEqual(plan.notStartedCount, content.totalFlashcards)
        XCTAssertEqual(plan.sessionIDs.count, FlashcardQueue.defaultDailyNewLimit)
    }

    /// Every id the queue hands to the session must resolve to real content,
    /// or the runner shows "Question not found".
    func testEverySessionIDResolvesToRealContent() throws {
        content.bootstrapReviewCards(context: context)
        let plan = ReviewQueue.plan(
            cards: try fetch(ReviewCard.self),
            attempts: [],
            dailyNewLimit: 60,
            isEligible: ReviewQueue.eligibility(content: content, typeFilter: .mixed)
        )
        XCTAssertFalse(plan.sessionIDs.isEmpty)
        for id in plan.sessionIDs {
            XCTAssertTrue(
                content.question(id: id) != nil || content.drillQuestion(id: id) != nil,
                "session contains an unresolvable id: \(id)"
            )
        }
    }

    // MARK: - Answering moves a question between lanes

    func testAnsweringMovesAQuestionOutOfTheNotStartedLane() throws {
        content.bootstrapReviewCards(context: context)
        var cards = try fetch(ReviewCard.self)
        let target = try XCTUnwrap(cards.first { content.question(id: $0.questionId) != nil })

        let attempt = Attempt(
            questionId: target.questionId, caseId: target.caseId,
            topicId: target.topicId, durationSeconds: 30, wasCorrect: true
        )
        context.insert(attempt)
        ReviewScheduler.update(item: target, quality: 4)
        try context.save()

        cards = try fetch(ReviewCard.self)
        let plan = ReviewQueue.plan(
            cards: cards, attempts: try fetch(Attempt.self),
            dailyNewLimit: 20,
            isEligible: ReviewQueue.eligibility(content: content, typeFilter: .mixed)
        )
        XCTAssertEqual(plan.notStartedCount, content.totalBankAndDrillQuestions - 1)
        XCTAssertEqual(plan.introducedToday, 1, "it spent one of today's slots")
        XCTAssertFalse(plan.sessionIDs.contains(target.questionId),
                       "a question scheduled a day out must not come straight back")
    }

    /// Submitting writes an Attempt, but totalAttempts is only incremented when
    /// the grading screen is dismissed forward — so backing out leaves the two
    /// disagreeing. The question is answered either way.
    func testAQuestionAbandonedAtGradingIsNotOfferedAsNewMaterial() throws {
        content.bootstrapReviewCards(context: context)
        let cards = try fetch(ReviewCard.self)
        let target = try XCTUnwrap(cards.first)

        context.insert(Attempt(
            questionId: target.questionId, caseId: target.caseId,
            topicId: target.topicId, durationSeconds: 30, wasCorrect: true
        ))
        try context.save()
        XCTAssertEqual(target.totalAttempts, 0, "precondition: the card was never updated")

        let plan = ReviewQueue.plan(
            cards: cards, attempts: try fetch(Attempt.self),
            dailyNewLimit: 20,
            isEligible: ReviewQueue.eligibility(content: content, typeFilter: .mixed)
        )
        XCTAssertEqual(plan.notStartedCount, content.totalBankAndDrillQuestions - 1)
        XCTAssertEqual(plan.dueCount, 1, "it has been seen, and its interval has not elapsed")
    }

    // MARK: - Wipe and re-seed

    /// Deleting every card and re-seeding is what the reset buttons do. Without
    /// the re-seed the app read "All caught up" over an untouched corpus until
    /// the next launch.
    func testWipingAndReseedingRestoresAWorkableQueue() throws {
        content.bootstrapReviewCards(context: context)
        for card in try fetch(ReviewCard.self) { context.delete(card) }
        try context.save()
        XCTAssertTrue(try fetch(ReviewCard.self).isEmpty)

        content.bootstrapReviewCards(context: context)
        let cards = try fetch(ReviewCard.self)
        XCTAssertEqual(cards.count, content.totalBankAndDrillQuestions)

        let plan = ReviewQueue.plan(
            cards: cards, attempts: [], dailyNewLimit: 20,
            isEligible: ReviewQueue.eligibility(content: content, typeFilter: .mixed)
        )
        XCTAssertFalse(plan.isEmpty, "a re-seeded queue must offer work again")
    }

    /// The reset buttons' enabled state, and the count they report, must both
    /// ignore seeded rows — otherwise they are permanently enabled and a
    /// confirmed erase reports thousands of "records" to someone who answered
    /// nothing.
    func testSeededRowsDoNotCountAsUserProgress() throws {
        content.bootstrapReviewCards(context: context)
        content.bootstrapFlashcardProgress(context: context)

        let attempts = try fetch(Attempt.self)
        let sessions = try fetch(Session.self)
        let ratedCards = try fetch(FlashcardProgress.self).filter { $0.totalAttempts > 0 }

        XCTAssertTrue(attempts.isEmpty && sessions.isEmpty && ratedCards.isEmpty,
                      "a seeded store holds no user progress")
        XCTAssertEqual(attempts.count + sessions.count + ratedCards.count, 0,
                       "the erase summary would report zero, so the button must be disabled")
        XCTAssertFalse(try fetch(ReviewCard.self).isEmpty,
                       "…even though thousands of scheduling rows exist")
    }

    // MARK: - Flashcard pacing over a real store

    func testRatingAFlashcardSpendsExactlyOneDailySlot() throws {
        content.bootstrapFlashcardProgress(context: context)
        let rows = try fetch(FlashcardProgress.self)
        let row = try XCTUnwrap(rows.first)

        row.firstAttemptedAt = .now
        ReviewScheduler.update(item: row, quality: 4)
        try context.save()

        XCTAssertEqual(FlashcardQueue.introducedToday(progress: try fetch(FlashcardProgress.self)), 1)

        // Rating the same card again the same day must not spend a second.
        ReviewScheduler.update(item: row, quality: 5)
        try context.save()
        XCTAssertEqual(FlashcardQueue.introducedToday(progress: try fetch(FlashcardProgress.self)), 1)
    }

    // MARK: - The queue is stable across evaluations

    /// The parent rebuilds the deck on every body evaluation and an answer
    /// invalidates its @Query, which is why the session view must snapshot.
    /// This pins the hazard: the same inputs plus one rating really do produce
    /// a different deck.
    func testRatingACardChangesTheDeckTheParentWouldRebuild() throws {
        content.bootstrapFlashcardProgress(context: context)
        let before = FlashcardQueue.plan(
            cards: content.allFlashcards,
            progress: try fetch(FlashcardProgress.self),
            dailyNewLimit: 20
        ).sessionIDs

        let row = try XCTUnwrap(try fetch(FlashcardProgress.self)
            .first { $0.cardId == before.first })
        row.firstAttemptedAt = .now
        ReviewScheduler.update(item: row, quality: 4)
        try context.save()

        let after = FlashcardQueue.plan(
            cards: content.allFlashcards,
            progress: try fetch(FlashcardProgress.self),
            dailyNewLimit: 20
        ).sessionIDs

        XCTAssertNotEqual(before, after,
                          "if this ever becomes equal, the snapshot in FlashcardSessionView "
                          + "is no longer load-bearing and the comment there should be revisited")
    }

    /// With no changes in between, two evaluations must agree — otherwise the
    /// session reshuffles under the user on any unrelated redraw.
    func testPlanIsStableAcrossRepeatedEvaluations() throws {
        content.bootstrapReviewCards(context: context)
        let cards = try fetch(ReviewCard.self)
        let eligible = ReviewQueue.eligibility(content: content, typeFilter: .mixed)
        let a = ReviewQueue.plan(cards: cards, attempts: [], dailyNewLimit: 20, isEligible: eligible)
        let b = ReviewQueue.plan(cards: cards, attempts: [], dailyNewLimit: 20, isEligible: eligible)
        XCTAssertEqual(a.sessionIDs, b.sessionIDs)
    }
}
