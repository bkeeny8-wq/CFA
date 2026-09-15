import Foundation
import SwiftData

/// Per-flashcard spaced-repetition state.
///
/// Deliberately SEPARATE from `ReviewCard` (which schedules bank/drill
/// questions): mixing the two would let a few hundred cards swamp the
/// question review queue and make "N due" mean two different things. Both
/// types share the same SM-2 implementation through `SpacedRepetitionItem`,
/// so a card and a question age identically.
@Model
final class FlashcardProgress {
    @Attribute(.unique) var cardId: String
    var readingId: String
    var areaId: String

    var easeFactor: Double
    var interval: Int
    var repetitions: Int
    var dueDate: Date

    var totalAttempts: Int
    var totalCorrect: Int
    var lastAttemptedAt: Date?
    var flaggedForReview: Bool

    /// When this card was first rated. Questions derive the same fact from
    /// their `Attempt` rows, but flashcard ratings write no Attempt, so the
    /// daily new-card pace has nothing to derive from unless it is recorded.
    /// Optional, so existing stores migrate without work: a pre-existing row
    /// reads as nil and simply never counts against a day's allowance.
    var firstAttemptedAt: Date?

    init(cardId: String, readingId: String, areaId: String) {
        self.cardId = cardId
        self.readingId = readingId
        self.areaId = areaId
        self.easeFactor = 2.5
        self.interval = 0
        self.repetitions = 0
        self.dueDate = .now
        self.totalAttempts = 0
        self.totalCorrect = 0
        self.flaggedForReview = false
    }
}

extension FlashcardProgress: SpacedRepetitionItem {}
