import Foundation

struct CaseStudy: Codable, Identifiable, Hashable {
    let id: String
    let topicID: String
    let title: String
    let vignette: String
    let questions: [Question]

    enum CodingKeys: String, CodingKey {
        case id, title, vignette, questions
        case topicID = "topic_id"
    }
}
