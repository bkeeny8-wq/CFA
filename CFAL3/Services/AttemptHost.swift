import Foundation
import SwiftData

/// Shared sitting chrome for bank questions and LOS drills: one clock, one
/// flag path, one skip-and-flag. The two attempt screens used to drift —
/// the clock bug was fixed in only one of them the first time.
enum AttemptHost {
    static let skipTitle = "Skip & flag"

    static func durationSeconds(from startedAt: Date, now: Date = .now) -> Int {
        max(1, Int(now.timeIntervalSince(startedAt)))
    }

    /// Mark the card for later. Creates the row if the sitting somehow
    /// reached a question that was never seeded.
    @discardableResult
    static func setFlagged(
        _ flagged: Bool,
        questionId: String,
        caseId: String,
        topicId: String,
        readingIds: [String],
        losIds: [String],
        existing: ReviewCard?,
        context: ModelContext
    ) -> ReviewCard {
        if let card = existing {
            card.flaggedForReview = flagged
            try? context.save()
            return card
        }
        let card = ReviewCard(
            questionId: questionId,
            caseId: caseId,
            topicId: topicId,
            readingIds: readingIds,
            losIds: losIds
        )
        card.flaggedForReview = flagged
        context.insert(card)
        try? context.save()
        return card
    }

    static func flagForSkip(
        questionId: String,
        caseId: String,
        topicId: String,
        readingIds: [String],
        losIds: [String],
        existing: ReviewCard?,
        context: ModelContext
    ) {
        setFlagged(
            true,
            questionId: questionId,
            caseId: caseId,
            topicId: topicId,
            readingIds: readingIds,
            losIds: losIds,
            existing: existing,
            context: context
        )
    }
}

/// First-appearance clock. `onAppear` fires again after the result screen
/// pops, and restarting there used to report only the time since reappearance.
struct AttemptClock {
    private(set) var startedAt: Date = .now
    private var started = false

    mutating func appear(now: Date = .now) {
        guard !started else { return }
        startedAt = now
        started = true
    }

    func durationSeconds(now: Date = .now) -> Int {
        AttemptHost.durationSeconds(from: startedAt, now: now)
    }
}
