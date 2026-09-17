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
