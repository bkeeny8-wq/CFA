import Foundation

enum NotesCalloutKind: String, CaseIterable {
    case mustDo = "What you must do"
    case coreIdea = "Core idea"
    case examFocus = "Exam focus"
    case watchOut = "Watch out"
    case drill = "Drill"

    var systemImage: String {
        switch self {
        case .mustDo: return "target"
        case .coreIdea: return "lightbulb"
        case .examFocus: return "star.fill"
        case .watchOut: return "exclamationmark.triangle.fill"
        case .drill: return "figure.run"
        }
    }
}

/// The curriculum letters a LOS number maps to.
///
/// The notes export writes "LOS 7 — …", but the curriculum — and every other
/// screen in this app, including the LOS checklist and the essay filter — names
/// that statement "g". The two agree because the export's number is the LOS's
/// **index within its reading**, not its position in the notes: the notes for
/// `overview_of_asset_allocation` cover 1, 2, 5, 6, 7, 8, 9, 10 of that
/// reading's ten LOS, and skip 3 and 4 entirely. Numbering the headings
/// sequentially would have labelled the third heading "3" when it is LOS e.
///
/// Derived arithmetically rather than by indexing `los_master`, because two
/// readings' notes carry a number past the end of their master list
/// (`active_equity_investing_portfolio_construction` has a 9 against 8 LOS,
/// and the endowment case study an 8 against 7). Indexing would render those
/// headings blank; this still labels them, and for the other 34 readings it is
/// the same letter the master list holds.
func losLetter(for number: Int) -> String {
    guard number >= 1, number <= 26 else { return String(number) }
    return String(UnicodeScalar(UInt8(96 + number)))
}

enum NotesBlock: Identifiable, Equatable {
    case losSection(number: Int, title: String)
    case losStatement(String)
    case callout(NotesCalloutKind, String)
    case subheading(String)
    case bulletList([String])
    case paragraph(String)
    case formulaBlock([String])
    case table(title: String, headers: [String], rows: [[String]])

    /// Built from the WHOLE of a block's text, never a prefix.
    ///
    /// These were `text.prefix(32)`, which is not an identity: a reading with
    /// two paragraphs opening "The key point here is that…", or two bullet
    /// lists of the same length starting the same way, produced two blocks
    /// claiming the same id. `ForEach` over colliding ids drops or duplicates
    /// rows and animates the wrong ones.
    ///
    /// Note that this is NOT what the notes list uses for identity — see
    /// `ReadingNotesBlocksView`, which enumerates by position, because two
    /// genuinely identical blocks in one reading would still collide here.
    /// The scroll anchors in that view are a separate, deliberately stable
    /// string that `ReadingNotesView` recomputes to jump to a LOS.
    var id: String {
        switch self {
        case .losSection(let number, let title):
            return "los-\(number)-\(title)"
        case .losStatement(let text):
            return "los-stmt-\(text)"
        case .callout(let kind, let text):
            return "callout-\(kind.rawValue)-\(text)"
        case .subheading(let text):
            return "sub-\(text)"
        case .bulletList(let items):
            return "bullets-\(items.joined(separator: "\u{1F}"))"
        case .paragraph(let text):
            return "para-\(text)"
        case .formulaBlock(let lines):
            return "formula-\(lines.joined(separator: "\u{1F}"))"
        case .table(let title, let headers, let rows):
            return "table-\(title)-\(headers.count)x\(rows.count)"
        }
    }
}

enum NotesContentParser {
    private static let losHeaderPattern = /^LOS (\d+) — (.+)$/
    private static let tableTitlePattern = /^Table \d+ — (.+)$/

    /// A line longer than this is prose, not a table cell.
    ///
    /// Table cells in the notes export are fragments; the paragraphs that
    /// follow a table are sentences. Nothing else separates them — the export
    /// writes one cell per line with no blank line at the end of the table —
    /// so without a cutoff the table kept swallowing the paragraphs after it
    /// and rendering them as extra rows. Calibrated against all 59 bundled
    /// tables: 150 leaves every one of them with at least two whole rows,
    /// where 100 and 120 truncated some genuine long-celled ones.
    private static let maxTableCellLength = 150

