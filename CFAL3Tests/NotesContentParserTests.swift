import XCTest
@testable import CFAL3

final class NotesContentParserTests: XCTestCase {
    func testParsesLOSSectionAndCallouts() {
        let sample = """
        LOS 1 — Framework role
        LOS: discuss the role of capital market expectations
        What you must do: Explain why CME matter.
        Core idea. CME are expectations for asset classes.
        Exam focus: Know the seven steps.
        The 7-step framework
        \t•\tStep one
        \t•\tStep two
        """

        let blocks = NotesContentParser.parse(sample, skipHeader: false)

        XCTAssertTrue(blocks.contains { if case .losSection([1], nil, "Framework role") = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .losStatement = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .callout(.examFocus, _) = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .bulletList(let items) = $0 { return items.count == 2 }; return false })
    }

    func testParsesTable() {
        let sample = """
        Table 1 — Sample table
        Col A
        Col B
        Col C
        Row1A
        Row1B
        Row1C
        Row2A
        Row2B
        Row2C
        Next section
        """

        let blocks = NotesContentParser.parse(sample, skipHeader: false)
        let table = blocks.first {
            if case .table(let title, let headers, let rows) = $0 {
                return title == "Sample table" && headers.count == 3 && rows.count == 2
            }
            return false
        }
        XCTAssertNotNil(table)

        // "Next section" completes no row, so it belongs to the document, not
        // to the table. It used to be dropped on the floor.
        XCTAssertTrue(
            blocks.contains { block in
                if case .paragraph(let text) = block { return text.contains("Next section") }
                if case .subheading(let text) = block { return text.contains("Next section") }
                return false
            },
            "the line after the table was swallowed: \(blocks.map(\.id))"
        )
    }

    // MARK: - Against the real bundled notes

    private func loadedContent() -> ContentLoader {
        let content = ContentLoader()
        content.load()
        return content
    }

    private func allReadingNotes(_ content: ContentLoader) -> [ReadingNotesEntry] {
        content.readingNotesBundle?.readings ?? []
    }

    /// Half the bundled tables are not 3 columns. Assuming they were turned a
    /// 4-column table's last header into its first body cell and offset every
    /// row after it, while still looking like a legitimate table.
    func testBundledTablesKeepTheirOwnColumnCount() {
        let content = loadedContent()
        let notes = allReadingNotes(content)
        XCTAssertFalse(notes.isEmpty)

        var widths: [Int: Int] = [:]
        for entry in notes {
            for block in NotesContentParser.parse(entry.content) {
                guard case .table(let title, let headers, let rows) = block else { continue }
                widths[headers.count, default: 0] += 1
                for row in rows {
                    XCTAssertEqual(
                        row.count, headers.count,
                        "\(title): a row has \(row.count) cells under \(headers.count) headers"
                    )
                }
            }
        }
        XCTAssertGreaterThan(widths.count, 1,
                             "every table came out the same width — the count is being assumed again")
        XCTAssertNotNil(widths[4], "the bundle contains 4-column tables; none survived as one")
    }

    /// Every line a table gathers either lands in the grid or stays in the
    /// document. Nothing may be silently discarded: the old parser dropped 57
    /// cells across the bundle and absorbed the paragraphs after each table.
    func testTablesNeitherDropLinesNorSwallowTheProseAfterThem() {
        let content = loadedContent()

        for entry in allReadingNotes(content) {
            let blocks = NotesContentParser.parse(entry.content)
            for block in blocks {
                guard case .table(let title, let headers, let rows) = block else { continue }
                let cellCount = headers.count + rows.count * headers.count

                // Every cell in the grid must be a line of the source, and the
                // grid must be a whole number of rows.
                XCTAssertEqual(cellCount % headers.count, 0, "\(title): ragged grid")
                XCTAssertGreaterThanOrEqual(rows.count, 1, "\(title): table with no body")

                for cell in headers + rows.flatMap({ $0 }) {
                    XCTAssertTrue(
                        entry.content.contains(cell),
                        "\(title): cell '\(cell.prefix(40))' is not in the source"
                    )
                    XCTAssertLessThanOrEqual(
                        cell.count, 150,
                        "\(title): a paragraph was absorbed as a cell — '\(cell.prefix(60))'"
                    )
                }
            }
        }
    }

