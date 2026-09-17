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

/// How many questions to draw for EACH book / reading / LOS in scope. The
/// session total scales with how many units are selected — pick "5" with
/// four readings in scope and you get up to 20 questions, four per reading.
enum PracticeCount: Int, CaseIterable, Identifiable, Codable {
    case three = 3
    case five = 5
    case ten = 10
    case fifteen = 15
    case all = -1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .three: return "3"
        case .five: return "5"
        case .ten: return "10"
        case .fifteen: return "15"
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
        static let dailyNewLimit = "review.dailyNewLimit"
        static let dailyNewFlashcardLimit = "review.dailyNewFlashcardLimit"
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

    /// Never-seen questions admitted to a review session per day. Lives here
    /// rather than in @AppStorage because this object is the app's one
    /// preference idiom — see the note above about observation.
    var dailyNewLimit: Int {
        didSet { defaults.set(dailyNewLimit, forKey: Keys.dailyNewLimit) }
    }

    /// Separate from `dailyNewLimit`: cards and questions are separate queues
    /// with separate paces, so one shared number would mean neither.
    var dailyNewFlashcardLimit: Int {
        didSet { defaults.set(dailyNewFlashcardLimit, forKey: Keys.dailyNewFlashcardLimit) }
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

        // Per-unit quota. A stored legacy total (10/20/50/100) that is no
        // longer a valid case falls back to the default rather than crashing.
        let rawCount = defaults.integer(forKey: Keys.count)
        count = PracticeCount(rawValue: rawCount == 0 ? 5 : rawCount) ?? .five

        // Persisted topic IDs may predate the six-book restructure; remap
        // legacy IDs so a stale selection can never silently filter every
        // question out of the pool.
        let storedTopics = Set(defaults.stringArray(forKey: Keys.selectedTopics) ?? [])
        selectedTopics = Set(storedTopics.map(ProgressStats.canonicalTopicID))

        selectedReadings = Set(defaults.stringArray(forKey: Keys.selectedReadings) ?? [])
        selectedLOS = Set(defaults.stringArray(forKey: Keys.selectedLOS) ?? [])
        weaknessWeighted = defaults.bool(forKey: Keys.weaknessWeighted)

        // `integer(forKey:)` returns 0 for a missing key, and 0 is a valid
        // choice here ("Off"), so absence has to be tested separately.
        dailyNewLimit = defaults.object(forKey: Keys.dailyNewLimit) == nil
            ? ReviewQueue.defaultDailyNewLimit
            : defaults.integer(forKey: Keys.dailyNewLimit)

        dailyNewFlashcardLimit = defaults.object(forKey: Keys.dailyNewFlashcardLimit) == nil
            ? FlashcardQueue.defaultDailyNewLimit
            : defaults.integer(forKey: Keys.dailyNewFlashcardLimit)

        // Write the sanitized topic set back so defaults converge.
        if storedTopics != selectedTopics {
            defaults.set(Array(selectedTopics), forKey: Keys.selectedTopics)
        }
    }

    func reset() {
        typeFilter = .mixed
        sourceFilter = .both
        count = .five
        selectedTopics = []
        selectedReadings = []
        selectedLOS = []
        weaknessWeighted = false
    }
}

/// The Practice scope cascade: which readings a book selection allows, which
/// LOS a reading selection allows, and what to drop when the selection above
/// narrows.
///
/// This lived as private methods on `PracticeBuilderView`, which meant the
/// tests covering it could only re-implement the same predicates inline and
/// compare them with themselves — they exercised no production code and could
/// not fail however the real cascade behaved. It is pure and takes the areas
/// explicitly, so it is testable and the view is thinner for it.
enum PracticeScope {
    /// Readings belonging to the selected books; an empty selection means all.
    static func readings(in areas: [CurriculumArea], topics: Set<String>) -> Set<String> {
        var ids = Set<String>()
        for area in areas where topics.isEmpty || topics.contains(area.id) {
            for reading in area.readings { ids.insert(reading.id) }
        }
        return ids
    }

    /// LOS belonging to the selected readings, or — when no reading is picked
    /// — to the selected books.
    static func los(
        in areas: [CurriculumArea],
        readings: Set<String>,
        topics: Set<String>
    ) -> Set<String> {
        var ids = Set<String>()
        for area in areas {
            for reading in area.readings {
                let inScope = readings.isEmpty
                    ? (topics.isEmpty || topics.contains(area.id))
                    : readings.contains(reading.id)
                if inScope { for los in reading.los { ids.insert(los.id) } }
            }
        }
        return ids
    }

    /// The selection that survives after the books change: readings outside
    /// the chosen books go, and then any LOS left without a home.
    static func pruned(
        areas: [CurriculumArea],
        topics: Set<String>,
        readings: Set<String>,
        los selectedLOS: Set<String>
    ) -> (readings: Set<String>, los: Set<String>) {
        var keptReadings = readings
        if !topics.isEmpty {
            keptReadings.formIntersection(self.readings(in: areas, topics: topics))
        }
        guard !keptReadings.isEmpty || !topics.isEmpty else {
            return (keptReadings, selectedLOS)
        }
        let allowedLOS = los(in: areas, readings: keptReadings, topics: topics)
        return (keptReadings, selectedLOS.intersection(allowedLOS))
    }
}