    /// How many columns each bundled table has.
    ///
    /// This cannot be derived from the content. The export flattens a table to
    /// one cell per line, which throws the column structure away, and the
    /// parser used to assume every table had three. Half of them do not: of
    /// the 59 bundled tables, 30 are 3-column but 14 are 2-column, 10 are
    /// 4-column, 2 are 5-column and one is 6-column. Assuming three silently
    /// re-flowed the other 29 into the wrong shape — a 4-column table's fourth
    /// header became its first body cell, and every row after it was offset by
    /// one — while presenting the result as authoritative study material.
    ///
    /// Inferring the count was tried and abandoned: scoring candidate strides
    /// on divisibility plus "the first column is consistently shorter" agreed
    /// with the real headers on only 21 of 30 hand-checked tables, and a wrong
    /// inference scrambles a table exactly as badly as the fixed 3 did.
    ///
    /// So the counts are recorded here, read off each table's header row.
    /// Titles are unique across the bundle. A table missing from this map
    /// falls back to three, which is the most common shape — and even then it
    /// can no longer drop cells or swallow the prose after it.
    private static let tableColumnCounts: [String: Int] = [
        "Active Share vs active risk": 3,
        "Alternative categories, their primary role, and behavior": 3,
        "Asset size as a constraint": 3,
        "Asset-class returns by inflation regime (relative to expectations)": 4,
        "Biases in allocation and how to counter them": 3,
        "Capital and risk across life stages": 4,
        "Choosing a strategy by direction and volatility view": 3,
        "Class, mechanism, and best use": 3,
        "Comparing equity-risk mitigators": 3,
        "Credit expectation and action": 2,
        "Credit spread measures": 3,
        "Dominant constraints by type": 3,
        "ERM components: what good looks like vs common weaknesses": 3,
        "Electronic-trading risks and their fixes": 2,
        "Environmental, social, and governance risks": 3,
        "Execution algorithms": 2,
        "Execution cost components": 2,
        "Fixed-income risk measures": 2,
        "Fundamental vs quantitative active management": 3,
        "Heuristic and alternative approaches": 3,
        "Illustrative GIPS composite presentation (extract)": 6,
        "Income sources and cost types": 2,
        "Index-construction methods": 3,
        "Index-weighting schemes and their tilts": 3,
        "Institutional investor profiles": 5,
        "Liability types by certainty": 4,
        "Liability-management strategies at a glance": 4,
        "Liquidity by sub-sector (most to least liquid)": 3,
        "MVO's weaknesses and the standard remedies": 3,
        "Mapping a view to a position": 2,
        "Market structure by asset class": 3,
        "Passive bond-exposure methods": 2,
        "Passive vs factor vs active": 4,
        "Policy mix and the resulting yield curve": 4,
        "Pooled vehicles vs separately managed accounts (SMAs)": 3,
        "Private vs institutional clients": 3,
        "Private-client segments": 2,
        "Returns-based vs holdings-based style analysis": 3,
        "Strategy, view, and key risk": 3,
        "Taxes individuals face": 3,
        "The active strategy families at a glance": 4,
        "The active-management spectrum": 2,
        "The currency-management continuum": 2,
        "The five business-cycle phases": 4,
        "The four construction approaches": 5,
        "The option Greeks": 3,
        "The three approaches compared": 4,
        "The three forecasting approaches at a glance": 3,
        "The three liability-relative approaches": 3,
        "The three primary segmentation approaches": 3,
        "Three attribution approaches": 4,
        "Trade-execution benchmarks": 3,
        "Two forms of TAA": 3,
        "Two ways to classify style": 3,
        "Two ways to frame the opportunity set": 4,
        "Type I and Type II errors (H0: manager has no skill)": 3,
        "Vehicle choice at a glance": 2,
        "Vehicles for index exposure": 2,
        "What sets the optimal corridor width": 3,
    ]

