import SwiftUI

/// One symbol for the scroll coordinate space. A second string literal for
/// this name would produce garbage offsets with no compile error.
enum NotesCoordinateSpace {
    static let scroll = "notes.scroll"
}

/// Everything the scroll view reports, in one preference.
///
/// Merged into a single probe so one callback sees every channel at once —
/// otherwise the viewport height, the content end and the header positions
/// arrive in separate passes and the tracker decides from a half-updated
/// picture.
struct NotesScrollProbe: Equatable {
    var sectionTops: [Int: CGFloat] = [:]
    var viewportHeight: CGFloat?
    var contentEnd: CGFloat?
}

struct NotesScrollProbeKey: PreferenceKey {
    static let defaultValue = NotesScrollProbe()

    static func reduce(value: inout NotesScrollProbe, nextValue: () -> NotesScrollProbe) {
        let next = nextValue()
        value.sectionTops.merge(next.sectionTops) { _, new in new }
        value.viewportHeight = next.viewportHeight ?? value.viewportHeight
        value.contentEnd = next.contentEnd ?? value.contentEnd
    }
}

struct ReadingNotesView: View {
    @Environment(LeftColumnPreference.self) private var leftColumns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let notes: ReadingNotesEntry
    var showsTopicArea: Bool = true

    /// Parsed ONCE per reading, not per body pass.
    ///
    /// This was a computed property that re-ran the whole regex parse on every
    /// access, three times per body evaluation. That cost nothing while
    /// nothing invalidated the view — but sticky-header tracking invalidates
    /// it on every scroll tick, and a single swipe produces ~150 preference
    /// callbacks. At ~2ms a parse that is a second of regex per swipe.
    private let page: NotesPage

    @State private var currentIndex: Int?
    @State private var expansion = NotesSectionExpansion()

    init(notes: ReadingNotesEntry, showsTopicArea: Bool = true) {
        self.notes = notes
        self.showsTopicArea = showsTopicArea
        self.page = NotesPageCache.page(for: notes)
    }

    private var outline: NotesOutline { page.outline }

    /// Only on regular width: on a narrow column the rail would eat the
    /// readable text width, and nine Ethics readings have no LOS headings to
    /// put in it.
    private var railApplies: Bool {
        outline.showsRail && horizontalSizeClass == .regular
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                // Outside the ScrollView, so it stays put without any pinning
                // machinery. Unmounted rather than hidden when folded away, so
                // VoiceOver does not keep reading a rail that is not there.
                if railApplies, !leftColumns.isHidden(.notesLOSRail) {
                    LOSLetterRail(
                        outline: outline,
                        currentIndex: currentIndex,
                        expansion: expansion,
                        onJump: { jump(to: $0, proxy: proxy) }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                notesScroll(proxy: proxy)
            }
        }
        .leftColumnControl(.notesLOSRail, active: railApplies)
    }

