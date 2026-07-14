import Foundation
import SwiftData

@Model
final class ReviewCard {
    @Attribute(.unique) var questionId: String
    var caseId: String
    var topicId: String
    var readingIds: [String]
    var losIds: [String]

    var easeFactor: Double
    var interval: Int
    var repetitions: Int
    var dueDate: Date

    var totalAttempts: Int
    var totalCorrect: Int
    var lastAttemptedAt: Date?
    var flaggedForReview: Bool

    init(
        questionId: String,
        caseId: String,
        topicId: String,
        readingIds: [String],
        losIds: [String]
    ) {
        self.questionId = questionId
        self.caseId = caseId
        self.topicId = topicId
        self.readingIds = readingIds
        self.losIds = losIds
        self.easeFactor = 2.5
        self.interval = 0
        self.repetitions = 0
        self.dueDate = .now
        self.totalAttempts = 0
        self.totalCorrect = 0
        self.flaggedForReview = false
    }
}
