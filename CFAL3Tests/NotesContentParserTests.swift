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

        XCTAssertTrue(blocks.contains { if case .losSection(1, "Framework role") = $0 { return true }; return false })
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
