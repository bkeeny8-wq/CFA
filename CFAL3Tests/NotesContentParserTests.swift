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

// MARK: - Review sheets

/// The combined study-notes DOCX, imported as its own section.
///
/// Deliberately a second copy of material Notes already carries — the owner
/// asked for it that way. These tests guard the import itself: that the
/// extraction kept every block, and that no table came through ragged, which
/// is the defect that made the Notes tables unreadable.
final class ReviewSheetContentTests: XCTestCase {

    private func sheets() throws -> [ReviewSheet] {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")
        return content.reviewSheets
    }

    func testEveryReadingLoadedWithContent() throws {
        let all = try sheets()
        XCTAssertEqual(all.count, 25, "the source document holds 25 readings")
        for sheet in all {
            XCTAssertFalse(sheet.title.isEmpty, "reading \(sheet.number) has no title")
            XCTAssertFalse(sheet.blocks.isEmpty, "\(sheet.title) came through empty")
        }
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "duplicate reading ids")
    }

    /// Word knows each table's width, so nothing here should be ragged. A
    /// renderer walking a ragged grid drops the overhang or crashes.
    func testNoTableIsRagged() throws {
        var tables = 0
        for sheet in try sheets() {
            for block in sheet.blocks {
                guard case .table(let headers, let rows) = block else { continue }
                tables += 1
                XCTAssertGreaterThanOrEqual(headers.count, 2,
                                            "\(sheet.title): a 1-column table is a box, not a table")
                for row in rows {
                    XCTAssertEqual(row.count, headers.count,
                                   "\(sheet.title): row of \(row.count) under \(headers.count) headers")
                }
            }
        }
        XCTAssertGreaterThan(tables, 50, "the document has 64 real tables")
    }

    /// The worked examples, formula sheets and self-tests are one-cell tables
    /// in the source. An earlier pass dropped everything with fewer than two
    /// rows and lost all 206 of them.
    func testBoxedAsidesSurvivedTheImport() throws {
        let all = try sheets()
        let boxes = all.flatMap(\.blocks).filter { if case .box = $0 { return true }; return false }
        XCTAssertGreaterThan(boxes.count, 150, "boxed asides were dropped on import")

        let text = all.flatMap(\.blocks).compactMap { block -> String? in
            if case .box(let lines) = block { return lines.joined(separator: " ") }
            return nil
        }.joined(separator: " ")
        XCTAssertTrue(text.contains("Worked example"), "worked examples are missing")
        XCTAssertTrue(text.contains("formula"), "the formula sheets are missing")
    }

    /// Distinct blocks need distinct ids or ForEach drops rows.
    func testBlockIDsAreDistinctWithinASheet() throws {
        for sheet in try sheets() {
            var seen: [String: ReviewBlock] = [:]
            for block in sheet.blocks {
                if let clash = seen[block.id], clash != block {
                    XCTFail("\(sheet.title): two different blocks share id '\(block.id.prefix(50))'")
                }
                seen[block.id] = block
            }
        }
    }
}
