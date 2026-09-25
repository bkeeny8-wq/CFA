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
        XCTAssertEqual(content.totalFlashcards, 2_997, "atomized deck size")
        XCTAssertEqual(content.allFlashcards.count, content.totalFlashcards)
    }

    func testAtomizedBacksStayShort() {
        let cards = loadedContent().allFlashcards
        let words = cards.map { $0.back.split { $0.isWhitespace || $0.isNewline }.count }.sorted()
        XCTAssertFalse(words.isEmpty)
        let median = words[words.count / 2]
        XCTAssertLessThanOrEqual(median, 40, "median back should be one idea, not a note")
        let p90 = words[Int(Double(words.count) * 0.9)]
        XCTAssertLessThanOrEqual(p90, 50)
        XCTAssertLessThanOrEqual(words.last ?? 0, 49, "no remaining booklet-length backs")
    }

    /// The reported bug: splitting a long back into atoms labelled each atom
    /// by summarising its own back, so most fronts opened with the answer's
    /// first words and the card arrived already revealed. A front may carry
    /// only the prompt and a positional "part n of m".
    func testFrontsDoNotGiveAwayTheirOwnAnswer() {
        let part = /^part \d+ of \d+$/
        for card in loadedContent().allFlashcards {
            let blocks = card.front.components(separatedBy: "\n\n")
            for block in blocks.dropFirst() {
                XCTAssertNotNil(
                    try? part.wholeMatch(in: block.trimmingCharacters(in: .whitespacesAndNewlines)),
                    "front of \(card.id) carries answer text after the prompt: \(block)"
                )
            }
        }
    }

    /// Atoms of one source card share a base id, so their part numbers must
    /// run 1...n over exactly that group. Re-splitting an already-split card
    /// used to leave stale counts like "part 2 of 3" in a group of six.
    func testPartLabelsNumberTheirOwnGroup() {
        let cards = loadedContent().allFlashcards
        let base = { (id: String) in id.replacing(/(_p\d+)+$/, with: "") }
        var totals: [String: Int] = [:]
        for card in cards { totals[base(card.id), default: 0] += 1 }

        var seen: [String: Int] = [:]
        for card in cards {
            let group = base(card.id)
            seen[group, default: 0] += 1
            let expected = totals[group] == 1
                ? nil : "part \(seen[group]!) of \(totals[group]!)"
            let suffix = card.front.components(separatedBy: "\n\n").dropFirst().first
            XCTAssertEqual(suffix, expected, "wrong part label on \(card.id)")
        }
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

    // MARK: - Queue

    private func deck(_ n: Int, reading: String = "r1") -> [Flashcard] {
        (1...n).map {
            Flashcard(
                id: "c\($0)", readingID: reading, areaID: "a1", losID: "los1",
                type: .concept, front: "f", back: "b",
                formula: nil, mnemonic: nil, difficulty: .core
            )
        }
    }

    private func row(_ id: String, attempts: Int, due: Date = .now, first: Date? = nil) -> FlashcardProgress {
        let r = FlashcardProgress(cardId: id, readingId: "r1", areaId: "a1")
        r.totalAttempts = attempts
        r.dueDate = due
        r.firstAttemptedAt = first
        return r
    }

    /// The reported bug: every card was seeded due, and a card with no row at
    /// all also read as due, so a fresh install announced the whole deck.
    func testFreshDeckHasNothingDueAndIsMeteredByTheDailyLimit() {
        let p = FlashcardQueue.plan(cards: deck(445), progress: [], dailyNewLimit: 20)
        XCTAssertEqual(p.dueCount, 0, "an unrated card is not 'due'")
        XCTAssertEqual(p.notStartedCount, 445)
        XCTAssertEqual(p.sessionIDs.count, 20)
    }

    func testASeededRowWithNoRatingsIsStillNotDue() {
        let cards = deck(10)
        let rows = cards.map { row($0.id, attempts: 0) }
        let p = FlashcardQueue.plan(cards: cards, progress: rows, dailyNewLimit: 5)
        XCTAssertEqual(p.dueCount, 0)
        XCTAssertEqual(p.notStartedCount, 10)
        XCTAssertEqual(p.sessionIDs.count, 5)
    }

    func testRatedCardsComeBackWhenTheirIntervalElapses() {
        let cards = deck(4)
        let past = Date.now.addingTimeInterval(-3_600)
        let rows = [
            row("c1", attempts: 1, due: past, first: past),
            row("c2", attempts: 1, due: .now.addingTimeInterval(86_400), first: past),
        ]
        let p = FlashcardQueue.plan(cards: cards, progress: rows, dailyNewLimit: 0)
        XCTAssertEqual(p.dueCount, 1, "only the elapsed one is due")
        XCTAssertEqual(p.notStartedCount, 2)
        XCTAssertEqual(p.sessionIDs, ["c1"])
    }

    func testTodaysAllowanceIsSpentByCardsFirstRatedToday() {
        let cards = deck(50)
        let rows = (1...20).map { row("c\($0)", attempts: 1, due: .now.addingTimeInterval(86_400), first: .now) }
        let p = FlashcardQueue.plan(cards: cards, progress: rows, dailyNewLimit: 20)
        XCTAssertEqual(p.introducedToday, 20)
        XCTAssertEqual(p.newRemainingToday, 0)
        XCTAssertTrue(p.isEmpty)
        XCTAssertTrue(p.isNewExhausted)
    }

    func testCardsFirstRatedYesterdayDoNotSpendTodaysAllowance() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let cards = deck(30)
        let rows = (1...10).map {
            row("c\($0)", attempts: 2, due: .now.addingTimeInterval(86_400), first: yesterday)
        }
        let p = FlashcardQueue.plan(cards: cards, progress: rows, dailyNewLimit: 20)
        XCTAssertEqual(p.introducedToday, 0)
        XCTAssertEqual(p.newRemainingToday, 20)
    }

    /// A row predating this field reads nil and must not crash or be counted.
    func testRowsWithoutAFirstRatingDateAreNotCountedAsIntroducedToday() {
        let rows = [row("c1", attempts: 5, first: nil)]
        XCTAssertEqual(FlashcardQueue.introducedToday(progress: rows), 0)
    }

    func testTheCountShownIsTheSessionItStarts() {
        let cards = deck(100)
        let p = FlashcardQueue.plan(cards: cards, progress: [], dailyNewLimit: 20)
        XCTAssertEqual(p.sessionIDs.count, p.dueInSession + p.newInSession + p.flaggedInSession)
        XCTAssertEqual(Set(p.sessionIDs).count, p.sessionIDs.count, "no duplicates")
        XCTAssertFalse(p.isEmpty)
    }

    func testAnEmptyDeckYieldsAnEmptyPlanRatherThanACrash() {
        let p = FlashcardQueue.plan(cards: [], progress: [], dailyNewLimit: 20)
        XCTAssertTrue(p.isEmpty)
        XCTAssertEqual(p.dueCount, 0)
    }

    func testPlanIsStableRegardlessOfDeckOrder() {
        let cards = deck(40)
        let a = FlashcardQueue.plan(cards: cards, progress: [], dailyNewLimit: 20)
        let b = FlashcardQueue.plan(cards: cards.reversed(), progress: [], dailyNewLimit: 20)
        XCTAssertEqual(a.sessionIDs, b.sessionIDs)
    }

    func testSkippedFlagComesBackWithoutSpendingTheNewRation() {
        let cards = deck(50)
        let flagged = FlashcardProgress(cardId: "c1", readingId: "r1", areaId: "a1")
        flagged.flaggedForReview = true
        let p = FlashcardQueue.plan(cards: cards, progress: [flagged], dailyNewLimit: 0)
        XCTAssertEqual(p.flaggedCount, 1)
        XCTAssertEqual(p.sessionIDs.first, "c1")
        XCTAssertEqual(p.newInSession, 0, "a skip must not spend the new-card ration")
    }

    func testFlaggedFutureDueCardReturnsToday() {
        let cards = deck(2)
        let flagged = row("c1", attempts: 3, due: .now.addingTimeInterval(86_400))
        flagged.flaggedForReview = true
        let p = FlashcardQueue.plan(cards: cards, progress: [flagged], dailyNewLimit: 0)
        XCTAssertEqual(p.dueCount, 0)
        XCTAssertEqual(p.flaggedCount, 1)
        XCTAssertEqual(p.sessionIDs, ["c1"])
    }
}
