import XCTest
@testable import CFAL3

/// The outline is what the sticky header, the "N of M" counter, the left rail
/// and the collapse state all read from. It indexes the same block array the
/// page renders, so these tests are the guard against the two drifting.
final class NotesOutlineTests: XCTestCase {

    private func loadedContent() throws -> ContentLoader {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")
        return content
    }

    private func page(_ id: String) throws -> NotesPage {
        let content = try loadedContent()
        return NotesPage(try XCTUnwrap(content.readingNotes(id: id)))
    }

    // MARK: - Ranges index the rendered array

    /// Every section's range must point at its own header. If `NotesPage`
    /// ever builds the outline BEFORE inserting the orientation paragraph,
    /// every range shifts by one and each section claims the block above it.
    /// Mutation: build the outline before the insert — this fails on the first
    /// reading with an orientation.
    func testSectionRangesPointAtTheirOwnHeaders() throws {
        let content = try loadedContent()
        var checked = 0

        for entry in content.readingNotesBundle?.readings ?? [] {
            let page = NotesPage(entry)
            for section in page.outline.sections {
                let block = page.blocks[section.range.lowerBound]
                let heading = try XCTUnwrap(
                    block.losSectionHeading,
                    "\(entry.readingID): section range starts on a non-header block"
                )
                XCTAssertEqual(heading.number, section.number)
                XCTAssertEqual(heading.title, section.title)
                checked += 1
            }
        }
        XCTAssertEqual(checked, 193, "the set of LOS sections in the corpus moved")
    }

    /// The ranges must tile the array: preamble, then every section end-to-end,
    /// with nothing lost and nothing counted twice.
    /// Mutation: end a section at `next.index - 1` — the gap fails here.
    func testRangesTileTheBlockArrayExactly() throws {
        let content = try loadedContent()

        for entry in content.readingNotesBundle?.readings ?? [] {
            let page = NotesPage(entry)
            let outline = page.outline
            var covered = outline.preamble.count
            var cursor = outline.preamble.upperBound

            for section in outline.sections {
                XCTAssertEqual(
                    section.range.lowerBound, cursor,
                    "\(entry.readingID): gap or overlap before LOS \(section.letter)"
                )
                covered += section.range.count
                cursor = section.range.upperBound
            }
            XCTAssertEqual(cursor, page.blocks.count, "\(entry.readingID): trailing blocks lost")
            XCTAssertEqual(covered, page.blocks.count, "\(entry.readingID): coverage mismatch")
        }
    }

    /// The body range excludes the header, because the header carries the
    /// scroll anchor and collapsing must not remove it.
    func testBodyRangeExcludesTheHeaderItself() throws {
        let page = try page("yield_curve_strategies")
        let section = try XCTUnwrap(page.outline.sections.first)
        XCTAssertEqual(section.bodyRange.lowerBound, section.range.lowerBound + 1)
        XCTAssertEqual(section.bodyRange.upperBound, section.range.upperBound)
        XCTAssertNotNil(page.blocks[section.range.lowerBound].losSectionHeading)
    }

    // MARK: - Position is not the number

