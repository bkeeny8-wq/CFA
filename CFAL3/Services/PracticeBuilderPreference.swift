import Foundation
import Observation

enum QuestionTypeFilter: String, CaseIterable, Identifiable, Codable {
    case mixed
    case mcOnly
    case essaysOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mixed: return "Mixed"
        case .mcOnly: return "MC only"
        case .essaysOnly: return "Essays only"
        }
    }

    func allows(_ type: QuestionType) -> Bool {
        switch self {
        case .mixed: return true
        case .mcOnly: return type == .mc
        case .essaysOnly: return type == .essay
        }
    }
}

enum PracticeCount: Int, CaseIterable, Identifiable, Codable {
    case ten = 10
    case twenty = 20
    case fifty = 50
    case hundred = 100
    case all = -1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .ten: return "10"
        case .twenty: return "20"
        case .fifty: return "50"
        case .hundred: return "100"
        case .all: return "All"
        }
    }
}

@Observable
final class PracticeBuilderPreference {
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let typeFilter = "practice.typeFilter"
        static let sourceFilter = "practice.sourceFilter"
        static let count = "practice.count"
        static let selectedTopics = "practice.selectedTopics"
        static let selectedReadings = "practice.selectedReadings"
        static let selectedLOS = "practice.selectedLOS"
        static let weaknessWeighted = "practice.weaknessWeighted"
    }

    var typeFilter: QuestionTypeFilter {
        get {
            guard let raw = defaults.string(forKey: Keys.typeFilter),
                  let value = QuestionTypeFilter(rawValue: raw) else { return .mixed }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.typeFilter) }
    }

    var sourceFilter: QuestionSourceFilter {
        get {
            guard let raw = defaults.string(forKey: Keys.sourceFilter),
                  let value = QuestionSourceFilter(rawValue: raw) else { return .both }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.sourceFilter) }
    }

    var count: PracticeCount {
        get {
            let raw = defaults.integer(forKey: Keys.count)
            return PracticeCount(rawValue: raw == 0 ? 20 : raw) ?? .twenty
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.count) }
    }

    var selectedTopics: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.selectedTopics) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.selectedTopics) }
    }

    var selectedReadings: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.selectedReadings) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.selectedReadings) }
    }

    var selectedLOS: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.selectedLOS) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.selectedLOS) }
    }

    var weaknessWeighted: Bool {
        get { defaults.bool(forKey: Keys.weaknessWeighted) }
        set { defaults.set(newValue, forKey: Keys.weaknessWeighted) }
    }

    func reset() {
        typeFilter = .mixed
        sourceFilter = .both
        count = .twenty
        selectedTopics = []
        selectedReadings = []
        selectedLOS = []
        weaknessWeighted = false
    }
}
