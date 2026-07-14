import Foundation

struct BankTopic: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let cases: [CaseStudy]

    var shortName: String { Formatting.shortTopicName(name) }

    var questionCount: Int {
        cases.reduce(0) { $0 + $1.questions.count }
    }
}

struct TopicSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let caseCount: Int
    let questionCount: Int
    let readingIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case caseCount = "case_count"
        case questionCount = "question_count"
        case readingIDs = "reading_ids"
    }

    var shortName: String { Formatting.shortTopicName(name) }
}