    /// The counter counts POSITION among present headings; the letter comes
    /// from the NUMBER. For most of the corpus these differ, and conflating
    /// them is the single easiest way to mislabel a statement.
    /// Mutation: return `number` from `position` — this fails on section 3.
    func testPositionCountsHeadingsWhileLetterComesFromTheNumber() throws {
        let page = try page("overview_of_asset_allocation")
        let sections = page.outline.sections

        XCTAssertEqual(sections.map(\.number), [1, 2, 5, 6, 7, 8, 9, 10])
        XCTAssertEqual(sections.map(\.position), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(sections.map(\.letter), ["A", "B", "E", "F", "G", "H", "I", "J"])

        // The third heading is LOS E, and it is "3 of 8" — both true at once.
        XCTAssertEqual(page.outline.counterText(at: 2), "3 of 8")
        XCTAssertEqual(sections[2].letter, "E")
    }

    // MARK: - Anchors

    /// One definition, used by the renderer and by the rail. Mutation: drop
    /// the number from `anchorID` — the collision assertion below fails.
    func testAnchorsAreUniqueWithinEveryReading() throws {
        let content = try loadedContent()
        var readingsWithSections = 0

        for entry in content.readingNotesBundle?.readings ?? [] {
            let outline = NotesPage(entry).outline
            guard !outline.sections.isEmpty else { continue }
            readingsWithSections += 1
            let anchors = outline.sections.map(\.anchorID)
            XCTAssertEqual(
                Set(anchors).count, anchors.count,
                "\(entry.readingID): two sections claim the same scroll anchor"
            )
        }
        XCTAssertEqual(readingsWithSections, 27, "the set of readings with sections moved")
    }

    func testAnchorLookupRoundTrips() throws {
        let outline = try page("yield_curve_strategies").outline
        for (index, section) in outline.sections.enumerated() {
            XCTAssertEqual(outline.index(ofAnchor: section.anchorID), index)
        }
        XCTAssertNil(outline.index(ofAnchor: "los-999-nothing"))
    }

    // MARK: - Degenerate readings

    /// Nine ethics readings have no LOS headings at all. Everything must be
    /// preamble, and the chrome must switch itself off rather than render
    /// empty. Mutation: return `showsStickyHeader = true` unconditionally.
    func testReadingWithNoHeadingsIsAllPreambleAndHasNoChrome() throws {
        let page = try page("code_and_standards")
        XCTAssertTrue(page.outline.sections.isEmpty)
        XCTAssertEqual(page.outline.preamble, 0..<page.blocks.count)
        XCTAssertFalse(page.outline.showsStickyHeader)
        XCTAssertFalse(page.outline.showsRail)
        XCTAssertFalse(page.blocks.isEmpty, "the reading still has content to show")
        XCTAssertNil(page.outline.counterText(at: 0))
        XCTAssertNil(page.outline.section(at: 0), "must not trap on an empty outline")
    }

    /// `principles_of_asset_allocation` opens with "LOS 1 & 2 — …", a form the
    /// parser's grammar does not match, so roughly forty blocks of real LOS
    /// material sit in the preamble. The outline must carry them rather than
    /// discard them — dropping the preamble would silently delete that content
    /// from the page.
    func testPreambleCarriesContentBeforeTheFirstRecognisedHeading() throws {
        let page = try page("principles_of_asset_allocation")
        XCTAssertGreaterThan(
            page.outline.preamble.count, 10,
            "this reading's unrecognised first heading leaves real content up front"
        )
        XCTAssertEqual(page.outline.sections.first?.number, 3, "first recognised heading is LOS 3")
        XCTAssertEqual(page.outline.preamble.lowerBound, 0)
    }

    func testCounterIsNilWhenThereIsNothingToCount() {
        let outline = NotesOutline.build(from: [.paragraph("only prose")])
        XCTAssertTrue(outline.sections.isEmpty)
        XCTAssertNil(outline.counterText(at: 0))

        let single = NotesOutline.build(from: [.losSection(number: 1, title: "Only"), .paragraph("x")])
        XCTAssertEqual(single.sections.count, 1)
        XCTAssertFalse(single.showsRail, "one section needs no rail")
        XCTAssertTrue(single.showsStickyHeader)
        XCTAssertNil(single.counterText(at: 0), "\"1 of 1\" is noise")
    }

    // MARK: - Collapse state

    /// Keyed by anchor, not index — otherwise opening a different reading
    /// collapses whichever section happens to sit at the same position.
    func testCollapseIsKeyedByAnchorNotPosition() throws {
        let first = try page("yield_curve_strategies").outline
        let second = try page("overview_of_asset_allocation").outline

        var expansion = NotesSectionExpansion()
        expansion.toggle(first.sections[0])

        XCTAssertTrue(expansion.isCollapsed(first.sections[0]))
        XCTAssertFalse(
            expansion.isCollapsed(second.sections[0]),
            "a collapse in one reading leaked into another reading's first section"
        )
    }

    func testToggleAndExpandAll() throws {
        let outline = try page("yield_curve_strategies").outline
        var expansion = NotesSectionExpansion()

        expansion.collapseAll(outline)
        XCTAssertTrue(expansion.allCollapsed(outline))

        expansion.expand(outline.sections[0])
        XCTAssertFalse(expansion.allCollapsed(outline))
        XCTAssertFalse(expansion.isCollapsed(outline.sections[0]))

        expansion.expandAll()
        XCTAssertTrue(outline.sections.allSatisfy { !expansion.isCollapsed($0) })
    }

    // MARK: - Scroll tracking

    /// The measured map is SPARSE — only headers the scroll view has laid out
    /// report a position — so the tracker must never assume index continuity.
    /// Mutation: use `tops.count - 1` instead of `passed.max()`.
    func testCurrentSectionFromASparseMeasurementMap() {
        let tops: [Int: CGFloat] = [0: -900, 3: -120, 5: 40]
        XCTAssertEqual(
            NotesScrollTracker.currentIndex(tops: tops, threshold: 8, sectionCount: 8),
            3,
            "index 5 is still below the threshold; 3 is the last one passed"
        )
    }

    func testPreambleReportsNoCurrentSection() {
        let tops: [Int: CGFloat] = [0: 500, 1: 900]
        XCTAssertNil(
            NotesScrollTracker.currentIndex(tops: tops, threshold: 8, sectionCount: 4),
            "nothing has scrolled past the top yet"
        )
    }

    /// A final section shorter than the viewport physically cannot scroll to
    /// the top, so without this the rail's last letter would never light up.
    /// Mutation: drop the `atBottom` branch.
    func testTheLastSectionWinsAtTheBottomEvenIfItNeverReachesTheTop() {
        let tops: [Int: CGFloat] = [6: -400, 7: 752]
        XCTAssertEqual(
            NotesScrollTracker.currentIndex(tops: tops, threshold: 8, sectionCount: 8),
            6,
            "mid-scroll, the short last section has not been passed"
        )
        XCTAssertEqual(
            NotesScrollTracker.currentIndex(tops: tops, threshold: 8, sectionCount: 8, atBottom: true),
            7,
            "at the bottom of the document the last section is what you are reading"
        )
    }

    /// The physical bottom test, independent of the tracker.
    func testIsAtBottomNeedsBothMeasurementsAndToleratesOverscroll() {
        XCTAssertFalse(NotesScrollTracker.isAtBottom(contentEnd: nil, viewportHeight: 1000))
        XCTAssertFalse(NotesScrollTracker.isAtBottom(contentEnd: 900, viewportHeight: nil))
        XCTAssertFalse(NotesScrollTracker.isAtBottom(contentEnd: 4000, viewportHeight: 1000))
        XCTAssertTrue(NotesScrollTracker.isAtBottom(contentEnd: 1010, viewportHeight: 1000))
        XCTAssertTrue(
            NotesScrollTracker.isAtBottom(contentEnd: -50, viewportHeight: 1000),
            "overscroll bounce is still the bottom"
        )
    }

    func testTrackerIgnoresOutOfRangeAndEmptyOutlines() {
        XCTAssertNil(
            NotesScrollTracker.currentIndex(tops: [:], threshold: 8, sectionCount: 0),
            "a reading with no sections has no current section, even at the bottom"
        )
        XCTAssertNil(
            NotesScrollTracker.currentIndex(tops: [:], threshold: 8, sectionCount: 0, atBottom: true)
        )
        XCTAssertNil(
            NotesScrollTracker.currentIndex(tops: [:], threshold: 8, sectionCount: 3, atBottom: true),
            """
            Collapse every section and a whole reading can be shorter than the \
            viewport — trivially "at the bottom" while you are looking at the \
            top. Nothing has been passed, so nothing is current.
            """
        )
        // A measurement left over from a longer reading must not select an
        // index this outline does not have — `sections[9]` would trap.
        XCTAssertNil(
            NotesScrollTracker.currentIndex(tops: [9: -10], threshold: 8, sectionCount: 3),
            "a stale measurement for a section that no longer exists must be ignored"
        )
    }
}
