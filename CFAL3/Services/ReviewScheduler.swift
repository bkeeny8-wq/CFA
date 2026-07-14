import Foundation

enum ReviewScheduler {
    static func update(card: ReviewCard, quality: Int, now: Date = .now) {
        let q = max(0, min(5, quality))

        if q < 3 {
            card.repetitions = 0
            card.interval = 1
        } else {
            switch card.repetitions {
            case 0:
                card.interval = 1
            case 1:
                card.interval = 6
            default:
                card.interval = Int((Double(card.interval) * card.easeFactor).rounded())
            }
            card.repetitions += 1
        }

        // DELIBERATE deviation from canonical SM-2: the ease factor is updated
        // on ALL reviews, including failures (q < 3). Canonical SM-2 leaves EF
        // unchanged on failure. Penalizing EF on failure makes chronically hard
        // cards resurface faster after relearning, which is the desired behavior
        // for exam prep. Do not "fix" this to match the canonical algorithm —
        // changing it mid-study would silently shift every card’s future schedule.
        let ef = card.easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        card.easeFactor = max(1.3, ef)

        card.dueDate = Calendar.current.date(byAdding: .day, value: card.interval, to: now) ?? now
        card.lastAttemptedAt = now
        card.totalAttempts += 1
        if q >= 3 {
            card.totalCorrect += 1
        }
    }

    static func suggestedQuality(wasCorrect: Bool) -> Int {
        wasCorrect ? 4 : 1
    }

    static func suggestedQuality(essayGrade: Int) -> Int {
        max(0, min(5, essayGrade))
    }
}
