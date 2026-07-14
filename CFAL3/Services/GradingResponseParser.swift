import Foundation

struct GradingResult: Codable, Equatable {
    let grade: Int
    let verdict: String
    let strengths: [String]
    let gaps: [String]
    let corrections: [String]
    let modelAnswer: String
    let pointsEarned: Int?
    let pointsPossible: Int?

    enum CodingKeys: String, CodingKey {
        case grade, verdict, strengths, gaps, corrections
        case modelAnswer = "model_answer"
        case pointsEarned = "points_earned"
        case pointsPossible = "points_possible"
    }

    /// "5/6 points" when points were graded, nil otherwise.
    var pointsSummary: String? {
        guard let pointsEarned, let pointsPossible, pointsPossible > 0 else { return nil }
        return "\(pointsEarned)/\(pointsPossible) points"
    }

    var feedbackMarkdown: String {
        var parts: [String] = []
        if let pointsSummary {
            parts.append("**\(pointsSummary)** — \(verdict)")
        } else {
            parts.append("**\(verdict)**")
        }
        if !strengths.isEmpty {
            parts.append("**Strengths**\n" + strengths.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !gaps.isEmpty {
            parts.append("**Gaps**\n" + gaps.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !corrections.isEmpty {
            parts.append("**Corrections**\n" + corrections.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !modelAnswer.isEmpty {
            parts.append("**Model answer**\n\(modelAnswer)")
        }
        return parts.joined(separator: "\n\n")
    }
}

enum GradingResponseParser {
    enum ParserError: Error, Equatable {
        case empty
        case invalidJSON
    }

    static func parse(_ raw: String) throws -> GradingResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParserError.empty }

        let candidates = candidateJSONStrings(from: trimmed)
        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let result = try? JSONDecoder().decode(GradingResult.self, from: data) {
                return result
            }
        }
        throw ParserError.invalidJSON
    }

    static func candidateJSONStrings(from raw: String) -> [String] {
        var results: [String] = []
        let stripped = stripCodeFences(raw)
        results.append(stripped)

        if let object = extractFirstJSONObject(from: stripped) {
            results.append(object)
        }
        return Array(Set(results))
    }

    static func stripCodeFences(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value.replacingOccurrences(of: "```json", with: "")
            value = value.replacingOccurrences(of: "```", with: "")
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    static func extractFirstJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        for index in text[start...].indices {
            let char = text[index]
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }
        return nil
    }
}
