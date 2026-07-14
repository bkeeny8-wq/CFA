import Foundation

enum QuestionType: String, Codable {
    case mc
    case essay
}

struct Question: Codable, Identifiable, Hashable {
    let id: String
    let number: Int
    let stem: String
    let type: QuestionType
    let options: [String: String]?
    let correct: String?
    let rationales: [String: String]?
    let candidateLOS: [String]
    let primaryReadingIDs: [String]
    let dataQuality: String
    let dataQualityFlags: [String]
    let points: Int?

    enum CodingKeys: String, CodingKey {
        case id, number, stem, type, options, correct, rationales, points
        case candidateLOS = "candidate_los"
        case primaryReadingIDs = "primary_reading_ids"
        case dataQuality = "data_quality"
        case dataQualityFlags = "data_quality_flags"
    }

    var isIncomplete: Bool { dataQuality != "complete" }
    var hasNoCorrect: Bool { dataQualityFlags.contains("no_correct") }
    var canGradeMC: Bool { type == .mc && !hasNoCorrect && correct != nil }

    var modelAnswer: String? { rationales?["model_answer"] }

    /// Point value for essay items (real-exam style). Nil for MC or untagged content.
    var pointValue: Int? { type == .essay ? points : nil }

    var sortedOptionKeys: [String] {
        guard let options else { return [] }
        return options.keys.sorted()
    }
}
