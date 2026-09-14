import Foundation

/// What kind of recall a card drills. Drives the badge shown on the card face
/// and lets a session be filtered to, say, formulas only before an exam.
enum FlashcardType: String, Codable, CaseIterable, Identifiable, Hashable {
    case concept
    case formula
    case comparison
    case process
    case pitfall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .concept: return "Concept"
        case .formula: return "Formula"
        case .comparison: return "Compare"
        case .process: return "Process"
        case .pitfall: return "Pitfall"
        }
    }

    var symbolName: String {
        switch self {
        case .concept: return "lightbulb"
        case .formula: return "function"
        case .comparison: return "arrow.left.arrow.right"
        case .process: return "list.number"
        case .pitfall: return "exclamationmark.triangle"
        }
    }
}

enum FlashcardDifficulty: String, Codable, CaseIterable, Hashable {
    case core
    case stretch

    var displayName: String { self == .core ? "Core" : "Stretch" }
}

struct Flashcard: Codable, Identifiable, Hashable {
    let id: String
    let readingID: String
    let areaID: String
    /// The LOS this card serves. Empty when the card spans the whole reading.
    let losID: String
    let type: FlashcardType
    let front: String
    let back: String
    /// Plain-text equation, present on `.formula` cards.
    let formula: String?
    let mnemonic: String?
    let difficulty: FlashcardDifficulty

    enum CodingKeys: String, CodingKey {
        case id, type, front, back, formula, mnemonic, difficulty
        case readingID = "reading_id"
        case areaID = "area_id"
        case losID = "los_id"
    }
}

struct FlashcardBundle: Codable {
    let schemaVersion: Int
    let generatedBy: String?
    let cards: [Flashcard]

    enum CodingKeys: String, CodingKey {
        case cards
        case schemaVersion = "schema_version"
        case generatedBy = "generated_by"
    }
}
