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
            overflowDue: overflow,
            flaggedCount: 0,
            flaggedInSession: 0
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

// MARK: - Study streak

/// The streak is the one number the app shows you before you have done
/// anything that day, so when it is wrong it is wrong at exactly the wrong
/// moment.
final class StudyStreakTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func attempt(daysAgo: Int, from now: Date) -> Attempt {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return Attempt(
            questionId: "q-\(daysAgo)", caseId: "c", topicId: "t",
            timestamp: day, durationSeconds: 30
        )
    }

    private var noonToday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!
    }

    /// The bug: counting began at today, so a streak collapsed to 0 at
    /// midnight and stayed there until the first question of the day.
    func testStreakSurvivesUntilTheDayEndsNotUntilItStarts() {
        let now = noonToday
        // Studied yesterday and the three days before. Nothing yet today.
        let attempts = (1...4).map { attempt(daysAgo: $0, from: now) }

        XCTAssertEqual(
            ProgressStats.streakDays(attempts: attempts, now: now), 4,
            "a four-day streak read as broken because today had not started yet"
        )
    }

    func testStudyingTodayExtendsTheStreak() {
        let now = noonToday
        let attempts = (0...3).map { attempt(daysAgo: $0, from: now) }
        XCTAssertEqual(ProgressStats.streakDays(attempts: attempts, now: now), 4)
    }

    /// Two clear days IS a broken streak — the grace period is one day, not
    /// unlimited.
    func testAGapOfAWholeDayBreaksTheStreak() {
        let now = noonToday
        let attempts = [2, 3, 4].map { attempt(daysAgo: $0, from: now) }
        XCTAssertEqual(
            ProgressStats.streakDays(attempts: attempts, now: now), 0,
            "yesterday was missed as well, so there is no live streak"
        )
    }

    func testNoAttemptsIsNoStreak() {
        XCTAssertEqual(ProgressStats.streakDays(attempts: [], now: noonToday), 0)
    }
}

final class QuestionSubmitCopyTests: XCTestCase {
    func testLocalMCCheckDoesNotSayGrade() {
        XCTAssertEqual(
            QuestionSubmitCopy.title(
                type: .mc, canGradeMC: true, explainReasoning: false, hasReasoningText: false
            ),
            "Check answer"
        )
    }

    func testReasoningCritiqueUsesGrade() {
        XCTAssertEqual(
            QuestionSubmitCopy.title(
                type: .mc, canGradeMC: true, explainReasoning: true, hasReasoningText: true
            ),
            "Grade reasoning"
        )
    }

    func testEssaySubmitIsUnchanged() {
        XCTAssertEqual(
            QuestionSubmitCopy.title(
                type: .essay, canGradeMC: false, explainReasoning: false, hasReasoningText: false
            ),
            "Submit for grading"
        )
    }
}

final class SessionDebriefTests: XCTestCase {
    private func mc(_ id: String, correct: Bool, seconds: Int) -> SessionDebrief.Row {
        SessionDebrief.Row(
            questionID: id,
            label: id,
            durationSeconds: seconds,
            wasCorrect: correct,
            pointsEarned: nil,
            pointsPossible: nil,
            grade: nil,
            examPoints: nil,
            isEssay: false
        )
    }

    func testScorePaceAndRetryListMissedIDs() {
        let d = SessionDebrief.snapshot(rows: [
            mc("q1", correct: true, seconds: 60),
            mc("q2", correct: false, seconds: 150),
            SessionDebrief.Row(
                questionID: "e1",
                label: "essay",
                durationSeconds: 400,
                wasCorrect: nil,
                pointsEarned: 2,
                pointsPossible: 8,
                grade: 2,
                examPoints: 8,
                isEssay: true
            ),
        ])
        XCTAssertEqual(d.scoreLine, "1/2 correct · 2/8 essay points")
        XCTAssertEqual(d.targetSeconds, 90 + 90 + 720)
        XCTAssertEqual(d.missedIDs, ["q2", "e1"])
        XCTAssertTrue(d.canRetry)
        XCTAssertTrue(d.paceLine.contains("90s/point"))
    }

    func testSkipOnlySittingDoesNotLookLikeZeroScore() {
        let d = SessionDebrief.snapshot(rows: [])
        XCTAssertEqual(d.scoreLine, "No answers recorded")
        XCTAssertTrue(d.paceLine.contains("skipped"))
        XCTAssertFalse(d.canRetry)
        XCTAssertEqual(d.attempted, 0)
    }

    func testGraderFailureIsUngradedNotMissed() {
        let d = SessionDebrief.snapshot(rows: [
            SessionDebrief.Row(
                questionID: "e1",
                label: "essay",
                durationSeconds: 10,
                wasCorrect: nil,
                pointsEarned: nil,
                pointsPossible: 6,
                grade: nil,
                examPoints: 6,
                isEssay: true
            ),
        ])
        XCTAssertEqual(d.unscoredCount, 1)
        XCTAssertTrue(d.missedIDs.isEmpty)
        XCTAssertTrue(d.scoreLine.contains("ungraded"))
    }

