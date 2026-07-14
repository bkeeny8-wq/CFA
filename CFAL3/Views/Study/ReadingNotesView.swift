import SwiftUI

struct ReadingNotesView: View {
    let notes: ReadingNotesEntry

    private var blocks: [NotesBlock] {
        NotesContentParser.parse(notes.content)
    }

    private var losSections: [(number: Int, title: String)] {
        blocks.compactMap { block in
            if case .losSection(let number, let title) = block {
                return (number, title)
            }
            return nil
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if losSections.count > 1 {
                        losJumpBar(proxy: proxy)
                    }

                    ReadingNotesBlocksView(blocks: blocks)
                }
                .readableContentWidth(LayoutMetrics.readableMaxWidth + 80)
                .padding()
                .textSelection(.enabled)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !notes.topicArea.isEmpty {
                Text(notes.topicArea.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            if !notes.title.isEmpty {
                Text(notes.title)
                    .font(.title2.bold())
            }

            if !notes.orientation.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "signpost.right.fill")
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                    Text(notes.orientation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(12)
                .background(Theme.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Divider()
        }
    }

    private func losJumpBar(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(losSections, id: \.number) { section in
                    Button {
                        withAnimation {
                            proxy.scrollTo(losScrollID(section.number, section.title), anchor: .top)
                        }
                    } label: {
                        Text("LOS \(section.number)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.12))
                            .foregroundStyle(Theme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func losScrollID(_ number: Int, _ title: String) -> String {
        "los-\(number)-\(title.prefix(24))"
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
