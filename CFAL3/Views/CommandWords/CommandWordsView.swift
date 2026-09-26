import SwiftUI

/// The command-word guide: every verb the outline uses on the left, one word's
/// page on the right.
///
/// Deliberately one word at a time rather than a single long scroll. The
/// screen exists to answer one verb properly before moving on, and a combined
/// scroll of seventeen sections is a document, not a study screen.
struct CommandWordsView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(LeftColumnPreference.self) private var leftColumns
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedWord: String?
    /// Compact width has no room for the list beside the page, so there the
    /// page is pushed instead of sitting alongside.
    @State private var pushedWord: String?

    private var words: [CommandWord] { content.allCommandWords }

    /// The list is only a foldable column at regular width, and only when
    /// there is something to put in it — so the shared control is not offered
    /// for a column that is not on screen.
    private var listIsColumn: Bool {
        horizontalSizeClass == .regular && !words.isEmpty
    }

    var body: some View {
        Group {
            if words.isEmpty {
                unavailable
            } else if listIsColumn {
                splitLayout
            } else {
                stackLayout
            }
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Command words")
        .leftColumnControl(.commandWordList, active: listIsColumn)
        .onAppear {
            if selectedWord == nil { selectedWord = words.first?.word }
        }
    }

    /// The guide is optional content, like the schedule and the card deck: a
    /// build whose bundle failed to decode says so instead of showing a blank
    /// column.
    private var unavailable: some View {
        ContentUnavailableView(
            "Command words unavailable",
            systemImage: "character.book.closed",
            description: Text(
                content.loadError
                    ?? "The bundled command word guide didn’t load, so there is nothing to show yet."
            )
        )
        .foregroundStyle(Theme.dust)
        .accessibilityIdentifier("commandwords.unavailable")
    }

    private var splitLayout: some View {
        HStack(spacing: 0) {
            if !leftColumns.isHidden(.commandWordList) {
                wordList
                    .frame(width: 260)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle()
                    .fill(Theme.pine.opacity(0.1))
                    .frame(width: 1)
                    .ignoresSafeArea()
            }
            page
        }
    }

    private var stackLayout: some View {
        wordList
            .navigationDestination(item: $pushedWord) { word in
                if let entry = content.commandWord(word) {
                    CommandWordDetailView(word: entry, onSelectWord: select)
                        .toolbar(.visible, for: .navigationBar)
                }
            }
    }

    @ViewBuilder
    private var page: some View {
        if let selectedWord, let entry = content.commandWord(selectedWord) {
            CommandWordDetailView(word: entry, onSelectWord: select)
                // Rebuilt from scratch per word rather than diffed into the
                // previous word's page, so a long answer's scroll position
                // does not carry over onto the next word.
                .id(entry.word)
        } else {
            ContentUnavailableView(
                "Choose a command word",
                systemImage: "character.book.closed",
                description: Text("Pick a verb to see what the examiner is asking for and how to shape the answer.")
            )
            .foregroundStyle(Theme.dust)
        }
    }

    private var wordList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Command words")
                    .font(Theme.serif(.largeTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("commandwords.library")
                Text("What each verb is asking for, and how many statements it leads. Busiest first.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dust)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(words) { word in
                        wordRow(word)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(Theme.paper)
    }

    private func wordRow(_ word: CommandWord) -> some View {
        let selected = listIsColumn && selectedWord == word.word

        return Button {
            select(word.word)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.displayWord)
                    .font(Theme.serif(.headline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(CommandWordDisplay.losSubtitle(word))
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Theme.sage : Theme.cardFill)
                    .shadow(color: Color.black.opacity(selected ? 0 : 0.04), radius: 8, y: 3)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityIdentifier("commandwords.word.\(word.word)")
        .accessibilityLabel(word.displayWord)
        // "76 LOS" is spoken as letters, so the count is spelled out here.
        .accessibilityValue(CommandWordDisplay.spokenLOSCount(word))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ word: String) {
        if listIsColumn {
            selectedWord = word
        } else {
            pushedWord = word
        }
    }
}

/// Wording shared by the list and the page, so the count is phrased and spoken
/// the same way in both places.
enum CommandWordDisplay {
    /// Short form for the 260-point column.
    static func losSubtitle(_ word: CommandWord) -> String {
        "\(word.losCount) LOS"
    }

    static func spokenLOSCount(_ word: CommandWord) -> String {
        word.losCount == 1
            ? "1 learning outcome statement"
            : "\(word.losCount) learning outcome statements"
    }

    /// `total` is the size of the outline the counts were derived from, so the
    /// page can say 76 of 247 rather than 76 of nothing in particular.
    static func losHeadline(_ word: CommandWord, total: Int?) -> String {
        guard let total, total > 0 else { return "Leads \(spokenLOSCount(word))" }
        return "Leads \(word.losCount) of the \(total) learning outcome statements"
    }
}
