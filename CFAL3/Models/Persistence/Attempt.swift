import Foundation
import SwiftData

@Model
final class Attempt {
    @Attribute(.unique) var id: UUID
    var questionId: String
    var caseId: String
    var topicId: String
    var timestamp: Date
    var durationSeconds: Int

    var selectedOption: String?
    var wasCorrect: Bool?

    var essayText: String?
    var grade: Int?
    var claudeFeedback: String?
    var reasoningText: String?

    var quality: Int?
    var pointsEarned: Int?
    var pointsPossible: Int?

    init(
        id: UUID = UUID(),
        questionId: String,
        caseId: String,
        topicId: String,
        timestamp: Date = .now,
        durationSeconds: Int,
        selectedOption: String? = nil,
        wasCorrect: Bool? = nil,
        essayText: String? = nil,
        grade: Int? = nil,
        claudeFeedback: String? = nil,
        reasoningText: String? = nil,
        quality: Int? = nil,
        pointsEarned: Int? = nil,
        pointsPossible: Int? = nil
    ) {
        self.id = id
        self.questionId = questionId
        self.caseId = caseId
        self.topicId = topicId
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.selectedOption = selectedOption
        self.wasCorrect = wasCorrect
        self.essayText = essayText
        self.grade = grade
        self.claudeFeedback = claudeFeedback
        self.reasoningText = reasoningText
        self.quality = quality
        self.pointsEarned = pointsEarned
        self.pointsPossible = pointsPossible
    }
}
