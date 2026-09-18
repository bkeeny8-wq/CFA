import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Progress export format and file IO, kept off SettingsView so the backup
/// schema is not trapped inside a settings screen.
enum ProgressBackup {
    static func payload(
        attempts: [Attempt],
        cards: [ReviewCard],
        sessions: [Session],
        losStudyStatuses: [LOSStudyStatus],
        dayCompletions: [DayCompletion],
        flashcardProgress: [FlashcardProgress]
    ) -> ExportPayload {
        ExportPayload(
            exportedAt: .now,
            attempts: attempts.map {
                AttemptExport(
                    id: $0.id,
                    questionId: $0.questionId,
                    caseId: $0.caseId,
                    topicId: $0.topicId,
                    timestamp: $0.timestamp,
                    durationSeconds: $0.durationSeconds,
                    selectedOption: $0.selectedOption,
                    wasCorrect: $0.wasCorrect,
                    essayText: $0.essayText,
                    grade: $0.grade,
                    claudeFeedback: $0.claudeFeedback,
                    reasoningText: $0.reasoningText,
                    quality: $0.quality,
                    pointsEarned: $0.pointsEarned,
                    pointsPossible: $0.pointsPossible
                )
            },
            reviewCards: cards.map {
                ReviewCardExport(
                    questionId: $0.questionId,
                    caseId: $0.caseId,
                    topicId: $0.topicId,
                    readingIds: $0.readingIds,
                    losIds: $0.losIds,
                    easeFactor: $0.easeFactor,
                    interval: $0.interval,
                    repetitions: $0.repetitions,
                    dueDate: $0.dueDate,
                    totalAttempts: $0.totalAttempts,
                    totalCorrect: $0.totalCorrect,
                    lastAttemptedAt: $0.lastAttemptedAt,
                    flaggedForReview: $0.flaggedForReview
                )
            },
            sessions: sessions.map {
                SessionExport(
                    id: $0.id,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    mode: $0.mode,
                    filterDescription: $0.filterDescription,
                    attemptIds: $0.attemptIds
                )
            },
            losStudyStatuses: losStudyStatuses.map {
                LOSStudyStatusExport(
                    losId: $0.losId,
                    readingId: $0.readingId,
                    areaId: $0.areaId,
                    state: $0.state,
                    notes: $0.notes,
                    updatedAt: $0.updatedAt
                )
            },
            dayCompletions: dayCompletions.map {
                DayCompletionExport(dateKey: $0.dateKey,
                                    completedHours: $0.completedHours)
            },
            // Only rated cards: the other seeded rows are scaffolding that
            // the destination device regenerates for itself.
            flashcardProgress: flashcardProgress
                .filter { $0.totalAttempts > 0 }
                .map {
                    FlashcardProgressExport(
                        cardId: $0.cardId,
                        readingId: $0.readingId,
                        areaId: $0.areaId,
                        easeFactor: $0.easeFactor,
                        interval: $0.interval,
                        repetitions: $0.repetitions,
                        dueDate: $0.dueDate,
                        totalAttempts: $0.totalAttempts,
                        totalCorrect: $0.totalCorrect,
                        lastAttemptedAt: $0.lastAttemptedAt,
                        firstAttemptedAt: $0.firstAttemptedAt,
                        flaggedForReview: $0.flaggedForReview
                    )
                }
        )
    }

    static func write(_ payload: ExportPayload) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfal3-export-\(Int(Date().timeIntervalSince1970)).json")
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url)
        return url
    }

    static func decode(from url: URL) throws -> ExportPayload {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ExportPayload.self, from: data)
    }
}

struct ExportPayload: Codable {
    let exportedAt: Date
    let attempts: [AttemptExport]
    let reviewCards: [ReviewCardExport]
    let sessions: [SessionExport]
    let losStudyStatuses: [LOSStudyStatusExport]
    var dayCompletions: [DayCompletionExport]?
    /// Optional so backups written before flashcards existed still decode.
    var flashcardProgress: [FlashcardProgressExport]?
}

struct FlashcardProgressExport: Codable {
    let cardId: String
    let readingId: String?
    let areaId: String?
    let easeFactor: Double
    let interval: Int
    let repetitions: Int
    let dueDate: Date
    let totalAttempts: Int
    let totalCorrect: Int
    let lastAttemptedAt: Date?
    let firstAttemptedAt: Date?
    let flaggedForReview: Bool
}

struct AttemptExport: Codable {
    let id: UUID
    let questionId: String
    let caseId: String
    let topicId: String
    let timestamp: Date
    let durationSeconds: Int
    let selectedOption: String?
    let wasCorrect: Bool?
    let essayText: String?
    let grade: Int?
    let claudeFeedback: String?
    let reasoningText: String?
    let quality: Int?
    let pointsEarned: Int?
    let pointsPossible: Int?
}

struct ReviewCardExport: Codable {
    let questionId: String
    let caseId: String?
    let topicId: String?
    let readingIds: [String]?
    let losIds: [String]?
    let easeFactor: Double
    let interval: Int
    let repetitions: Int
    let dueDate: Date
    let totalAttempts: Int
    let totalCorrect: Int
    let lastAttemptedAt: Date?
    let flaggedForReview: Bool
}

struct SessionExport: Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let mode: String
    let filterDescription: String
    let attemptIds: [UUID]
}

struct DayCompletionExport: Codable {
    var dateKey: String
    var completedHours: Double
}

struct LOSStudyStatusExport: Codable {
    let losId: String
    let readingId: String
    let areaId: String
    let state: String
    let notes: String
    let updatedAt: Date
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let url: URL

    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnknown)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}
