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

/// Practice session preferences.
///
/// IMPORTANT: properties must be STORED for @Observable to track them —
/// the previous implementation used computed properties over UserDefaults,
/// which emit no observation events, so every control in the Practice
/// builder (topic sheet checkmarks, pickers, toggle, onChange previews)
/// rendered as dead UI. Stored properties + didSet persistence restores
/// observation while keeping the same UserDefaults keys.
@Observable
final class PracticeBuilderPreference {
    @ObservationIgnored private let defaults: UserDefaults

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
        didSet { defaults.set(typeFilter.rawValue, forKey: Keys.typeFilter) }
    }

    var sourceFilter: QuestionSourceFilter {
        didSet { defaults.set(sourceFilter.rawValue, forKey: Keys.sourceFilter) }
    }

    var count: PracticeCount {
        didSet { defaults.set(count.rawValue, forKey: Keys.count) }
    }

    var selectedTopics: Set<String> {
        didSet { defaults.set(Array(selectedTopics), forKey: Keys.selectedTopics) }
    }

    var selectedReadings: Set<String> {
        didSet { defaults.set(Array(selectedReadings), forKey: Keys.selectedReadings) }
    }

    var selectedLOS: Set<String> {
        didSet { defaults.set(Array(selectedLOS), forKey: Keys.selectedLOS) }
    }

    var weaknessWeighted: Bool {
        didSet { defaults.set(weaknessWeighted, forKey: Keys.weaknessWeighted) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.string(forKey: Keys.typeFilter),
           let value = QuestionTypeFilter(rawValue: raw) {
            typeFilter = value
        } else {
            typeFilter = .mixed
        }

        if let raw = defaults.string(forKey: Keys.sourceFilter),
           let value = QuestionSourceFilter(rawValue: raw) {
            sourceFilter = value
        } else {
            sourceFilter = .both
        }

        let rawCount = defaults.integer(forKey: Keys.count)
        count = PracticeCount(rawValue: rawCount == 0 ? 20 : rawCount) ?? .twenty

        // Persisted topic IDs may predate the six-book restructure; remap
        // legacy IDs so a stale selection can never silently filter every
        // question out of the pool.
        let storedTopics = Set(defaults.stringArray(forKey: Keys.selectedTopics) ?? [])
        selectedTopics = Set(storedTopics.map(ProgressStats.canonicalTopicID))

        selectedReadings = Set(defaults.stringArray(forKey: Keys.selectedReadings) ?? [])
        selectedLOS = Set(defaults.stringArray(forKey: Keys.selectedLOS) ?? [])
        weaknessWeighted = defaults.bool(forKey: Keys.weaknessWeighted)

        // Write the sanitized topic set back so defaults converge.
        if storedTopics != selectedTopics {
            defaults.set(Array(selectedTopics), forKey: Keys.selectedTopics)
        }
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
