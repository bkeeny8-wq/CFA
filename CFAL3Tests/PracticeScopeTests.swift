import XCTest
@testable import CFAL3

/// Locks the Practice scope-cascade contract against the real curriculum:
/// selecting a book must narrow the readings to that book, and selecting a
/// reading must narrow the LOS to that reading. Mirrors the filter predicates
/// used by ReadingMultiSelectSheet and LOSFilterSheet.
final class PracticeScopeTests: XCTestCase {

    private func loadedContent() -> ContentLoader {
        let content = ContentLoader()
        content.load()
        return content
    }

    func testReadingsNarrowToSelectedBook() {
        let content = loadedContent()
        let areas = content.losMaster?.areas ?? []
        XCTAssertFalse(areas.isEmpty)

        let allReadingIDs = Set(areas.flatMap { $0.readings.map(\.id) })

        // Through PracticeScope, the code the sheet runs. This used to filter
        // `areas` by a set holding one id and then assert the result was that
        // id — a tautology over a predicate the test had written itself, which
        // exercised nothing and could not fail.
        for area in areas {
            let visibleReadings = PracticeScope.readings(in: areas, topics: [area.id])

            XCTAssertEqual(
                visibleReadings, Set(area.readings.map(\.id)),
                "\(area.id): scoping to one book must offer exactly that book's readings"
            )
            XCTAssertFalse(visibleReadings.isEmpty, "\(area.id) has readings")
            XCTAssertTrue(visibleReadings.isSubset(of: allReadingIDs))

            // And nothing from any other book leaked in.
            for other in areas where other.id != area.id {
                XCTAssertTrue(
                    visibleReadings.isDisjoint(with: Set(other.readings.map(\.id))),
                    "\(area.id) offered a reading belonging to \(other.id)"
                )
            }
        }

        // With more than one book, a single-book scope is a strict subset.
        if areas.count > 1, let first = areas.first {
            XCTAssertLessThan(
                PracticeScope.readings(in: areas, topics: [first.id]).count,
                allReadingIDs.count
            )
        }
    }

    /// Through `PracticeScope`, the code the builder actually runs.
    ///
    /// This used to filter the readings itself and compare the result with a
    /// second expression built the same way — one predicate agreeing with
    /// itself. No production code was exercised, so the cascade could break
    /// entirely and the suite would stay green.
    func testLOSNarrowToSelectedReadings() {
        let content = loadedContent()
        let areas = content.losMaster?.areas ?? []
        let allReadings = areas.flatMap(\.readings)
        XCTAssertFalse(allReadings.isEmpty)

        let allLOS = Set(allReadings.flatMap { $0.los.map(\.id) })
        let sample = Array(allReadings.prefix(2))
        let readingScope = Set(sample.map(\.id))

        let visibleLOS = PracticeScope.los(in: areas, readings: readingScope, topics: [])

        XCTAssertEqual(visibleLOS, Set(sample.flatMap { $0.los.map(\.id) }))
        XCTAssertTrue(visibleLOS.isSubset(of: allLOS))
        if allReadings.count > 2 {
            XCTAssertLessThan(visibleLOS.count, allLOS.count)
        }
    }

    /// An empty selection means "everything", at both levels.
    func testEmptyScopeMeansTheWholeCurriculum() {
        let content = loadedContent()
        let areas = content.losMaster?.areas ?? []
        XCTAssertFalse(areas.isEmpty)

        XCTAssertEqual(
            PracticeScope.readings(in: areas, topics: []),
            Set(areas.flatMap { $0.readings.map(\.id) })
        )
        XCTAssertEqual(
            PracticeScope.los(in: areas, readings: [], topics: []),
            Set(areas.flatMap { $0.readings.flatMap { $0.los.map(\.id) } })
        )
    }

    /// Narrowing the books must drop the readings — and the LOS under them —
    /// that no longer fit, and keep everything that does.
    func testNarrowingTheBooksPrunesWhatNoLongerFits() {
        let content = loadedContent()
        let areas = content.losMaster?.areas ?? []
        guard areas.count >= 2 else { return XCTFail("fixture needs ≥2 books") }

        let keep = areas[0]
        let drop = areas[1]
        let selectedReadings = Set(
            (keep.readings.prefix(2) + drop.readings.prefix(2)).map(\.id)
        )
        let selectedLOS = Set(
            (keep.readings.prefix(2) + drop.readings.prefix(2)).flatMap { $0.los.map(\.id) }
        )

        let pruned = PracticeScope.pruned(
            areas: areas,
            topics: [keep.id],
            readings: selectedReadings,
            los: selectedLOS
        )

        let keepReadingIDs = Set(keep.readings.map(\.id))
        XCTAssertFalse(pruned.readings.isEmpty)
        XCTAssertTrue(pruned.readings.isSubset(of: keepReadingIDs),
                      "a reading from a deselected book survived the prune")
        XCTAssertTrue(
            pruned.los.isSubset(of: Set(keep.readings.flatMap { $0.los.map(\.id) })),
            "a LOS from a deselected book survived the prune"
        )
        XCTAssertLessThan(pruned.readings.count, selectedReadings.count)
        XCTAssertLessThan(pruned.los.count, selectedLOS.count)
    }

