import Foundation
import SwiftData

enum LOSStudyState: String, Codable, CaseIterable {
    case notStarted = "not_started"
    case reviewing = "reviewing"
    case mastered = "mastered"

    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .reviewing: return "Reviewing"
        case .mastered: return "Mastered"
        }
    }

    var sortOrder: Int {
        switch self {
        case .notStarted: return 0
        case .reviewing: return 1
        case .mastered: return 2
        }
    }
}

@Model
final class LOSStudyStatus {
    @Attribute(.unique) var losId: String
    var readingId: String
    var areaId: String
    var state: String
    var notes: String
    var updatedAt: Date

    init(
        losId: String,
        readingId: String,
        areaId: String,
        state: LOSStudyState = .notStarted,
        notes: String = "",
        updatedAt: Date = .now
    ) {
        self.losId = losId
        self.readingId = readingId
        self.areaId = areaId
        self.state = state.rawValue
        self.notes = notes
        self.updatedAt = updatedAt
    }

    var studyState: LOSStudyState {
        get { LOSStudyState(rawValue: state) ?? .notStarted }
        set {
            state = newValue.rawValue
            updatedAt = .now
        }
    }
}