    static func parse(_ content: String, skipHeader: Bool = true) -> [NotesBlock] {
        var lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        if skipHeader {
            if let idx = lines.firstIndex(where: { $0.hasPrefix("LOS 1") }) {
                lines = Array(lines[idx...])
            } else {
                // Nine Ethics readings are organised as numbered sections
                // rather than "LOS N —" headers, so the search above found
                // nothing and the export preamble rendered as content — the
                // line "CFA® Level III — Study Notes" even matched the
                // subheading rule and came out bold. Strip it explicitly.
                lines = Array(lines.drop(while: isExportHeaderLine))
            }
        }

        var blocks: [NotesBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                index += 1
                continue
            }

            if let match = line.firstMatch(of: losHeaderPattern) {
                let number = Int(match.1) ?? 0
                let title = String(match.2)
                blocks.append(.losSection(number: number, title: title))
                index += 1
                continue
            }

            if line.hasPrefix("LOS:") {
                let text = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                blocks.append(.losStatement(text))
                index += 1
                continue
            }

            if let callout = parseCallout(line) {
                blocks.append(callout)
                index += 1
                continue
            }

            if let match = line.firstMatch(of: tableTitlePattern) {
                let title = String(match.1)
                let (tableBlock, nextIndex) = parseTable(lines: lines, start: index + 1, title: title)
                if let tableBlock {
                    blocks.append(tableBlock)
                }
                index = nextIndex
                continue
            }

            if isBulletLine(lines[index]) {
                let (items, nextIndex) = parseBullets(lines: lines, start: index)
                blocks.append(.bulletList(items))
                index = nextIndex
                continue
            }

            if isFormulaLine(line) {
                let (formulas, nextIndex) = parseFormulaBlock(lines: lines, start: index)
                blocks.append(.formulaBlock(formulas))
                index = nextIndex
                continue
            }

            if isSubheading(line, previous: blocks.last, next: nextNonEmpty(lines, from: index + 1)) {
                blocks.append(.subheading(line))
                index += 1
                continue
            }

            let (paragraph, nextIndex) = parseParagraph(lines: lines, start: index)
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
            index = nextIndex
        }

