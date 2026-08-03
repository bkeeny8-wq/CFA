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

        // Same predicate the readings sheet uses: filter areas by chosen book.
        for area in areas {
            let scopeTopics: Set<String> = [area.id]
            let visible = areas.filter { scopeTopics.contains($0.id) }
            XCTAssertEqual(visible.map(\.id), [area.id],
                           "Only the chosen book should be offered")

            let visibleReadings = Set(visible.flatMap { $0.readings.map(\.id) })
            XCTAssertFalse(visibleReadings.isEmpty, "\(area.id) has readings")
            XCTAssertTrue(visibleReadings.isSubset(of: allReadingIDs))
            // Every visible reading actually belongs to the chosen book.
            for reading in visible.flatMap(\.readings) {
                XCTAssertEqual(reading.areaID, area.id)
            }
        }

        // With more than one book, a single-book scope is a strict subset.
        if areas.count > 1, let first = areas.first {
            let scoped = Set(areas.filter { [first.id].contains($0.id) }
                .flatMap { $0.readings.map(\.id) })
            XCTAssertLessThan(scoped.count, allReadingIDs.count)
        }
    }

    func testLOSNarrowToSelectedReadings() {
        let content = loadedContent()
        let allReadings = (content.losMaster?.areas ?? []).flatMap(\.readings)
        XCTAssertFalse(allReadings.isEmpty)

        let allLOS = Set(allReadings.flatMap { $0.los.map(\.id) })

        // Pick two readings; the LOS sheet's readingScope predicate must yield
        // exactly those readings' LOS and nothing else.
        let sample = Array(allReadings.prefix(2))
        let readingScope = Set(sample.map(\.id))
        let visibleReadings = allReadings.filter { readingScope.contains($0.id) }
        let visibleLOS = Set(visibleReadings.flatMap { $0.los.map(\.id) })

        let expected = Set(sample.flatMap { $0.los.map(\.id) })
        XCTAssertEqual(visibleLOS, expected)
        XCTAssertTrue(visibleLOS.isSubset(of: allLOS))
        if allReadings.count > 2 {
            XCTAssertLessThan(visibleLOS.count, allLOS.count)
        }
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
