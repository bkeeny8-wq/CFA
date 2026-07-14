import Foundation

struct DrillQuestion: Codable, Identifiable, Hashable {
    let id: String
    let number: Int
    let stem: String
    let type: QuestionType
    let options: [String: String]?
    let correct: String?
    let rationales: [String: String]?
    let primaryLOS: String
    let readingID: String
    let areaID: String
    let difficulty: String?
    let curriculumRef: String?
    let dataQuality: String
    let dataQualityFlags: [String]

    enum CodingKeys: String, CodingKey {
        case id, number, stem, type, options, correct, rationales
        case primaryLOS = "primary_los"
        case readingID = "reading_id"
        case areaID = "area_id"
        case difficulty
        case curriculumRef = "curriculum_ref"
        case dataQuality = "data_quality"
        case dataQualityFlags = "data_quality_flags"
    }

    var asQuestion: Question {
        let payload: [String: Any] = [
            "id": id,
            "number": number,
            "stem": stem,
            "type": type.rawValue,
            "options": options as Any,
            "correct": correct as Any,
            "rationales": rationales as Any,
            "candidate_los": [primaryLOS],
            "primary_reading_ids": [readingID],
            "data_quality": dataQuality,
            "data_quality_flags": dataQualityFlags,
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return try! JSONDecoder().decode(Question.self, from: data)
    }
}

struct LOSDrillGroup: Codable, Identifiable, Hashable {
    let losID: String
    let losLetter: String
    let losText: String
    let readingID: String
    let readingName: String
    let areaID: String
    let questions: [DrillQuestion]

    var id: String { losID }

    enum CodingKeys: String, CodingKey {
        case losID = "los_id"
        case losLetter = "los_letter"
        case losText = "los_text"
        case readingID = "reading_id"
        case readingName = "reading_name"
        case areaID = "area_id"
        case questions
    }
}

struct LOSDrillBundle: Codable {
    let schemaVersion: Int
    let generatedBy: String?
    let curriculumSource: String?
    let drills: [LOSDrillGroup]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedBy = "generated_by"
        case curriculumSource = "curriculum_source"
        case drills
    }

    var readingID: String? { drills.first?.readingID }

    var totalQuestions: Int {
        drills.reduce(0) { $0 + $1.questions.count }
    }
}

struct LOSDrillIndex: Codable {
    let bundles: [LOSDrillIndexEntry]
}

struct LOSDrillIndexEntry: Codable {
    let readingID: String
    let filename: String
    let readingNumber: Int?

    enum CodingKeys: String, CodingKey {
        case readingID = "reading_id"
        case filename
        case readingNumber = "reading_number"
    }
}

enum DrillAttemptContext {
    static func caseId(readingID: String) -> String { "los_drill:\(readingID)" }
}
