import Foundation
import SwiftData

/// What one scheduled question sitting actually scored.
///
/// This exists because `Attempt` cannot cover November. Eleven of the month's
/// forty-five sittings are answered in Mark Meldrum's app, which writes no
/// `Attempt` row here and never will, so for those readings this is the only
/// record there is. Deriving the month's baseline from attempts alone would
/// leave holes in exactly the places the plan sends the work elsewhere.
///
/// It is also why the figures are typed in rather than computed: a row is a
/// self-report, not a measurement. Nothing here should be mixed into an
/// accuracy derived from `Attempt` rows — an app-sourced sitting produces
/// both, and adding them double counts it.
@Model
final class ScheduleBlockResult {
    /// `"\(dateKey)|\(blockStart)"`.
    ///
    /// Not `ScheduleBlock.id`: that is `start-label`, which repeats on 42 of
    /// the plan's blocks and on one block across six separate days, so a
    /// unique constraint over it would silently collapse six sittings into one
    /// overwriting row. No day repeats a start time, and keying on the start
    /// rather than the label also means a copy-edit to a block's wording does
    /// not orphan the score already recorded against it.
    @Attribute(.unique) var key: String

    var dateKey: String
    var blockStart: String
    /// Kept for display when the plan JSON has moved on and no longer has a
    /// block at this slot. The row still has to be readable.
    var blockLabel: String
    /// Nil for the six mock sittings and the two review blocks, which rank
    /// against no single reading.
    var readingID: String?
    /// `ScheduleBlockSource.rawValue` as it was when recorded, so a later
    /// re-sourcing of the plan does not rewrite history.
    var source: String?

    var questionsAttempted: Int
    var questionsCorrect: Int
    /// Essay points. Mirrors `Attempt.pointsEarned`/`pointsPossible` so the
    /// export schema reads the same on both sides.
    var pointsEarned: Int?
    var pointsPossible: Int?
    /// Has no equivalent anywhere else: `Attempt` stores `durationSeconds` but
    /// never whether the clock beat you, which is the thing worth knowing
    /// about a timed sitting.
    var ranOutOfTime: Bool
    /// 1...5, self-reported. Not `Attempt.quality`, which is the SM-2 review
    /// rating and means something else.
    var confidence: Int?
    var recordedAt: Date

    init(
        key: String,
        dateKey: String,
        blockStart: String,
        blockLabel: String,
        readingID: String? = nil,
        source: String? = nil,
        questionsAttempted: Int = 0,
        questionsCorrect: Int = 0,
        pointsEarned: Int? = nil,
        pointsPossible: Int? = nil,
        ranOutOfTime: Bool = false,
        confidence: Int? = nil,
        recordedAt: Date = .now
    ) {
        self.key = key
        self.dateKey = dateKey
        self.blockStart = blockStart
        self.blockLabel = blockLabel
        self.readingID = readingID
        self.source = source
        self.questionsAttempted = questionsAttempted
        self.questionsCorrect = questionsCorrect
        self.pointsEarned = pointsEarned
        self.pointsPossible = pointsPossible
        self.ranOutOfTime = ranOutOfTime
        self.confidence = confidence
        self.recordedAt = recordedAt
    }

    /// Nil rather than zero when nothing was attempted: a sitting with no
    /// questions is unrecorded, not a zero score, and sorting a ranked list
    /// has to be able to tell those apart.
    var correctRate: Double? {
        guard questionsAttempted > 0 else { return nil }
        return Double(questionsCorrect) / Double(questionsAttempted)
    }

    var essayRate: Double? {
        guard let earned = pointsEarned, let possible = pointsPossible, possible > 0 else {
            return nil
        }
        return Double(earned) / Double(possible)
    }

    /// Whether this row carries any score at all. A row created only to hold a
    /// confidence rating still counts as recorded.
    var hasScore: Bool { questionsAttempted > 0 || essayRate != nil }
}
