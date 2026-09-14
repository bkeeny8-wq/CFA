import Foundation

/// Anything that carries SM-2 scheduling state. Implemented by `ReviewCard`
/// (bank + drill questions) and `FlashcardProgress` so both age through the
/// exact same algorithm rather than two drifting copies of it.
protocol SpacedRepetitionItem: AnyObject {
    var easeFactor: Double { get set }
    var interval: Int { get set }
    var repetitions: Int { get set }
    var dueDate: Date { get set }
    var totalAttempts: Int { get set }
    var totalCorrect: Int { get set }
    var lastAttemptedAt: Date? { get set }
}

extension ReviewCard: SpacedRepetitionItem {}

enum ReviewScheduler {
    static func update(card: ReviewCard, quality: Int, now: Date = .now) {
        update(item: card, quality: quality, now: now)
    }

    static func update(item: some SpacedRepetitionItem, quality: Int, now: Date = .now) {
        let q = max(0, min(5, quality))

        if q < 3 {
            item.repetitions = 0
            item.interval = 1
        } else {
            switch item.repetitions {
            case 0:
                item.interval = 1
            case 1:
                item.interval = 6
            default:
                item.interval = Int((Double(item.interval) * item.easeFactor).rounded())
            }
            item.repetitions += 1
        }

        // DELIBERATE deviation from canonical SM-2: the ease factor is updated
        // on ALL reviews, including failures (q < 3). Canonical SM-2 leaves EF
        // unchanged on failure. Penalizing EF on failure makes chronically hard
        // cards resurface faster after relearning, which is the desired behavior
        // for exam prep. Do not "fix" this to match the canonical algorithm —
        // changing it mid-study would silently shift every card’s future schedule.
        let ef = item.easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        item.easeFactor = max(1.3, ef)

        item.dueDate = Calendar.current.date(byAdding: .day, value: item.interval, to: now) ?? now
        item.lastAttemptedAt = now
        item.totalAttempts += 1
        if q >= 3 {
            item.totalCorrect += 1
        }
    }

    static func suggestedQuality(wasCorrect: Bool) -> Int {
        wasCorrect ? 4 : 1
    }

    static func suggestedQuality(essayGrade: Int) -> Int {
        max(0, min(5, essayGrade))
    }

    /// The interval a rating would produce, without mutating anything — used to
    /// label the rating buttons ("Good · 6d") so the choice is informed.
    static func previewInterval(item: some SpacedRepetitionItem, quality: Int) -> Int {
        let q = max(0, min(5, quality))
        guard q >= 3 else { return 1 }
        switch item.repetitions {
        case 0: return 1
        case 1: return 6
        default: return Int((Double(item.interval) * item.easeFactor).rounded())
        }
    }
}
