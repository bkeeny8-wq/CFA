import SwiftUI

struct ReadingNotesBlocksView: View {
    let blocks: [NotesBlock]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: NotesBlock) -> some View {
        switch block {
        case .losSection(let number, let title):
            LOSSectionHeader(number: number, title: title)
                .id("los-\(number)-\(title.prefix(24))")
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

private struct LOSSectionHeader: View {
    let number: Int
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct NotesCalloutView: View {
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
                    .font(.subheadline)
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

            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                            Text(header)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(minWidth: 140, alignment: .leading)
                        }
                    }

                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(.caption)
                                    .frame(minWidth: 140, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