    func testBookIDsMatchTopicIDs() {
        // The cascade relies on questionBank topic IDs equaling los_master area
        // IDs (the values stored in pref.selectedTopics). Guard that alignment.
        let content = loadedContent()
        let areaIDs = Set((content.losMaster?.areas ?? []).map(\.id))
        let topicIDs = Set(content.questionBank?.topics.map(\.id) ?? [])
        XCTAssertFalse(areaIDs.isEmpty)
        XCTAssertEqual(topicIDs, areaIDs,
                       "Practice book filter breaks if topic IDs drift from area IDs")
    }
}

// MARK: - Per-LOS stats behind the checklist

/// The LOS checklist shows an "attempted / correct" figure beside each
/// statement. It counted the case bank only, so the 2,625 LOS drills — the
/// most precisely LOS-tagged content in the app — moved none of it.
final class LOSQuestionStatsTests: XCTestCase {

    private func loadedContent() throws -> ContentLoader {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")
        return content
    }

    private func attempt(_ questionID: String, correct: Bool) -> Attempt {
        Attempt(
            questionId: questionID, caseId: "c", topicId: "t",
            durationSeconds: 30, wasCorrect: correct
        )
    }

    /// Answering a drill must register against the LOS it drills.
    func testADrillAttemptCountsTowardItsLOS() throws {
        let content = try loadedContent()

        // A LOS that actually has drills behind it.
        let losWithDrills = (content.losMaster?.areas ?? [])
            .flatMap(\.readings)
            .flatMap(\.los)
            .first { !content.drills(forLOS: $0.id).isEmpty }
        let los = try XCTUnwrap(losWithDrills, "fixture has no LOS with drills")
        let drill = try XCTUnwrap(content.drills(forLOS: los.id).first)

        let before = StudyPlannerStats.questionStats(losID: los.id, content: content, attempts: [])
        XCTAssertEqual(before.attempted, 0)

        let after = StudyPlannerStats.questionStats(
            losID: los.id, content: content, attempts: [attempt(drill.id, correct: true)]
        )
        XCTAssertEqual(after.attempted, 1, "the drill did not count toward its own LOS")
        XCTAssertEqual(after.correctRate, 1.0)
    }

    /// Bank questions still count — the fix adds drills, it does not swap them.
    func testABankAttemptStillCountsTowardItsLOS() throws {
        let content = try loadedContent()

        let pair = (content.losMaster?.areas ?? [])
            .flatMap(\.readings)
            .flatMap(\.los)
            .lazy
            .compactMap { los -> (String, String)? in
                guard let q = content.questions(matchingLOS: [los.id]).first else { return nil }
                return (los.id, q)
            }
            .first
        let (losID, questionID) = try XCTUnwrap(pair, "fixture has no LOS with bank questions")

        let after = StudyPlannerStats.questionStats(
            losID: losID, content: content, attempts: [attempt(questionID, correct: false)]
        )
        XCTAssertEqual(after.attempted, 1)
        XCTAssertEqual(after.correctRate, 0.0)
    }

    /// The two banks are counted together, not one or the other.
    func testBankAndDrillAttemptsAreBothCounted() throws {
        let content = try loadedContent()

        let combined = (content.losMaster?.areas ?? [])
            .flatMap(\.readings)
            .flatMap(\.los)
            .lazy
            .compactMap { los -> (String, String, String)? in
                guard let q = content.questions(matchingLOS: [los.id]).first,
                      let d = content.drills(forLOS: los.id).first
                else { return nil }
                return (los.id, q, d.id)
            }
            .first
        let (losID, questionID, drillID) = try XCTUnwrap(
            combined, "fixture has no LOS carrying both a bank question and a drill"
        )

        let stats = StudyPlannerStats.questionStats(
            losID: losID,
            content: content,
            attempts: [attempt(questionID, correct: true), attempt(drillID, correct: false)]
        )
        XCTAssertEqual(stats.attempted, 2, "one bank question and one drill is two attempts")
        XCTAssertEqual(stats.correctRate, 0.5)
    }
}
