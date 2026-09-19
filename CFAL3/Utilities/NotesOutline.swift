import Foundation

/// A reading's notes seen as SECTIONS rather than a flat list of blocks.
///
/// This indexes INTO the block array the page renders; it never copies blocks.
/// That is the whole point. `ReadingNotesView` and `ReadingNotesBlocksView`
/// each used to build the scroll-anchor string by hand, and a drift in either
/// copy would have broken the jump bar silently, with no test able to see it.
/// Here the outline and the blocks come from one array, so they cannot
/// disagree.
struct NotesOutline: Equatable {

    struct Section: Equatable, Identifiable {
        /// The LOS index within its reading, exactly as the export wrote it.
        /// NOT the heading's position — 11 of 36 readings skip numbers, so
        /// `overview_of_asset_allocation` runs 1, 2, 5, 6, 7, 8, 9, 10. Never
        /// renumber this; the letter is derived from it.
        let number: Int
        let title: String
        /// 1-based position among the headings actually PRESENT in this
        /// reading — the numerator of "2 of 7". Deliberately separate from
        /// `number`, because for most of the corpus they differ.
        let position: Int
        /// Half-open range of block indices this section owns, header first.
        let range: Range<Int>

        var id: String { anchorID }
        var anchorID: String { NotesOutline.anchorID(number: number, title: title) }
        var letter: String { losLetter(for: number).uppercased() }

        /// What collapsing hides: everything under the header, never the
        /// header itself — the header carries the scroll anchor, so hiding it
        /// would make the rail unable to jump to a collapsed section.
        var bodyRange: Range<Int> { (range.lowerBound + 1)..<range.upperBound }
    }

    /// Blocks before the first heading. This is NOT just the orientation
    /// paragraph: `principles_of_asset_allocation` carries roughly forty
    /// blocks of real LOS material up here, because its first heading reads
    /// "LOS 1 & 2 — …" and the parser's grammar does not recognise that form.
    /// The preamble is therefore never collapsible and never counted.
    let preamble: Range<Int>
    let sections: [Section]

    var count: Int { sections.count }

    /// Nine ethics readings have no LOS headings at all, so they get no rail
    /// and no sticky header — the chrome must vanish rather than render empty.
    var showsRail: Bool { sections.count > 1 }
    var showsStickyHeader: Bool { !sections.isEmpty }

    static func build(from blocks: [NotesBlock]) -> NotesOutline {
        var starts: [(index: Int, number: Int, title: String)] = []
        for (index, block) in blocks.enumerated() {
            if let heading = block.losSectionHeading {
                starts.append((index, heading.number, heading.title))
            }
        }

        guard let first = starts.first else {
            return NotesOutline(preamble: blocks.indices.startIndex..<blocks.count, sections: [])
        }

        var sections: [Section] = []
        for (offset, start) in starts.enumerated() {
            let end = offset + 1 < starts.count ? starts[offset + 1].index : blocks.count
            sections.append(
                Section(
                    number: start.number,
                    title: start.title,
                    position: offset + 1,
                    range: start.index..<end
                )
            )
        }
        return NotesOutline(preamble: 0..<first.index, sections: sections)
    }

    /// THE definition of a notes scroll anchor, in one place.
    ///
    /// The number stays in the string on purpose: two sections in
    /// `capital_market_expectations_part_2` share their first 24 title
    /// characters, so a title-only anchor would make them the same place and
    /// the jump bar would land on the wrong one.
    static func anchorID(number: Int, title: String) -> String {
        "los-\(number)-\(title.prefix(24))"
    }

    /// nil-safe on purpose. The scroll tracker reports nil while the reader is
    /// still in the preamble, and for the nine readings with no sections at
    /// all — `sections[index]` would trap on both.
    func section(at index: Int?) -> Section? {
        guard let index, sections.indices.contains(index) else { return nil }
        return sections[index]
    }

    func index(ofAnchor anchorID: String) -> Int? {
        sections.firstIndex { $0.anchorID == anchorID }
    }

    /// "2 of 7". nil when there is nothing worth counting.
    func counterText(at index: Int) -> String? {
        guard sections.indices.contains(index), sections.count > 1 else { return nil }
        return "\(sections[index].position) of \(sections.count)"
    }

    /// Which section owns a block, or nil if the block is in the preamble.
    func sectionIndex(forBlockAt blockIndex: Int) -> Int? {
        sections.firstIndex { $0.range.contains(blockIndex) }
    }
}

extension NotesBlock {
    /// The one place that answers "does this block begin a LOS section?".
    ///
    /// 25 combined headings across the corpus — "LOS 3 & 4 — …", "LOS 1b — …",
    /// "LOS 9–12 — …" — do NOT match the parser's grammar today and so are not
    /// sections. Widening that grammar is a parser change; it belongs here and
    /// nowhere else, so the outline never has to guess.
    var losSectionHeading: (number: Int, title: String)? {
        if case .losSection(let number, let title) = self { return (number, title) }
        return nil
    }
}