        return blocks
    }

    /// The machine-written preamble every notes export carries. Kept narrow on
    /// purpose: it must not eat the "Orientation." paragraph that follows, or
    /// any real content.
    private static func isExportHeaderLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if trimmed.hasPrefix("Topic Area:") { return true }
        if trimmed.hasPrefix("Reading:") { return true }
        return trimmed.contains("Level III") && trimmed.contains("Study Notes")
    }

    private static func parseCallout(_ line: String) -> NotesBlock? {
        let prefixes: [(NotesCalloutKind, String)] = [
            (.mustDo, "What you must do:"),
            (.coreIdea, "Core idea."),
            (.examFocus, "Exam focus:"),
            (.watchOut, "Watch out:"),
            (.drill, "Drill:"),
        ]

        for (kind, prefix) in prefixes {
            if line.hasPrefix(prefix) {
                let text = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return .callout(kind, text)
            }
        }
        return nil
    }

    private static func parseBullets(lines: [String], start: Int) -> ([String], Int) {
        var items: [String] = []
        var index = start
        while index < lines.count {
            let raw = lines[index]
            if isBulletLine(raw) {
                items.append(cleanBullet(raw))
                index += 1
            } else if raw.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                break
            } else {
                break
            }
        }
        return (items, index)
    }

    private static func isBulletLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("•") || trimmed.hasPrefix("\u{2022}") || line.contains("\t•\t") || line.hasPrefix("\t•")
    }

    private static func cleanBullet(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("•") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static func parseFormulaBlock(lines: [String], start: Int) -> ([String], Int) {
        var formulas: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { break }
            if isFormulaLine(line) || looksLikeFormulaContinuation(line, after: formulas) {
                formulas.append(line)
                index += 1
            } else {
                break
            }
        }
        return (formulas, index)
    }

    private static func isFormulaLine(_ line: String) -> Bool {
        if line.contains("≈") { return true }
        let equalsCount = line.filter { $0 == "=" }.count
        return equalsCount >= 1 && line.contains("  ") && line.count < 120
    }

    private static func looksLikeFormulaContinuation(_ line: String, after previous: [String]) -> Bool {
        guard !previous.isEmpty else { return false }
        return line.contains("=") && line.count < 120 && !line.hasPrefix("LOS")
    }

    /// Reads a table, and — just as importantly — reads only the table.
    ///
    /// The returned index is where the grid ENDS, not where cell collection
    /// stopped. Anything gathered that does not complete a row is handed back
    /// to the main loop to be parsed as ordinary content, because that is what
    /// it invariably is: the start of the paragraph after the table. Both of
    /// the old behaviours here lost material. Trailing cells past the last
    /// whole row were dropped outright — 57 of them across the bundle — and
    /// the paragraphs following a table were absorbed into it, so they
    /// vanished from the prose and reappeared as bogus rows.
    private static func parseTable(lines: [String], start: Int, title: String) -> (NotesBlock?, Int) {
        var index = start
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }
        let firstCell = index

        var cells: [String] = []
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { break }
            if isSpecialLineStart(line) { break }
            if line.count > maxTableCellLength { break }
            cells.append(line)
            index += 1
        }

        let columnCount = tableColumnCounts[title] ?? 3
        let rowCount = cells.count / columnCount

        // One row is a header with nothing under it; show the title and let
        // the lines themselves be parsed as content rather than swallowing
        // them into a table that has no body.
        guard rowCount >= 2 else {
            return (.subheading("Table — \(title)"), firstCell)
        }

        let used = rowCount * columnCount
        let headers = Array(cells.prefix(columnCount))
        var rows: [[String]] = []
        var cursor = columnCount
        while cursor < used {
            rows.append(Array(cells[cursor..<(cursor + columnCount)]))
            cursor += columnCount
        }

        return (.table(title: title, headers: headers, rows: rows), firstCell + used)
    }

    private static func parseParagraph(lines: [String], start: Int) -> (String, Int) {
        var parts: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { break }
            if isSpecialLineStart(line) || isBulletLine(lines[index]) || isFormulaLine(line) {
                break
            }
            parts.append(line)
            index += 1
        }
        return (parts.joined(separator: " "), index)
    }

    private static func isSpecialLineStart(_ line: String) -> Bool {
        if line.firstMatch(of: losHeaderPattern) != nil { return true }
        if line.hasPrefix("LOS:") { return true }
        if parseCallout(line) != nil { return true }
        if line.firstMatch(of: tableTitlePattern) != nil { return true }
        return false
    }

    private static func isSubheading(_ line: String, previous: NotesBlock?, next: String?) -> Bool {
        guard line.count <= 90 else { return false }
        if line.hasSuffix(".") && !line.hasSuffix("...") && line.count > 60 {
            return false
        }

        if isSpecialLineStart(line) { return false }

        let nextIsBullet = next.map { isBulletLine($0) || $0.hasPrefix("•") } ?? false
        let afterLOS = if case .losStatement = previous { true } else { false }
        let afterSection = if case .losSection = previous { true } else { false }

        if line.hasPrefix("Worked example") { return true }
        if line.hasPrefix("Table ") { return false }
        if line.contains(" — ") && line.count < 70 { return true }
        if nextIsBullet && line.count < 70 { return true }
        if afterSection && line.count < 60 && !line.contains(".") { return false } // prefer callout/LOS next
        if afterLOS && line.count < 50 && !line.contains(".") { return true }

        return false
    }

    private static func nextNonEmpty(_ lines: [String], from start: Int) -> String? {
        var index = start
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { return lines[index] }
            index += 1
        }
        return nil
    }
}
