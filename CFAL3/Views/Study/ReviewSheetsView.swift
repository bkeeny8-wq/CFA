import SwiftUI

/// The combined study-notes DOCX, as its own section.
///
/// This is deliberately a second copy of material the Notes section already
/// carries — `reading_notes.json` was built from the per-reading files in the
/// same folder as this document's source, and Notes covers 36 readings to this
/// document's 25. It is here because it is a different cut of the same
/// content: one continuous review sheet per reading, formula boxes and
/// self-tests included, rather than a planner you navigate LOS by LOS.
///
/// Because they are separate copies, they will drift if the source documents
/// are ever regenerated apart from each other. That is the accepted cost.
struct ReviewSheetsView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var expanded: Set<String> = []
    @State private var query = ""

    private var sheets: [ReviewSheet] { content.reviewSheets }

    private var filtered: [ReviewSheet] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sheets }
        return sheets.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        Group {
            if sheets.isEmpty {
                ContentUnavailableView(
                    "No review sheets in this copy",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("review_sheets.json didn't ship with this build.")
                )
            } else {
                list
            }
        }
        .navigationTitle("Review")
        .toolbar(.hidden, for: .navigationBar)
        .background(Theme.paper)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review")
                        .font(Theme.serif(.largeTitle, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Combined study notes — one sheet per reading, formulas and self-tests included.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dust)
                }

                ParchmentGroup(title: "Readings") {
                    ForEach(filtered) { sheet in
                        BookDisclosureSection(
                            title: "R\(sheet.number) · \(sheet.title)",
                            subtitle: summary(sheet),
                            accessibilityID: "review.sheet.\(sheet.id)",
                            isExpanded: $expanded[sheet.id]
                        ) {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(sheet.blocks) { block in
                                    ReviewBlockView(block: block)
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                }

                Label(
                    "\(sheets.count) readings · \(sheets.reduce(0) { $0 + $1.blocks.count }.formatted()) blocks",
                    systemImage: "line.3.horizontal.decrease"
                )
                .font(.caption)
                .foregroundStyle(Theme.dust)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("review.summary")
            }
            .padding(24)
        }
        .searchable(text: $query, prompt: "Find a reading")
        .frame(maxWidth: horizontalSizeClass == .regular ? 760 : .infinity)
        .frame(maxWidth: .infinity)
    }

    private func summary(_ sheet: ReviewSheet) -> String {
        let tables = sheet.blocks.filter { if case .table = $0 { return true }; return false }.count
        let boxes = sheet.blocks.filter { if case .box = $0 { return true }; return false }.count
        var parts: [String] = []
        if tables > 0 { parts.append("\(tables) table\(tables == 1 ? "" : "s")") }
        if boxes > 0 { parts.append("\(boxes) box\(boxes == 1 ? "" : "es")") }
        return parts.isEmpty ? "\(sheet.blocks.count) blocks" : parts.joined(separator: " · ")
    }
}

/// One block. Tables render at their REAL width — the column count came from
/// Word, so nothing here has to infer it.
private struct ReviewBlockView: View {
    let block: ReviewBlock

    var body: some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .padding(.top, 6)

        case .paragraph(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.accent)
                        Text(item)
                            .font(.body)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .box(let lines):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.sage.opacity(0.35))
            )

        case .table(let headers, let rows):
            // Horizontally scrollable: a genuine 8-column table will not fit a
            // 760pt column, and squeezing it makes every cell unreadable.
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    row(headers, isHeader: true)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        Divider()
                        row(r, isHeader: false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.cardFill)
                )
            }
        }
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(isHeader ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(isHeader ? Theme.pine : Theme.ink)
                    .frame(width: 180, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
            }
        }
    }
}
