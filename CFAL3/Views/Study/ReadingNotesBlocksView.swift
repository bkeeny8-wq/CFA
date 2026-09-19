import SwiftUI

struct ReadingNotesBlocksView: View {
    let blocks: [NotesBlock]
    /// Which slice to render. nil means the whole array.
    var range: Range<Int>?

    init(blocks: [NotesBlock], range: Range<Int>? = nil) {
        self.blocks = blocks
        self.range = range
    }

    private var indices: Range<Int> {
        let r = range ?? 0..<blocks.count
        return r.clamped(to: 0..<blocks.count)
    }

    var body: some View {
        // A plain VStack, NOT a LazyVStack. Two reasons, both measured.
        //
        // Correctness first: sections render as sibling ForEach bodies, and a
        // lazy container reuses a row whose id it has already materialised. A
        // probe reproduced one LOS's study material appearing UNDER another
        // LOS's heading — silently, with no missing-row symptom. Absolute
        // block indices below make the ids globally unique, which fixes it,
        // but the lazy path also refuses to report offsets for sections it has
        // not laid out, and the rail needs every section's offset.
        //
        // Cost second: the largest reading in the bundle is ~103 blocks
        // (277 source lines is the loose upper bound). Laziness buys nothing
        // at that size.
        VStack(alignment: .leading, spacing: 20) {
            // Keyed by ABSOLUTE index into `blocks`, so two identical blocks
            // in one reading — and the same offset in two different sections —
            // stay distinct.
            ForEach(indices, id: \.self) { index in
                blockView(blocks[index])
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: NotesBlock) -> some View {
        switch block {
        case .losSection(let number, let title):
            // Reached only when a caller renders the whole array without an
            // outline. The sectioned page draws its own headers.
            LOSSectionHeader(number: number, title: title)
                .id(NotesOutline.anchorID(number: number, title: title))
        case .losStatement(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .italic()
                .padding(.leading, 4)
        case .callout(let kind, let text):
            NotesCalloutView(kind: kind, text: text)
        case .subheading(let text):
            Text(text)
                .font(.headline)
                .padding(.top, 4)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        Text(item)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .paragraph(let text):
            Text(text)
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .formulaBlock(let lines):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.subheadline, design: .monospaced))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        case .table(let title, let headers, let rows):
            NotesTableView(title: title, headers: headers, rows: rows)
        }
    }
}

/// The badge + title that opens a LOS section, and the tap target that
/// collapses it.
struct LOSSectionHeader: View {
    let number: Int
    let title: String
    var position: String?
    var isCollapsed: Bool = false
    var onToggle: (() -> Void)?

    private var letter: String { losLetter(for: number).uppercased() }

    var body: some View {
        let row = HStack(alignment: .top, spacing: 12) {
            Text(letter)
                .font(.headline)
                .foregroundStyle(.white)
                // minWidth, not a fixed frame: a hard 32x32 box clipped the
                // label to a sliver at accessibility text sizes, and this is
                // the primary wayfinding on a notes page.
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: 32, minHeight: 32)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let position {
                    Text(position)
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                }
            }

            Spacer(minLength: 8)

            if onToggle != nil {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dust)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .padding(.top, 8)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        // A .clear background contributes no hit region, so the row's gaps
        // would not be tappable without this.
        .contentShape(Rectangle())

        Group {
            if let onToggle {
                Button(action: onToggle) { row }
                    .buttonStyle(.plain)
                    .accessibilityLabel("LOS \(letter), \(title)")
                    .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
                    .accessibilityHint("Double-tap to \(isCollapsed ? "expand" : "collapse") this section")
            } else {
                row.accessibilityElement(children: .combine)
                    .accessibilityLabel("LOS \(letter), \(title)")
            }
        }
    }
}

private struct NotesCalloutView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let kind: NotesCalloutKind
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(accentColor)
                .font(.body)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                Text(text)
                    .font(horizontalSizeClass == .regular ? .callout : .subheadline)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentColor.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(accentColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var accentColor: Color {
        switch kind {
        case .mustDo: return Theme.accent
        case .coreIdea: return .secondary
        case .examFocus: return .green
        case .watchOut: return .orange
        case .drill: return .purple
        }
    }
}

private struct NotesTableView: View {
    let title: String
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            // No-horizontal-scroll policy: the grid renders inline when it
            // fits the pane; otherwise rows REFLOW vertically as stacked
            // cards (pages grow longer, never sideways).
            ViewThatFits(in: .horizontal) {
                inlineGrid
                stackedRows
            }
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Natural-width grid for tables that fit the pane.
    private var inlineGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 90, maxWidth: 260, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.footnote)
                            .frame(minWidth: 90, maxWidth: 260, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
    }

    /// Vertical reflow for tables too wide to fit: one card per row, the
    /// first column as the row title and the remaining columns as
    /// label–value lines.
    private var stackedRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.first ?? "")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(zip(headers.dropFirst(), row.dropFirst())
                        .enumerated()), id: \.offset) { _, pair in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(pair.0)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(pair.1)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if row != rows.last {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
