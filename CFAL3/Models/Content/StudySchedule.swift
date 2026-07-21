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

    var id: String { "\(start)-\(label)" }
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