    /// Three bundled tables shipped with a wrong `tableColumnCounts` entry.
    /// A wrong count does not fail — it SHIFTS every row by the difference and
    /// drops the remainder into the next paragraph, so the table still renders
    /// as a table while stating something untrue. The GIPS composite
    /// presentation was declared 6 columns against a real 8: every year's
    /// figures were offset by two and its last two cells ("520M", "3,400M")
    /// fell out as a stray line of prose.
    ///
    /// Pins the shape of the three, by header row and row count. A corpus-wide
    /// "cells divide evenly" rule cannot work here: the parser deliberately
    /// over-gathers and lets a trailing non-cell line fall back to the
    /// document, which `testParsesTable` pins.
    ///
    /// Mutation: set any of the three counts back and its assertion fails.
    func testTheThreeMiscountedTablesKeepTheirRealShape() {
        let content = loadedContent()

        func table(_ readingID: String, titled title: String) -> (headers: [String], rows: [[String]])? {
            guard let entry = allReadingNotes(content).first(where: { $0.readingID == readingID })
            else { return nil }
            for block in NotesContentParser.parse(entry.content) {
                if case .table(let t, let headers, let rows) = block, t == title {
                    return (headers, rows)
                }
            }
            return nil
        }

        // 8 columns, 3 years of data — not 6.
        let gips = table(
            "overview_of_the_global_investment_performance_standards",
            titled: "Illustrative GIPS composite presentation (extract)"
        )
        XCTAssertEqual(gips?.headers.count, 8, "the GIPS table is 8 columns wide")
        XCTAssertEqual(gips?.headers.last, "Firm assets")
        XCTAssertEqual(gips?.rows.count, 3, "one row per year: 2022, 2023, 2024")
        XCTAssertEqual(gips?.rows.first?.first, "2022", "row 1 must START on the year")
        XCTAssertEqual(gips?.rows.last?.last, "3,400M", "the last cell must not be dropped")

        // 2 columns, 3 approaches — not 3.
        let seg = table(
            "overview_of_equity_portfolio_management",
            titled: "The three primary segmentation approaches"
        )
        XCTAssertEqual(seg?.headers, ["Approach", "Segments"])
        XCTAssertEqual(seg?.rows.count, 3, "the table names three approaches")
        XCTAssertEqual(seg?.rows.last?.first, "Economic activity (sector / industry)",
                       "the third approach was being dropped entirely")

        // A labelled 2x2: the export lost the empty corner, so no column count
        // could make it whole until the corner was restored in the content.
        let matrix = table(
            "active_equity_investing_portfolio_construction",
            titled: "Active Share vs active risk"
        )
        XCTAssertEqual(matrix?.headers,
                       ["Active Share / active risk", "Low active risk", "High active risk"])
        XCTAssertEqual(matrix?.rows.count, 2)
        XCTAssertEqual(matrix?.rows.first?.first, "Low Active Share")
        XCTAssertEqual(matrix?.rows.last?.first, "High Active Share",
                       "the high-Active-Share quadrants were being dropped")
    }

    /// `ForEach` needs distinct ids. These were built from `text.prefix(32)`,
    /// so two blocks opening the same way claimed the same identity.
    func testBlockIDsAreDistinctWithinAReading() {
        let content = loadedContent()

        for entry in allReadingNotes(content) {
            let blocks = NotesContentParser.parse(entry.content)
            var seen: [String: NotesBlock] = [:]
            for block in blocks {
                if let clash = seen[block.id], clash != block {
                    XCTFail(
                        "\(entry.readingID): two different blocks share the id '\(block.id.prefix(60))'"
                    )
                }
                seen[block.id] = block
            }
        }
    }
}

// MARK: - LOS lettering

/// The notes headings are labelled with curriculum letters, and the mapping
/// from the export's number is only valid because that number is the LOS's
/// index within its reading rather than the heading's position in the notes.
/// These lock both halves of that claim.
final class NotesLOSLetteringTests: XCTestCase {

    func testNumbersMapToCurriculumLetters() {
        XCTAssertEqual(losLetter(for: 1), "a")
        XCTAssertEqual(losLetter(for: 7), "g")
        XCTAssertEqual(losLetter(for: 16), "p")
        XCTAssertEqual(losLetter(for: 26), "z")
    }

