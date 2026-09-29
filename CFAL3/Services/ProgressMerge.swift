import Foundation

/// The one rule deciding whether an imported row replaces the local one.
///
/// Settings promises "Import merges — newer data wins, nothing is deleted".
/// The merge used to read:
///
///     (item.lastAttemptedAt ?? .distantPast) >= (local.lastAttemptedAt ?? .distantPast)
///
/// which breaks that promise in two ways, both because `>=` over two copies of
/// the same sentinel is unconditionally true.
///
/// **It destroyed review flags.** `lastAttemptedAt` is written in exactly one
/// place — when a quality rating is saved — and flagging never touches it. So
/// for a question you flagged but have not answered, BOTH sides are nil, the
/// comparison is true, and the row is overwritten with the backup's
/// `flaggedForReview = false`. Flag eight unanswered questions, import the
/// backup you took beforehand, and all eight flags are gone with no warning
/// and no way back. The import summary counted each one as "updated", so it
/// read as a clean merge.
///
/// **It inflated the summary.** Every seeded review card has a nil timestamp,
/// so an import that changed nothing reported thousands of rows "updated" —
/// a number that makes a no-op look like a mass overwrite and buries the one
/// row that really did change.
///
/// The rule below is the honest reading of "newer wins": an import can only
/// win when it actually carries a timestamp, and a tie is not a win. Extracted
/// from the view because the interesting cases are all nil-handling, and a
/// test that re-implements a comparison inline can only agree with itself.
enum ProgressMerge {

    /// True only when the imported row genuinely carries newer history.
    ///
    /// - both nil — neither side has been answered, so the backup knows
    ///   nothing this device does not. Leave local alone; this is the case
    ///   that was eating flags.
    /// - imported nil, local set — local has been answered since. Keep local.
    /// - imported set, local nil — the backup has real history. Take it.
    /// - both set — strictly newer wins. An equal timestamp is the same
    ///   event, so there is nothing to copy.
    static func importWins(imported: Date?, local: Date?) -> Bool {
        guard let imported else { return false }
        guard let local else { return true }
        return imported > local
    }
}
