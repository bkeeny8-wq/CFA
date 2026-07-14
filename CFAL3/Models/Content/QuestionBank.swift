import Foundation

struct QuestionBank: Codable {
    let topics: [BankTopic]

    var totalQuestions: Int {
        topics.reduce(0) { $0 + $1.questionCount }
    }
}
