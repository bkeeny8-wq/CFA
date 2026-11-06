import Foundation

struct StudySchedule: Codable {
    let version: Int
    let source: String?
    let examDate: String
    let totalPlannedHours: Double
    let days: [ScheduleDay]

    enum CodingKeys: String, CodingKey {
        case version, source, days
        case examDate = "exam_date"
        case totalPlannedHours = "total_planned_hours"
    }

    var daysByDate: [String: ScheduleDay] {
        Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
    }

    func day(for date: Date) -> ScheduleDay? {
        daysByDate[Self.dateKey(for: date)]
    }

    func day(forKey key: String) -> ScheduleDay? {
        daysByDate[key]
    }

    static func dateKey(for date: Date) -> String {
        ScheduleDates.dateKey(for: date)
    }

    static func parseDate(_ key: String) -> Date? {
        ScheduleDates.parse(key)
    }
}

struct ScheduleDay: Codable, Identifiable, Hashable {
    let date: String
    let hours: Double
    let note: String?
    let blocks: [ScheduleBlock]

    var id: String { date }

    var isRestDay: Bool {
        hours == 0 && blocks.isEmpty
    }

    var parsedDate: Date? {
        StudySchedule.parseDate(date)
    }
}

struct ScheduleBlock: Codable, Identifiable, Hashable {
    let start: String
    let label: String
    let minutes: Int
    let kind: ScheduleBlockKind
    let book: Int?
    /// When set, Plan can open this block's curriculum reading.
    let readingID: String?
    /// Where to answer this block's questions. Deliberately NOT named `source`:
    /// `StudySchedule.source` above means the workbook this plan was exported
    /// from, and two unrelated meanings for one key fifty lines apart is how a
    /// reader gets it wrong. Nil on blocks that are not question sittings.
    let questionSource: ScheduleBlockSource?
    /// The further readings a bundled block covers. Ethics is ten short
    /// readings against one book's weight, so four November blocks carry two
    /// readings each; without this the plan would claim to cover 32 readings
    /// while the content covers 36.
    let alsoCovers: [String]?

    enum CodingKeys: String, CodingKey {
        case start, label, minutes, kind, book
        case readingID = "reading_id"
        case questionSource = "question_source"
        case alsoCovers = "also_covers"
    }

    /// Unique only WITHIN a day. 42 of the plan's 203 distinct values repeat
    /// across days (one on six separate days), so this is safe for a ForEach
    /// inside one day's inspector and wrong for anything persisted. Storage
    /// keys on `resultKey(on:)`.
    var id: String { "\(start)-\(label)" }

    /// The stable identity for a recorded result: unique across the whole plan
    /// (verified: no day repeats a start time), and unlike `id` it survives a
    /// copy-edit to the label without orphaning the row.
    func resultKey(on dateKey: String) -> String { "\(dateKey)|\(start)" }

    /// Every reading this block covers, primary first.
    var readingIDs: [String] {
        (readingID.map { [$0] } ?? []) + (alsoCovers ?? [])
    }
}

/// Which question bank a block's sitting comes from. Only blocks from
/// 6 November 2026 carry this; everything earlier predates the distinction and
/// decodes to nil, which must render as no badge rather than as `app`.
enum ScheduleBlockSource: String, Codable {
    case app
    case mm
    /// CFA Institute's own online question bank, 1,126 questions. Added when
    /// the plan was rebuilt around all three banks rather than two.
    case cfai
    case other

    /// Matches ScheduleBlockKind below. Without it one typo in one of 300
    /// blocks throws, ContentLoader's `try?` swallows it, and the whole
    /// schedule silently becomes nil: Plan shows "No study schedule" and
    /// Today's plan card disappears with no error logged anywhere.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ScheduleBlockSource(rawValue: raw) ?? .other
    }

    var isMeldrum: Bool { self == .mm }

    /// Whether this app can actually start the questions. False for Meldrum
    /// and for CFA Institute's own bank: offering in-app drills there sends
    /// you somewhere the plan did not ask you to go, and the resulting
    /// attempts would land against a sitting you never sat here.
    var isAnsweredInThisApp: Bool { self == .app }
}

enum ScheduleBlockKind: String, Codable {
    case deep3
    case video
    case questions
    case review
    case mock
    case study
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ScheduleBlockKind(rawValue: raw) ?? .other
    }
}

enum ScheduleDates {
    static func dateKey(for date: Date) -> String {
        dateKeyFormatter.string(from: date)
    }

    static func parse(_ key: String) -> Date? {
        dateKeyFormatter.date(from: key)
    }

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum ScheduleProgress {
    static func plannedToDate(schedule: StudySchedule, now: Date = .now) -> Double {
        let today = Calendar.current.startOfDay(for: now)
        return schedule.days.reduce(0) { partial, day in
            guard let date = day.parsedDate, date <= today else { return partial }
            return partial + day.hours
        }
    }

    static func plannedThroughYesterday(schedule: StudySchedule, now: Date = .now) -> Double {
        let today = Calendar.current.startOfDay(for: now)
        return schedule.days.reduce(0) { partial, day in
            guard let date = day.parsedDate, date < today else { return partial }
            return partial + day.hours
        }
    }

    static func completedHours(completions: [DayCompletion]) -> Double {
        completions.reduce(0) { $0 + $1.completedHours }
    }

    static func delta(
        schedule: StudySchedule,
        completions: [DayCompletion],
        now: Date = .now
    ) -> Double {
        completedHours(completions: completions) - plannedThroughYesterday(schedule: schedule, now: now)
    }

    static func weekSections(for days: [ScheduleDay]) -> [(title: String, days: [ScheduleDay])] {
        let grouped = Dictionary(grouping: days) { day -> Date in
            guard let date = day.parsedDate else { return .distantPast }
            return Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        }
        return grouped.keys.sorted().map { weekStart in
            let title = "Week of \(weekTitleFormatter.string(from: weekStart))"
            let weekDays = grouped[weekStart]?.sorted { $0.date < $1.date } ?? []
            return (title, weekDays)
        }
    }

    private static let weekTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
