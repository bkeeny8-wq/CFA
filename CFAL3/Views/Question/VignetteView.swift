import SwiftUI

/// Renders a case vignette from its plain-text structure: paragraphs split on
/// blank lines, "Exhibit N" headers styled as headers, bullet lines as
/// bulleted rows, and pipe-delimited tables as real grids. The previous
/// implementation ran the text through AttributedString(markdown:), which
/// collapses newlines — destroying paragraph breaks and mangling exhibits.
struct VignetteView: View {
    let vignette: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(isExpanded ? "Hide vignette" : "Show vignette") {
                withAnimation { isExpanded.toggle() }
            }
            .font(.subheadline)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    // MARK: - Parsing

    private enum VignetteBlock {
        case paragraph(String)
        case exhibitHeader(String)
        case bullets([String])
        case table(headers: [String], rows: [[String]])
        /// Source-mangled fixed-width tables (words chopped across lines by
        /// the original ingestion). Rendered monospaced until the content is
        /// repaired through the pipeline.
        case preformatted(String)
    }

    private var blocks: [VignetteBlock] {
        let chunks = vignette
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [VignetteBlock] = []
        for chunk in chunks {
            let lines = chunk.components(separatedBy: "\n")

            if isTable(lines) {
                result.append(parseTable(lines))
            } else if isBulletList(lines) {
                result.append(.bullets(lines.map(stripBullet)))
            } else if isExhibitHeader(chunk) {
                result.append(.exhibitHeader(joined(lines)))
            } else {
                result.append(.paragraph(joined(lines)))
            }
        }
        return result
    }

    /// Re-join hard-wrapped source lines into one flowing paragraph.
    private func joined(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

    private func isExhibitHeader(_ chunk: String) -> Bool {
        chunk.count < 120 &&
        chunk.range(of: #"^Exhibit\s+\d+"#, options: .regularExpression) != nil
    }

    private func isBulletList(_ lines: [String]) -> Bool {
        let bulletish = lines.filter {
            $0.range(of: #"^\s*[-*\u2022]\s+"#, options: .regularExpression) != nil
        }
        return !lines.isEmpty && bulletish.count == lines.count
    }

    private func stripBullet(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"^\s*[-*\u2022]\s+"#, with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    private func isTable(_ lines: [String]) -> Bool {
        let piped = lines.filter { $0.contains("|") }
        return piped.count >= 2 && piped.count >= lines.count - 1
    }

    private func parseTable(_ lines: [String]) -> VignetteBlock {
        var rows: [[String]] = []
        for line in lines where line.contains("|") {
            // skip markdown separator rows like |---|---|
            if line.range(of: #"^[\s|:\-]+$"#, options: .regularExpression) != nil {
                continue
            }
            let cells = line
                .trimmingCharacters(in: CharacterSet(charactersIn: "| \t"))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if !cells.isEmpty { rows.append(cells) }
        }
        guard let headers = rows.first else {
            return .paragraph(joined(lines))
        }

        // Degenerate fixed-width chop from the source ingestion: lots of
        // empty/fragment cells. Fall back to a monospaced block that at
        // least preserves the original alignment.
        let cells = rows.flatMap { $0 }
        let fragments = cells.filter { $0.count <= 3 }.count
        if !cells.isEmpty && Double(fragments) / Double(cells.count) > 0.4 {
            return .preformatted(lines.joined(separator: "\n"))
        }

        return .table(headers: headers, rows: Array(rows.dropFirst()))
    }

    // MARK: - Rendering

    @ViewBuilder
    private func blockView(_ block: VignetteBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .exhibitHeader(let text):
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.body)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .preformatted(let text):
            ScrollView(.horizontal, showsIndicators: true) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .padding(12)
            }
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))

        case .table(let headers, let rows):
            ViewThatFits(in: .horizontal) {
                tableGrid(headers: headers, rows: rows)
                ScrollView(.horizontal, showsIndicators: true) {
                    tableGrid(headers: headers, rows: rows)
                }
            }
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func tableGrid(headers: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 72, maxWidth: 280, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.footnote.monospacedDigit())
                            .frame(minWidth: 72, maxWidth: 280, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
    }
}
