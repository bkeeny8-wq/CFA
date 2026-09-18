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

/// Level III constructed-response heuristic: 90 seconds per point.
/// An MC slot is one point. Used by the pacing timer, session debrief,
/// and the full-case answer sheet so those clocks cannot drift.
enum ExamPacing {
    static let secondsPerPoint = 90

    static func targetSeconds(points: Int?) -> Int {
        secondsPerPoint * max(1, points ?? 1)
    }

    static func targetSeconds(for questions: [Question]) -> Int {
        questions.reduce(0) { $0 + targetSeconds(points: $1.pointValue) }
    }

    static func weight(for question: Question) -> Int {
        max(1, question.pointValue ?? 1)
    }

    /// Split wall-clock elapsed across items by exam weight. The parts sum
    /// to `max(1, elapsedSeconds)` so a booklet sitting is not recorded as
    /// one second per question.
    static func allocate(elapsedSeconds: Int, weights: [Int]) -> [Int] {
        let n = weights.count
        guard n > 0 else { return [] }
        let elapsed = max(1, elapsedSeconds)
        let w = weights.map { max(1, $0) }
        let total = w.reduce(0, +)
        var floors = w.map { Int(Double(elapsed) * Double($0) / Double(total)) }
        var leftover = elapsed - floors.reduce(0, +)
        let order = w.indices.sorted { a, b in
            let ra = Double(elapsed) * Double(w[a]) / Double(total) - Double(floors[a])
            let rb = Double(elapsed) * Double(w[b]) / Double(total) - Double(floors[b])
            if ra != rb { return ra > rb }
            return a < b
        }
        var i = 0
        while leftover > 0 {
            floors[order[i % n]] += 1
            leftover -= 1
            i += 1
        }
        return floors
    }
}
