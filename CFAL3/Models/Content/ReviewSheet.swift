import Foundation

/// One block of a review sheet, as extracted from the combined study-notes
/// DOCX.
///
/// Structured, not flattened to text. The reading-notes pipeline wrote tables
/// out one cell per line, which threw away the column count and left the app
/// guessing it — a guess it got wrong for half of them. Word already knows how
/// many columns a table has, so the extractor keeps that and this type carries
/// it through verbatim.
enum ReviewBlock: Decodable, Hashable, Identifiable {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    /// A one-cell table in the source: a worked example, a formula sheet, a
    /// self-test. 206 of them, and they are the reason this is not just
    /// paragraphs and tables.
    case box([String])
    case table(headers: [String], rows: [[String]])

    private enum CodingKeys: String, CodingKey {
        case kind, text, items, lines, headers, rows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "heading":
            self = .heading(try c.decode(String.self, forKey: .text))
        case "paragraph":
            self = .paragraph(try c.decode(String.self, forKey: .text))
        case "bullets":
            self = .bullets(try c.decode([String].self, forKey: .items))
        case "box":
            self = .box(try c.decode([String].self, forKey: .lines))
        case "table":
            self = .table(
                headers: try c.decode([String].self, forKey: .headers),
                rows: try c.decode([[String]].self, forKey: .rows)
            )
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "unknown review block kind '\(other)'"
            )
        }
    }

    /// Identity by full content, never a prefix. `NotesBlock` used
    /// `text.prefix(32)` and two paragraphs opening the same way claimed one
    /// id, which makes `ForEach` drop rows.
    var id: String {
        switch self {
        case .heading(let t): return "h-\(t)"
        case .paragraph(let t): return "p-\(t)"
        case .bullets(let items): return "b-\(items.joined(separator: "\u{1F}"))"
        case .box(let lines): return "x-\(lines.joined(separator: "\u{1F}"))"
        case .table(let h, let r):
            return "t-\(h.joined(separator: "\u{1F}"))-\(r.count)"
        }
    }
}

struct ReviewSheet: Decodable, Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let blocks: [ReviewBlock]
}

struct ReviewSheetBundle: Decodable {
    let schemaVersion: Int
    let source: String
    let readings: [ReviewSheet]

    enum CodingKeys: String, CodingKey {
        case source, readings
        case schemaVersion = "schema_version"
    }
}