    func testRetryMissedKeepsAdoptedSessionID() {
        let coordinator = StudySessionCoordinator()
        coordinator.start(questionIDs: ["a", "b"], mode: .random, filterDescription: "Case")
        let first = coordinator.sessionID
        let next = UUID()
        coordinator.retryMissed(questionIDs: ["b"], sessionID: next)
        XCTAssertEqual(coordinator.sessionID, next)
        XCTAssertNotEqual(first, next)
        XCTAssertEqual(coordinator.questionIDs, ["b"])
        XCTAssertTrue(coordinator.filterDescription.hasPrefix("Retry missed"))
        XCTAssertEqual(coordinator.currentIndex, 0)
        XCTAssertTrue(coordinator.completedAttemptIDs.isEmpty)
    }

    func testFlaggedOnlyQueueIsNotCaughtUp() {
        let p = ReviewQueue.Plan(
            dueCount: 0, notStartedCount: 4, introducedToday: 0,
            dailyNewLimit: 0, newRemainingToday: 0,
            sessionIDs: ["a", "b"], dueInSession: 0, newInSession: 0,
            overflowDue: 0, flaggedCount: 2, flaggedInSession: 2
        )
        XCTAssertEqual(
            ReviewCTA.title(ReviewCTA.Inputs(plan: p)),
            "Review flagged · 2 flagged"
        )
        XCTAssertTrue(ReviewCTA.subtitle(ReviewCTA.Inputs(plan: p)).contains("flagged"))
        XCTAssertEqual(ReviewCTA.tile(for: p).label, "Flagged")
    }

    func testSkipCurrentFlagsWithoutRecordingAnAttemptAndClearsOnStart() {
        let coordinator = StudySessionCoordinator()
        coordinator.start(questionIDs: ["a", "b", "c"], mode: .random, filterDescription: "Case")
        XCTAssertTrue(coordinator.skipCurrent())
        XCTAssertEqual(coordinator.skippedQuestionIDs, ["a"])
        XCTAssertEqual(coordinator.currentQuestionID, "b")
        XCTAssertTrue(coordinator.completedAttemptIDs.isEmpty)

        XCTAssertTrue(coordinator.skipCurrent())
        XCTAssertEqual(coordinator.skippedQuestionIDs, ["a", "b"])
        XCTAssertEqual(coordinator.currentQuestionID, "c")

        XCTAssertFalse(coordinator.skipCurrent())
        XCTAssertEqual(coordinator.skippedQuestionIDs, ["a", "b", "c"])
        XCTAssertNil(coordinator.currentQuestionID)
        XCTAssertEqual(coordinator.currentIndex, 3)
        XCTAssertTrue(coordinator.isPastLastQuestion)

        coordinator.start(questionIDs: ["d"], mode: .random, filterDescription: "Next")
        XCTAssertTrue(coordinator.skippedQuestionIDs.isEmpty)
    }
}

final class AttemptHostTests: XCTestCase {
    func testClockIgnoresReappearanceAndReportsAtLeastOneSecond() {
        var clock = AttemptClock()
        let start = Date(timeIntervalSince1970: 1_000)
        clock.appear(now: start)
        clock.appear(now: start.addingTimeInterval(40))
        XCTAssertEqual(clock.durationSeconds(now: start.addingTimeInterval(40)), 40)

        XCTAssertEqual(AttemptHost.durationSeconds(from: start, now: start), 1)
        XCTAssertEqual(AttemptHost.skipTitle, "Skip & flag")
    }

    func testBookletDurationSplitsElapsedByExamWeight() {
        XCTAssertEqual(ExamPacing.secondsPerPoint, 90)
        XCTAssertEqual(ExamPacing.targetSeconds(points: nil), 90)
        XCTAssertEqual(ExamPacing.targetSeconds(points: 8), 720)

        let even = ExamPacing.allocate(elapsedSeconds: 10, weights: [1, 1])
        XCTAssertEqual(even.reduce(0, +), 10)
        XCTAssertEqual(even, [5, 5])

        let mixed = ExamPacing.allocate(elapsedSeconds: 1_000, weights: [1, 1, 8])
        XCTAssertEqual(mixed.reduce(0, +), 1_000)
        XCTAssertEqual(mixed[2], 800)
        XCTAssertEqual(mixed[0] + mixed[1], 200)

        XCTAssertEqual(ExamPacing.allocate(elapsedSeconds: 0, weights: [1, 1, 1]).reduce(0, +), 1)
        XCTAssertTrue(ExamPacing.allocate(elapsedSeconds: 30, weights: []).isEmpty)
    }
}

final class ProgressBackupTests: XCTestCase {
    func testEmptyPayloadRoundTrips() throws {
        let payload = ExportPayload(
            exportedAt: Date(timeIntervalSince1970: 0),
            attempts: [],
            reviewCards: [],
            sessions: [],
            losStudyStatuses: [],
            dayCompletions: [],
            flashcardProgress: []
        )
        let url = try ProgressBackup.write(payload)
        let decoded = try ProgressBackup.decode(from: url)
        XCTAssertEqual(decoded.attempts.count, 0)
        XCTAssertEqual(decoded.reviewCards.count, 0)
        XCTAssertEqual(decoded.flashcardProgress?.count, 0)
    }
}
