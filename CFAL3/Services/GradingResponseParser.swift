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
    let partBreakdown: [String]

    enum CodingKeys: String, CodingKey {
        case grade, verdict, strengths, gaps, corrections
        case modelAnswer = "model_answer"
        case pointsEarned = "points_earned"
        case pointsPossible = "points_possible"
        case partBreakdown = "part_breakdown"
    }

    init(
        grade: Int,
        verdict: String,
        strengths: [String],
        gaps: [String],
        corrections: [String],
        modelAnswer: String,
        pointsEarned: Int?,
        pointsPossible: Int?,
        partBreakdown: [String]
    ) {
        self.grade = grade
        self.verdict = verdict
        self.strengths = strengths
        self.gaps = gaps
        self.corrections = corrections
        self.modelAnswer = modelAnswer
        self.pointsEarned = pointsEarned
        self.pointsPossible = pointsPossible
        self.partBreakdown = partBreakdown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grade = try c.decode(Int.self, forKey: .grade)
        verdict = try c.decode(String.self, forKey: .verdict)
        strengths = try c.decodeIfPresent([String].self, forKey: .strengths) ?? []
        gaps = try c.decodeIfPresent([String].self, forKey: .gaps) ?? []
        corrections = try c.decodeIfPresent([String].self, forKey: .corrections) ?? []
        modelAnswer = try c.decodeIfPresent(String.self, forKey: .modelAnswer) ?? ""
        pointsEarned = try c.decodeIfPresent(Int.self, forKey: .pointsEarned)
        pointsPossible = try c.decodeIfPresent(Int.self, forKey: .pointsPossible)
        partBreakdown = try c.decodeIfPresent([String].self, forKey: .partBreakdown) ?? []
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
        if !partBreakdown.isEmpty {
            parts.append(
                "**Part scores**\n" + partBreakdown.map { "- \($0)" }.joined(separator: "\n")
            )
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
    /// LocalizedError, because these surface directly under the Submit button
    /// in QuestionAttemptView. Without it the user reads
    /// "The operation couldn't be completed. (CFAL3...ParserError error 1.)"
    enum ParserError: LocalizedError, Equatable {
        case empty
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .empty:
                return "The grader returned an empty response. Check your connection and submit again."
            case .invalidJSON:
                return "The grader's response couldn't be read. Submit again, or switch grader model in Settings."
            }
        }
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
