import XCTest
@testable import CFAL3

/// Settings promises "Import merges — newer data wins, nothing is deleted".
/// It used to break that promise with a single `>=` over two copies of the
/// same sentinel date.
final class ProgressMergeTests: XCTestCase {

    private let older = Date(timeIntervalSince1970: 1_700_000_000)
    private let newer = Date(timeIntervalSince1970: 1_800_000_000)

    /// THE regression. A question you flagged but never answered has a nil
    /// `lastAttemptedAt` on BOTH sides, because flagging never writes that
    /// field. The old `(nil ?? .distantPast) >= (nil ?? .distantPast)` was
    /// true, so the row was overwritten with the backup's
    /// `flaggedForReview = false` and the flag was destroyed.
    ///
    /// Mutation: change `importWins` to `>=` over `?? .distantPast` and this
    /// fails immediately.
    func testAnImportNeverWinsWhenNeitherSideHasBeenAnswered() {
        XCTAssertFalse(
            ProgressMerge.importWins(imported: nil, local: nil),
            "both nil means the backup knows nothing this device does not — "
            + "winning here is what silently cleared review flags"
        )
    }

    func testAnImportCarryingNoHistoryNeverOverwritesLocalHistory() {
        XCTAssertFalse(
            ProgressMerge.importWins(imported: nil, local: older),
            "the local row has been answered since the backup was taken"
        )
    }

    func testAnImportWithRealHistoryWinsOverAnUntouchedLocalRow() {
        XCTAssertTrue(ProgressMerge.importWins(imported: older, local: nil))
    }

    func testNewerWinsAndOlderLoses() {
        XCTAssertTrue(ProgressMerge.importWins(imported: newer, local: older))
        XCTAssertFalse(ProgressMerge.importWins(imported: older, local: newer))
    }

    /// A tie is not a win. Re-importing the same backup must report nothing
    /// updated rather than rewriting every row it already matches — that is
    /// what made a no-op import read as a mass overwrite.
    ///
    /// Mutation: use `>=` and this fails.
    func testAnIdenticalTimestampIsNotAWin() {
        XCTAssertFalse(
            ProgressMerge.importWins(imported: older, local: older),
            "the same event on both sides has nothing to copy"
        )
    }

    /// Importing the very backup you just exported must be a no-op. Walks the
    /// real decision for a realistic mix of rows rather than asserting on one.
    func testReimportingTheSameBackupChangesNothing() {
        let rows: [(imported: Date?, local: Date?)] = [
            (nil, nil),            // seeded, untouched
            (nil, nil),            // flagged but unanswered
            (older, older),        // answered before the export
            (newer, newer),        // answered later, same on both sides
        ]
        let wins = rows.filter { ProgressMerge.importWins(imported: $0.imported, local: $0.local) }
        XCTAssertTrue(
            wins.isEmpty,
            "re-importing your own backup rewrote \(wins.count) of \(rows.count) rows"
        )
    }

    /// A genuinely newer backup still merges — the fix must not make import
    /// inert, which would be the opposite failure.
    func testARealRestoreStillApplies() {
        let rows: [(imported: Date?, local: Date?)] = [
            (newer, older),        // answered on the other device since
            (older, nil),          // history this device has never had
        ]
        XCTAssertEqual(
            rows.filter { ProgressMerge.importWins(imported: $0.imported, local: $0.local) }.count,
            2,
            "a newer backup must still restore"
        )
    }
}

/// The Progress pace tile told a user twelve hours behind the plan "On pace",
/// because its caption was `delta < -0.5 ? "On pace" : "On pace"` — both
/// branches the same string — while the value beside it read "−12h" and the
/// tile tinted copper on the same condition.
final class SchedulePaceTests: XCTestCase {

    /// The regression. Mutation: make both caption branches "On pace" again
    /// and this fails.
    func testBeingBehindIsNotCaptionedOnPace() {
        XCTAssertEqual(SchedulePace.caption(-12), "Behind")
        XCTAssertNotEqual(SchedulePace.caption(-12), "On pace")
        XCTAssertTrue(SchedulePace.isBehind(-12))
    }

    func testTheThreeStatesReadCorrectly() {
        XCTAssertEqual(SchedulePace.caption(-12), "Behind")
        XCTAssertEqual(SchedulePace.caption(0), "On pace")
        XCTAssertEqual(SchedulePace.caption(3), "Ahead")
    }

    /// Caption and value must never say the same thing — that pairing is what
    /// read as a glitch in the first place.
    func testCaptionAndValueNeverDuplicate() {
        for delta in [-12.0, -0.6, -0.4, 0, 0.4, 0.6, 3.0, 125.25] {
            XCTAssertNotEqual(
                SchedulePace.caption(delta), SchedulePace.value(delta),
                "at delta \(delta) the tile says the same thing twice"
            )
        }
    }

    /// The sign on the value has to match the caption, or the tile contradicts
    /// itself again in a subtler way.
    func testValueSignAgreesWithTheCaption() {
        XCTAssertTrue(SchedulePace.value(-12).hasPrefix("−"), "behind must read negative")
        XCTAssertTrue(SchedulePace.value(3).hasPrefix("+"), "ahead must read positive")
        XCTAssertEqual(SchedulePace.value(0), "—", "on pace shows no number")
    }

    /// A few minutes either way is noise, not a status change.
    func testTheDeadbandHoldsBothWays() {
        XCTAssertEqual(SchedulePace.caption(0.4), "On pace")
        XCTAssertEqual(SchedulePace.caption(-0.4), "On pace")
        XCTAssertFalse(SchedulePace.isBehind(-0.4))
        XCTAssertEqual(SchedulePace.caption(0.6), "Ahead")
        XCTAssertEqual(SchedulePace.caption(-0.6), "Behind")
        XCTAssertTrue(SchedulePace.isBehind(-0.6))
    }
}
