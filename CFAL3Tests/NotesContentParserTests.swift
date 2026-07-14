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
    }
}
