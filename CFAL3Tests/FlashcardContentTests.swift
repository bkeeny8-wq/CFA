import XCTest
@testable import CFAL3

/// Locks the flashcard deck's content contract: every card decodes, is
/// addressable, carries what its type promises, and points at a real reading
/// and LOS. A regenerated deck that breaks any of these fails here rather than
/// silently shipping a dead card.
final class FlashcardContentTests: XCTestCase {

    private func loadedContent() -> ContentLoader {
        let content = ContentLoader()
        content.load()
        return content
    }

    func testDeckLoadsAndIsNonTrivial() {
        let content = loadedContent()
        XCTAssertNil(content.loadError, content.loadError ?? "")
        XCTAssertGreaterThan(content.totalFlashcards, 300, "expected a few hundred cards")
        XCTAssertEqual(content.allFlashcards.count, content.totalFlashcards)
    }

    func testIDsAreUniqueAndResolvable() {
        let content = loadedContent()
        let cards = content.allFlashcards
        XCTAssertEqual(Set(cards.map(\.id)).count, cards.count, "duplicate card IDs")
        for card in cards {
            XCTAssertEqual(content.flashcard(id: card.id)?.id, card.id)
        }
    }

    func testEveryCardHasContentAndFormulaCardsHaveFormulas() {
        for card in loadedContent().allFlashcards {
            XCTAssertFalse(card.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "empty front: \(card.id)")
            XCTAssertFalse(card.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "empty back: \(card.id)")
            if card.type == .formula {
                let f = card.formula?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                XCTAssertFalse(f.isEmpty, "formula card without a formula: \(card.id)")
            }
        }
    }

    func testCardsMapToRealReadingsAreasAndLOS() {
        let content = loadedContent()
        let master = content.losMaster
        XCTAssertNotNil(master)
        let areas = master?.areas ?? []
        let readingIDs = Set(areas.flatMap { $0.readings.map(\.id) })
        let areaIDs = Set(areas.map(\.id))
        let losIDs = Set(areas.flatMap { $0.readings.flatMap { $0.los.map(\.id) } })

        for card in content.allFlashcards {
            XCTAssertTrue(readingIDs.contains(card.readingID), "unknown reading: \(card.id)")
            XCTAssertTrue(areaIDs.contains(card.areaID), "unknown area: \(card.id)")
            if !card.losID.isEmpty {
                XCTAssertTrue(losIDs.contains(card.losID), "unknown LOS on \(card.id): \(card.losID)")
            }
        }
    }

    func testEveryReadingHasADeck() {
        let content = loadedContent()
        for area in content.losMaster?.areas ?? [] {
            for reading in area.readings {
                XCTAssertFalse(content.flashcards(forReading: reading.id).isEmpty,
                               "no flashcards for reading \(reading.id)")
            }
        }
    }

    /// Cards and questions must age through the same algorithm — a regression
    /// here would silently desynchronize the two review queues.
    func testFlashcardProgressUsesTheSharedSM2Schedule() {
        let row = FlashcardProgress(cardId: "t", readingId: "r", areaId: "a")
        ReviewScheduler.update(item: row, quality: 5)
        XCTAssertEqual(row.interval, 1)
        XCTAssertEqual(row.repetitions, 1)
        ReviewScheduler.update(item: row, quality: 5)
        XCTAssertEqual(row.interval, 6, "second success must jump to the SM-2 6-day step")
        XCTAssertGreaterThan(row.easeFactor, 2.5, "easy ratings raise the ease factor")

        ReviewScheduler.update(item: row, quality: 1)
        XCTAssertEqual(row.interval, 1, "a lapse resets the interval")
        XCTAssertEqual(row.repetitions, 0)
        XCTAssertLessThan(row.easeFactor, 2.7, "failure penalizes EF (deliberate deviation)")
        XCTAssertGreaterThanOrEqual(row.easeFactor, 1.3, "EF floor")
    }
}