/// One reading's notes parsed ONCE: the blocks the page renders, and the
/// outline that navigates them, built from that same array.
///
/// `ReadingNotesView.blocks` was a computed property that re-ran
/// `NotesContentParser.parse` on every access — three times per body pass. On
/// a page with no scroll-driven state that cost nothing, because nothing
/// invalidated the view. Sticky-header tracking invalidates it on every scroll
/// tick, which would re-parse the whole reading per frame. Parse once.
struct NotesPage: Equatable {
    let blocks: [NotesBlock]
    let outline: NotesOutline

    init(_ notes: ReadingNotesEntry) {
        var parsed = NotesContentParser.parse(notes.content)
        if !notes.orientation.isEmpty {
            parsed.insert(.paragraph(notes.orientation), at: 0)
        }
        // Outline AFTER the insert, so every range indexes the array that is
        // actually rendered. Building it first would shift every index by one.
        self.blocks = parsed
        self.outline = NotesOutline.build(from: parsed)
    }
}

/// Which LOS sections are collapsed, keyed by scroll anchor.
///
/// Keyed by anchor rather than by position because SwiftUI reuses `@State`
/// across pushes of the same view type: an index-keyed set would collapse a
/// *different* section in the next reading you opened.
struct NotesSectionExpansion: Equatable {
    private(set) var collapsedAnchors: Set<String>

    init(collapsed: Set<String> = []) {
        self.collapsedAnchors = collapsed
    }

    func isCollapsed(_ section: NotesOutline.Section) -> Bool {
        collapsedAnchors.contains(section.anchorID)
    }

    mutating func toggle(_ section: NotesOutline.Section) {
        if collapsedAnchors.contains(section.anchorID) {
            collapsedAnchors.remove(section.anchorID)
        } else {
            collapsedAnchors.insert(section.anchorID)
        }
    }

    /// Jumping to a collapsed section must open it, or the rail appears to do
    /// nothing: the anchor scrolls into view but there is no body under it.
    mutating func expand(_ section: NotesOutline.Section) {
        collapsedAnchors.remove(section.anchorID)
    }

    mutating func collapseAll(_ outline: NotesOutline) {
        collapsedAnchors = Set(outline.sections.map(\.anchorID))
    }

    mutating func expandAll() {
        collapsedAnchors.removeAll()
    }

    func allCollapsed(_ outline: NotesOutline) -> Bool {
        !outline.sections.isEmpty && outline.sections.allSatisfy(isCollapsed)
    }
}

/// Picks the current section from however many header positions the scroll
/// view has actually measured.
///
/// Kept pure and separate from the view because the interesting cases are all
/// edge cases: a partially-measured map, the preamble, and a final section too
/// short to ever reach the top of the viewport.
enum NotesScrollTracker {

    /// A header counts as reached within 8pt of the top. Not 0: the sticky bar
    /// is a sibling above the scroll view, so a jump lands a header at minY 0
    /// exactly, and a little slack means a future content inset cannot make a
    /// jump fail to register. Shared with the tests so the threshold cannot
    /// drift between them and the view.
    static let headerLine: CGFloat = 8

    /// The header nearest the top without having gone past it.
    ///
    /// `tops` is sparse — only measured headers appear — so this must never
    /// assume index continuity.
    static func currentIndex(
        tops: [Int: CGFloat],
        threshold: CGFloat,
        sectionCount: Int,
        atBottom: Bool = false
    ) -> Int? {
        guard sectionCount > 0 else { return nil }
        let passed = tops
            .filter { $0.value <= threshold }
            .keys
            .filter { (0..<sectionCount).contains($0) }
        // `atBottom` only applies once something has actually been passed.
        // With every section collapsed, a whole reading can be shorter than
        // the viewport — trivially "at the bottom" while you are looking at
        // the top — and without this guard the rail would light its LAST
        // letter there.
        guard let last = passed.max() else { return nil }
        return atBottom ? sectionCount - 1 : last
    }

    /// The bottom clamp is physical: a final section whose body is shorter
    /// than the viewport can never scroll to the top, so it would never become
    /// current and the rail's last letter would never light.
    ///
    /// `tolerance` covers the content stack's own bottom padding plus
    /// rounding. Overscroll drives `contentEnd` further negative, which still
    /// reads as bottom.
    static func isAtBottom(
        contentEnd: CGFloat?,
        viewportHeight: CGFloat?,
        tolerance: CGFloat = 24
    ) -> Bool {
        guard let contentEnd, let viewportHeight, viewportHeight > 0 else { return false }
        return contentEnd <= viewportHeight + tolerance
    }
}
