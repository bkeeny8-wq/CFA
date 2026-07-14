import Foundation

enum Formatting {
    static let examDate = Calendar.current.date(from: DateComponents(year: 2027, month: 2, day: 20))!

    static func daysUntilExam(from date: Date = .now) -> Int {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.startOfDay(for: examDate)
        return Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func shortTopicName(_ name: String) -> String {
        if let range = name.range(of: " (", options: .backwards) {
            return String(name[..<range.lowerBound])
        }
        return name
    }

    static func truncatedStem(_ stem: String, limit: Int = 80) -> String {
        let collapsed = stem.replacingOccurrences(of: "\n", with: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func duration(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    static func maskedAPIKey(_ key: String) -> String {
        guard key.count > 12 else { return "••••••••" }
        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}
