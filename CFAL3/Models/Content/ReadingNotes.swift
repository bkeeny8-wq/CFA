import Foundation

struct ReadingNotesEntry: Codable, Identifiable, Hashable {
    let readingID: String
    let readingNumber: Int
    let sourceFile: String
    let topicArea: String
    let title: String
    let orientation: String
    let content: String

    var id: String { readingID }

    enum CodingKeys: String, CodingKey {
        case readingID = "reading_id"
        case readingNumber = "reading_number"
        case sourceFile = "source_file"
        case topicArea = "topic_area"
        case title, orientation, content
    }
}

struct ReadingNotesBundle: Codable {
    let version: Int
    let source: String
    let readings: [ReadingNotesEntry]
}
