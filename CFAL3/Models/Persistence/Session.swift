import Foundation
import SwiftData

enum SessionMode: String, Codable {
    case reviewDue = "review_due"
    case topicDrill = "topic_drill"
    case losDrill = "los_drill"
    case random
    case weakestTopic = "weakest_topic"
    case flagged = "flagged"
}

@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var mode: String
    var filterDescription: String
    var attemptIds: [UUID]

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        mode: String,
        filterDescription: String,
        attemptIds: [UUID] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.mode = mode
        self.filterDescription = filterDescription
        self.attemptIds = attemptIds
    }
}
