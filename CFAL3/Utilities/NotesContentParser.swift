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

enum NotesBlock: Identifiable, Equatable {
    case losSection(number: Int, title: String)
    case losStatement(String)
    case callout(NotesCalloutKind, String)
    case subheading(String)
    case bulletList([String])
    case paragraph(String)
    case formulaBlock([String])
    case table(title: String, headers: [String], rows: [[String]])

    var id: String {
        switch self {
        case .losSection(let number, let title):
            return "los-\(number)-\(title.prefix(24))"
        case .losStatement(let text):
            return "los-stmt-\(text.prefix(32))"
        case .callout(let kind, let text):
            return "callout-\(kind.rawValue)-\(text.prefix(24))"
        case .subheading(let text):
            return "sub-\(text.prefix(32))"
        case .bulletList(let items):
            return "bullets-\(items.count)-\(items.first?.prefix(16) ?? "")"
        case .paragraph(let text):
            return "para-\(text.prefix(32))"
        case .formulaBlock(let lines):
            return "formula-\(lines.joined().prefix(24))"
        case .table(let title, _, _):
            return "table-\(title.prefix(32))"
        }
    }
}

enum NotesContentParser {
    private static let losHeaderPattern = /^LOS (\d+) — (.+)$/
    private static let tableTitlePattern = /^Table \d+ — (.+)$/

    static func parse(_ content: String, skipHeader: Bool = true) -> [NotesBlock] {
        var lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        if skipHeader {
            if let idx = lines.firstIndex(where: { $0.hasPrefix("LOS 1") }) {
                lines = Array(lines[idx...])
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

    private static func parseTable(lines: [String], start: Int, title: String) -> (NotesBlock?, Int) {
        var index = start
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }

        var cells: [String] = []
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { break }
            if isSpecialLineStart(line) { break }
            cells.append(line)
            index += 1
        }

        guard cells.count >= 4 else {
            return (.subheading("Table — \(title)"), index)
        }

        // Most tables are 3 columns in the source export.
        let columnCount = 3
        let headers = Array(cells.prefix(columnCount))
        let body = Array(cells.dropFirst(columnCount))
        var rows: [[String]] = []
        var rowIndex = 0
        while rowIndex + columnCount <= body.count {
            rows.append(Array(body[rowIndex..<(rowIndex + columnCount)]))
            rowIndex += columnCount
        }

        return (.table(title: title, headers: headers, rows: rows), index)
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