    private func notesScroll(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // Compact width has no rail, so it keeps a horizontal strip.
                if outline.showsRail, horizontalSizeClass != .regular {
                    compactStrip(proxy: proxy)
                }

                ReadingNotesSectionedBody(
                    page: page,
                    expansion: expansion,
                    onToggle: { toggle($0) }
                )

                // 1pt sentinel: its position in the scroll space is how we
                // know the reader has hit the bottom, which the last section
                // needs because it can be too short to ever reach the top.
                GeometryReader { geo in
                    Color.clear.preference(
                        key: NotesScrollProbeKey.self,
                        value: NotesScrollProbe(
                            contentEnd: geo.frame(in: .named(NotesCoordinateSpace.scroll)).maxY
                        )
                    )
                }
                .frame(height: 1)
            }
            .readableContentWidth(LayoutMetrics.studyReadingMaxWidth)
            .padding()
            .textSelection(.enabled)
        }
        .coordinateSpace(name: NotesCoordinateSpace.scroll)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: NotesScrollProbeKey.self,
                    value: NotesScrollProbe(viewportHeight: geo.size.height)
                )
            }
        )
        .onPreferenceChange(NotesScrollProbeKey.self) { probe in
            // The index is computed HERE and @State is written only when it
            // actually changes. Assigning on every callback would turn ~150
            // measurements per swipe into ~150 body passes.
            let next = NotesScrollTracker.currentIndex(
                tops: probe.sectionTops,
                threshold: NotesScrollTracker.headerLine,
                sectionCount: outline.count,
                atBottom: NotesScrollTracker.isAtBottom(
                    contentEnd: probe.contentEnd,
                    viewportHeight: probe.viewportHeight
                )
            )
            if next != currentIndex { currentIndex = next }
        }
        // safeAreaInset, NOT overlay. `scrollTo(anchor: .top)` lands a header
        // at scroll-view y=0 — directly underneath an overlay bar. An inset
        // moves the content instead, so a jumped-to header stays visible.
        .safeAreaInset(edge: .top, spacing: 0) { stickyBar }
    }

    // MARK: - Sticky bar

    @ViewBuilder
    private var stickyBar: some View {
        if let section = outline.section(at: currentIndex) {
            HStack(spacing: 10) {
                Text(section.letter)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .frame(minWidth: 26, minHeight: 26)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(section.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if let counter = outline.counterText(at: currentIndex ?? 0) {
                    Text(counter)
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.cardFill)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 0.5)
            }
            // NOT animated. This text changes mid-scroll, and a spring on it
            // makes the bar smear while you drag.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Currently reading LOS \(section.letter), \(section.title)")
            .accessibilityIdentifier("notes.stickyheader")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTopicArea, !notes.topicArea.isEmpty {
                Text(notes.topicArea.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            if showsTopicArea {
                Divider()
            }
        }
    }

    private func compactStrip(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(outline.sections.enumerated()), id: \.element.id) { index, section in
                    Button {
                        jump(to: index, proxy: proxy)
                    } label: {
                        Text("LOS \(section.letter)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            // 44pt minimum touch target — these were ~28pt
                            // tall with 8pt gaps, so neighbouring chips were
                            // easy to hit by mistake.
                            .frame(minHeight: 44)
                            .background(index == currentIndex ? Theme.accent : Theme.sage)
                            .foregroundStyle(index == currentIndex ? .white : Theme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to LOS \(section.letter)")
                }
            }
        }
    }

    // MARK: - Actions

    private func jump(to index: Int, proxy: ScrollViewProxy) {
        guard let section = outline.section(at: index) else { return }
        // Expanding first: jumping to a collapsed section otherwise scrolls
        // the anchor into view with nothing under it, which reads as the rail
        // having done nothing.
        expansion.expand(section)
        withSittingAnimation(reduceMotion) {
            proxy.scrollTo(section.anchorID, anchor: .top)
        }
    }

    private func toggle(_ section: NotesOutline.Section) {
        withDisclosureAnimation(reduceMotion) { expansion.toggle(section) }
    }
}

/// The preamble, then each section with a full-bleed rule between them.
private struct ReadingNotesSectionedBody: View {
    let page: NotesPage
    let expansion: NotesSectionExpansion
    let onToggle: (NotesOutline.Section) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !page.outline.preamble.isEmpty {
                ReadingNotesBlocksView(blocks: page.blocks, range: page.outline.preamble)
            }

            ForEach(Array(page.outline.sections.enumerated()), id: \.element.id) { index, section in
                // The rule is what makes a new LOS stop looking like another
                // paragraph: every block on this page is 20pt from the next,
                // so a heading had no more separation than a bullet did.
                // Negative horizontal padding takes it past the text column.
                if index > 0 || !page.outline.preamble.isEmpty {
                    Rectangle()
                        .fill(Theme.ink.opacity(0.14))
                        .frame(height: 0.5)
                        .padding(.horizontal, -16)
                        .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 20) {
                    LOSSectionHeader(
                        number: section.number,
                        title: section.title,
                        position: page.outline.counterText(at: index),
                        isCollapsed: expansion.isCollapsed(section),
                        onToggle: { onToggle(section) }
                    )
                    // The anchor lives on the HEADER, never on the body, so
                    // collapsing a section never removes its anchor and a jump
                    // to a collapsed section still lands.
                    .id(section.anchorID)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: NotesScrollProbeKey.self,
                                value: NotesScrollProbe(
                                    sectionTops: [
                                        index: geo.frame(
                                            in: .named(NotesCoordinateSpace.scroll)
                                        ).minY
                                    ]
                                )
                            )
                        }
                    )

                    if expansion.isCollapsed(section) {
                        Text("\(section.bodyRange.count) blocks hidden")
                            .font(.caption)
                            .foregroundStyle(Theme.dust)
                    } else {
                        ReadingNotesBlocksView(blocks: page.blocks, range: section.bodyRange)
                    }
                }
            }
        }
    }
}

/// Vertical letter rail. Up to 11 sections in the real corpus, so at 44pt each
/// the tallest case is ~484pt — it fits an iPad, but it is scrollable anyway
/// because accessibility text sizes grow the chips.
private struct LOSLetterRail: View {
    let outline: NotesOutline
    let currentIndex: Int?
    let expansion: NotesSectionExpansion
    let onJump: (Int) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(Array(outline.sections.enumerated()), id: \.element.id) { index, section in
                    Button {
                        onJump(index)
                    } label: {
                        Text(section.letter)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(index == currentIndex ? .white : Theme.dust)
                            .frame(minWidth: 32, minHeight: 32)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(index == currentIndex ? Theme.accent : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        expansion.isCollapsed(section)
                                            ? Theme.dust.opacity(0.35) : Color.clear,
                                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                                    )
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("LOS \(section.letter), \(section.title)")
                    .accessibilityHint("Double-tap to jump to this section")
                    .accessibilityAddTraits(index == currentIndex ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 12)
            .padding(.leading, 8)
            .padding(.trailing, 4)
        }
        .frame(width: 52)
        .accessibilityIdentifier("notes.rail")
    }
}

/// Parses each reading once, ever.
///
/// A view struct is recreated constantly, so parsing in `init` — even into
/// `State(initialValue:)` — runs the parse every time. Main-thread only: it is
/// read from view bodies and nothing else.
enum NotesPageCache {
    private static var cache: [String: NotesPage] = [:]

    static func page(for notes: ReadingNotesEntry) -> NotesPage {
        assert(Thread.isMainThread, "NotesPageCache is main-thread only")
        if let hit = cache[notes.readingID] { return hit }
        let built = NotesPage(notes)
        cache[notes.readingID] = built
        return built
    }
}

struct ReadingNotesSection: View {
    let readingID: String
    @Environment(ContentLoader.self) private var content

    var body: some View {
        if let notes = content.readingNotes(id: readingID) {
            NavigationLink {
                ReadingNotesView(notes: notes)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Open study notes", systemImage: "doc.text.fill")
                        .font(.headline)
                    Text("R\(notes.readingNumber) · \(notes.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } else {
            Label("No bundled notes for this reading", systemImage: "doc.text")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}
