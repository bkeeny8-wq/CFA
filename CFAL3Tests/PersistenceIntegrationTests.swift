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

    /// It runs on every launch, so a second pass must add nothing AND disturb
    /// nothing.
    ///
    /// Counting rows alone was not enough: a re-seed that upserted over every
    /// existing card would keep the count identical while resetting each one's
    /// schedule to "new", silently wiping the user's spaced repetition on
    /// every launch. So the schedules are captured and compared too.
    func testBootstrapIsIdempotent() throws {
        content.bootstrapReviewCards(context: context)
        content.bootstrapFlashcardProgress(context: context)

        // Age a card and a flashcard so there is real state to disturb.
        let card = try XCTUnwrap(try fetch(ReviewCard.self).first)
        ReviewScheduler.update(card: card, quality: 5)
        let flashcard = try XCTUnwrap(try fetch(FlashcardProgress.self).first)
        flashcard.firstAttemptedAt = .now
        ReviewScheduler.update(item: flashcard, quality: 4)
        try context.save()

        let cardsBefore = try fetch(ReviewCard.self)
            .reduce(into: [String: (Int, Int, Date)]()) {
                $0[$1.questionId] = ($1.interval, $1.repetitions, $1.dueDate)
            }
        let flashcardsBefore = try fetch(FlashcardProgress.self)
            .reduce(into: [String: (Int, Int, Date?)]()) {
                $0[$1.cardId] = ($1.interval, $1.totalAttempts, $1.firstAttemptedAt)
            }

        content.bootstrapReviewCards(context: context)
        content.bootstrapFlashcardProgress(context: context)

        XCTAssertEqual(try fetch(ReviewCard.self).count, content.totalBankAndDrillQuestions)
        XCTAssertEqual(try fetch(FlashcardProgress.self).count, content.totalFlashcards)

        for row in try fetch(ReviewCard.self) {
            let before = try XCTUnwrap(cardsBefore[row.questionId])
            XCTAssertEqual(row.interval, before.0, "\(row.questionId): interval was re-seeded")
            XCTAssertEqual(row.repetitions, before.1, "\(row.questionId): repetitions were re-seeded")
            XCTAssertEqual(row.dueDate, before.2, "\(row.questionId): due date was re-seeded")
        }
        for row in try fetch(FlashcardProgress.self) {
            let before = try XCTUnwrap(flashcardsBefore[row.cardId])
            XCTAssertEqual(row.interval, before.0, "\(row.cardId): interval was re-seeded")
            XCTAssertEqual(row.totalAttempts, before.1, "\(row.cardId): history was re-seeded")
            XCTAssertEqual(row.firstAttemptedAt, before.2, "\(row.cardId): introduction was re-dated")
        }
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

        // Through the production gate, not a copy of it. This used to fetch
        // the rows and assert emptiness inline, which is the same predicate
        // agreeing with itself — it could not fail however the buttons behaved.
        func hasProgress() throws -> Bool {
            try ResetScope.hasAnyProgress(
                attempts: fetch(Attempt.self),
                sessions: fetch(Session.self),
                dayCompletions: fetch(DayCompletion.self),
                losStatuses: fetch(LOSStudyStatus.self),
                flashcards: fetch(FlashcardProgress.self)
            )
        }

        XCTAssertFalse(try hasProgress(), "a freshly seeded store holds no user progress")
        XCTAssertFalse(
            try ResetScope.hasQuizHistory(attempts: fetch(Attempt.self), sessions: fetch(Session.self)),
            "…so Clear quiz attempts must be disabled too"
        )
        XCTAssertFalse(try fetch(ReviewCard.self).isEmpty,
                       "…even though thousands of scheduling rows exist")

        // And it must notice the moment there IS something to erase. A rated
        // flashcard alone counts: a Cards-only user once found both buttons
        // permanently disabled.
        let row = try XCTUnwrap(try fetch(FlashcardProgress.self).first)
        ReviewScheduler.update(item: row, quality: 4)
        try context.save()

        XCTAssertTrue(try hasProgress(), "a rated flashcard is progress worth erasing")
        XCTAssertFalse(
            try ResetScope.hasQuizHistory(attempts: fetch(Attempt.self), sessions: fetch(Session.self)),
            "but it is not quiz history, so Clear stays disabled"
        )
    }

    // MARK: - Flashcard pacing over a real store

    /// Exercises the real introduction rule rather than hand-stamping the date
    /// and asserting it stayed put. The old version set `firstAttemptedAt`
    /// itself and then checked that a second rating did not change the count —
    /// but nothing in that test ever ran the guard that decides whether to
    /// stamp, so the "second rating spends no slot" claim could not fail.
    func testRatingAFlashcardSpendsExactlyOneDailySlot() throws {
        content.bootstrapFlashcardProgress(context: context)
        let row = try XCTUnwrap(try fetch(FlashcardProgress.self).first)

        // What FlashcardSessionView.rate does, in the same order.
        func rate(_ row: FlashcardProgress, quality: Int) throws {
            if row.isBeingIntroduced { row.firstAttemptedAt = .now }
            ReviewScheduler.update(item: row, quality: quality)
            try context.save()
        }

        XCTAssertTrue(row.isBeingIntroduced, "a seeded, never-rated row is a new card")
        try rate(row, quality: 4)
        XCTAssertEqual(FlashcardQueue.introducedToday(progress: try fetch(FlashcardProgress.self)), 1)

        // Rating the same card again the same day must not spend a second.
        XCTAssertFalse(row.isBeingIntroduced, "it has been introduced now")
        try rate(row, quality: 5)
        XCTAssertEqual(FlashcardQueue.introducedToday(progress: try fetch(FlashcardProgress.self)), 1)
    }

    /// A row carrying history but no `firstAttemptedAt` — written before that
    /// field existed — is an OLD card, and rating it must not spend one of
    /// today's new-card slots.
    func testReviewingALegacyCardDoesNotSpendANewCardSlot() throws {
        content.bootstrapFlashcardProgress(context: context)
        let row = try XCTUnwrap(try fetch(FlashcardProgress.self).first)

        // The shape a pre-migration row has: rated repeatedly, never dated.
        row.firstAttemptedAt = nil
        row.totalAttempts = 7
        row.repetitions = 3
        row.interval = 15
        try context.save()

        XCTAssertFalse(row.isBeingIntroduced,
                       "history without a date is still history, not an introduction")

        if row.isBeingIntroduced { row.firstAttemptedAt = .now }
        ReviewScheduler.update(item: row, quality: 4)
        try context.save()

        XCTAssertEqual(
            FlashcardQueue.introducedToday(progress: try fetch(FlashcardProgress.self)), 0,
            "reviewing an old card ate one of today's new-card slots"
        )
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

    // MARK: - Session records survive every way out

    /// "Save & exit" used to be the only writer of a Session row, so leaving
    /// by the back button, a swipe, or a tab switch lost the record of that
    /// sitting entirely. The attempts survived — each is saved as it is graded
    /// — but the row that groups them into a session did not, so history
    /// under-counted sittings and backups exported fewer sessions than had
    /// happened.
    @MainActor
    func testSessionIsRecordedAsItProgressesNotOnlyOnSaveAndExit() throws {
        let coordinator = StudySessionCoordinator()
        coordinator.start(questionIDs: ["q1", "q2", "q3"], mode: .reviewDue, filterDescription: "Due")

        XCTAssertTrue(try fetch(Session.self).isEmpty, "nothing answered yet, nothing to record")

        coordinator.recordAttempt(UUID())
        coordinator.persist(into: context)

        let afterOne = try fetch(Session.self)
        XCTAssertEqual(afterOne.count, 1, "the sitting must be on record before the user leaves")
        XCTAssertEqual(afterOne.first?.attemptIds.count, 1)
        XCTAssertEqual(afterOne.first?.mode, SessionMode.reviewDue.rawValue)
        XCTAssertEqual(afterOne.first?.filterDescription, "Due")

        // Answering more updates the SAME row rather than piling up duplicates.
        coordinator.recordAttempt(UUID())
        coordinator.recordAttempt(UUID())
        coordinator.persist(into: context)

        let afterThree = try fetch(Session.self)
        XCTAssertEqual(afterThree.count, 1, "each answer wrote a new session row")
        XCTAssertEqual(afterThree.first?.attemptIds.count, 3)
        XCTAssertEqual(afterThree.first?.startedAt, coordinator.startedAt,
                       "the session kept its real start time")
    }

    /// Two sittings are two rows. The record is keyed on the session, so a
    /// stable id must not mean one row forever.
    @MainActor
    func testASecondSessionGetsItsOwnRow() throws {
        let coordinator = StudySessionCoordinator()

        coordinator.start(questionIDs: ["q1"], mode: .reviewDue, filterDescription: "First")
        coordinator.recordAttempt(UUID())
        coordinator.persist(into: context)

        coordinator.start(questionIDs: ["q2"], mode: .losDrill, filterDescription: "Second")
        coordinator.recordAttempt(UUID())
        coordinator.persist(into: context)

        let sessions = try fetch(Session.self)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(Set(sessions.map(\.filterDescription)), ["First", "Second"])
    }
}