    /// Out of range falls back to the number rather than to a wrong letter or
    /// an empty label — a blank badge is the one outcome worse than a digit,
    /// since the badge is the page's only wayfinding.
    func testOutOfRangeFallsBackToTheNumber() {
        XCTAssertEqual(losLetter(for: 27), "27")
        XCTAssertEqual(losLetter(for: 0), "0")
        XCTAssertEqual(losLetter(for: -3), "-3")
    }

    /// Every reading's headings now cover its LOS contiguously, 1...N.
    ///
    /// This test replaces one asserting the opposite. The old grammar matched
    /// only `LOS <digits>`, so `overview_of_asset_allocation` appeared to run
    /// 1, 2, 5, 6, 7, 8, 9, 10 and skip two statements. It never skipped them:
    /// its third heading reads "LOS 3 & 4", which the parser could not see, so
    /// that section was not a section and its two numbers were invisible.
    /// Widening the grammar closed every such gap in the corpus.
    ///
    /// Which makes this the sharpest guard available on the grammar: a heading
    /// form it stops recognising punches a hole in some reading's run, and
    /// that hole fails here with the reading named.
    func testEveryReadingCoversItsLOSContiguously() throws {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")

        var checked = 0
        for entry in content.readingNotesBundle?.readings ?? [] {
            let numbers = NotesContentParser.parse(entry.content)
                .compactMap { block -> [Int]? in
                    if case .losSection(let numbers, _, _) = block { return numbers }
                    return nil
                }
                .flatMap { $0 }
                .sorted()
            guard !numbers.isEmpty else { continue }   // the nine Ethics readings

            XCTAssertEqual(
                Array(Set(numbers)).sorted(), Array(1...numbers.max()!),
                "\(entry.readingID): LOS numbers are not a complete run - "
                + "a heading form the grammar no longer recognises"
            )
            checked += 1
        }
        XCTAssertEqual(checked, 27, "the set of readings with headings moved")
    }

    /// A combined heading is ONE section covering several statements, so after
    /// one appears a section's position and its letter diverge. That is why
    /// the two are separate fields and neither is derived from the other.
    func testACombinedHeadingDecouplesPositionFromLetter() throws {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")

        let notes = try XCTUnwrap(content.readingNotes(id: "overview_of_asset_allocation"))
        let sections = NotesContentParser.parse(notes.content).compactMap { block -> [Int]? in
            if case .losSection(let numbers, _, _) = block { return numbers }
            return nil
        }

        XCTAssertEqual(sections, [[1], [2], [3, 4], [5], [6], [7], [8], [9], [10]])
        XCTAssertEqual(losLetters(for: sections[2]), "C & D", "one section, two statements")
        // Position 4 (1-based) is LOS e, not LOS d: the combined section above
        // consumed two numbers while occupying one slot.
        XCTAssertEqual(losLetters(for: sections[3]), "E")
    }

    /// Every letter a notes heading shows must name a LOS the curriculum
    /// actually has under that reading — otherwise the notes and the LOS
    /// checklist disagree about what "g" means. Two readings are known to
    /// overflow their master list; they are named here so the exception stays
    /// visible instead of being absorbed by a loose assertion.
    func testLettersNameRealLOSInTheirReading() throws {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")
        let master = try XCTUnwrap(content.losMaster)

        let knownOverflow: Set<String> = [
            "active_equity_investing_portfolio_construction",
            "case_study_in_portfolio_management_institutional_endowment"
        ]
        var checked = 0

        for reading in master.areas.flatMap(\.readings) {
            guard let notes = content.readingNotes(id: reading.id) else { continue }
            let letters = Set(reading.los.map { $0.letter.lowercased() })
            let headings = NotesContentParser.parse(notes.content).compactMap { block -> Int? in
                if case .losSection(let numbers, _, _) = block { return numbers.first }
                return nil
            }
            guard !headings.isEmpty else { continue }

            if knownOverflow.contains(reading.id) {
                XCTAssertGreaterThan(headings.count, 0)
                continue
            }

            for number in headings {
                XCTAssertTrue(
                    letters.contains(losLetter(for: number)),
                    "\(reading.id): notes label LOS \(losLetter(for: number)) but the reading has none"
                )
            }
            checked += 1
        }

        // Exactly 25: 36 readings carry notes, nine of them are ethics
        // readings whose notes have no LOS headings at all, and two overflow
        // and are skipped above. A floor rather than an equality would let the
        // scan quietly shrink to one reading and still pass.
        XCTAssertEqual(checked, 25, "the set of readings being scanned moved")
    }
}
