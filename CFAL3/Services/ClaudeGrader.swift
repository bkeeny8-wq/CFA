import Foundation
import Observation

enum GraderModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-4-7"
    case sonnet = "claude-sonnet-5"
    case haiku = "claude-haiku-4-5-20251001"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus: return "Opus 4.7"
        case .sonnet: return "Sonnet 5"
        case .haiku: return "Haiku 4.5"
        }
    }
}

@Observable
final class ClaudeGrader {
    var selectedModel: GraderModel = ClaudeGrader.loadStoredModel() {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "graderModel")
        }
    }

    private static func loadStoredModel() -> GraderModel {
        if let raw = UserDefaults.standard.string(forKey: "graderModel"),
           let model = GraderModel(rawValue: raw) {
            return model
        }
        return .opus
    }

    /// Anthropic error shape: `{"type":"error","error":{"type":"...","message":"..."}}`
    static func parseAPIErrorMessage(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        return message
    }

    private static let systemPrompt = """
    You are an experienced CFA charterholder grading Level III constructed-response
    (essay) answers in the style of the actual CFA Institute exam.

    CRITICAL GRADING PRINCIPLES — read carefully:

    1. CONCISENESS IS REWARDED. Real CFA candidates have ~90 seconds per point of
       credit. Terse, direct answers are the target. A one-sentence answer that hits
       the core point deserves the SAME grade as a three-paragraph answer that says
       the same thing. Do NOT penalize brevity. Do NOT reward padding.

    2. NUMERICAL ITEMS: per CFA Institute policy, a correct numerical value ALONE
       earns full credit on a calculation item — formulas and explanations are not
       required. Shown work matters only for awarding partial credit when the final
       number is wrong.

    3. THE CANONICAL SOLUTION IS A GRADING KEY, NOT A REFERENCE ESSAY. It will
       typically list MULTIPLE ACCEPTED ALTERNATIVES per part (marked with bullets or
       "any ONE" language). A candidate receives full credit for that part if their
       answer matches ANY ONE of the listed alternatives. Do not require them to
       enumerate all alternatives.

    4. VERDICT + JUSTIFICATION structure: many questions ask the candidate to
       determine/circle a verdict AND justify it. Both are usually required for full
       credit on that part. A correct verdict alone typically earns partial credit;
       verdict + one accepted justification earns full credit.

    5. MULTI-PART QUESTIONS: When a question has parts (i, ii, iii), grade
       COMPOSITIONALLY. Divide the available points across the parts evenly unless
       the grading key's partial-credit rubric says otherwise, and award per part.

    6. POINTS-BASED SCORING: The question will state POINTS AVAILABLE (real-exam
       style, typically 4-8). Award points_earned as an integer from 0 to
       points_possible. Then ALSO report a normalized 0-5 grade computed as
       round(5 * points_earned / points_possible). If no point value is provided,
       grade only on the 0-5 scale and omit the points fields.

    7. IGNORE PROSE STYLE. Candidates using fragmented notes, bullet points, or
       abbreviations are fine as long as the substance is correct and unambiguous.
       Do NOT deduct for missing transitions, informal tone, or absence of
       introductory framing.

    8. DO deduct for:
       - Wrong verdicts
       - Missing justifications when the question required one
       - Substantively incorrect reasoning (even if a keyword matches)
       - Answers that pattern-match a rationale without engaging the question
       - Excessive hedging or listing multiple contradictory answers ("kitchen sink")

    Return your grade as a valid JSON object with this exact shape, and NOTHING else:

    {
      "grade": <integer 0-5>,
      "points_earned": <integer, only when points were provided>,
      "points_possible": <integer, only when points were provided>,
      "verdict": "<one-line summary of overall performance>",
      "strengths": ["<terse bullet>", "<terse bullet>"],
      "gaps": ["<terse bullet>", "<terse bullet>"],
      "corrections": ["<terse bullet>", "<terse bullet>"],
      "model_answer": "<a tight 1-3 sentence exemplar in real CFA response style>"
    }

    The model_answer field returned to the candidate should be a TIGHT, EXAM-STYLE
    response — the kind of concise answer that would earn full credit under time
    pressure. Do NOT reproduce the full grading key's list of alternatives.

    Grade rubric (0-5, used directly when no points are provided):
    5 — Full credit: correct verdict(s) on all parts + accepted justification(s).
    4 — Nearly full: correct on all parts, minor gap in one justification.
    3 — Partial: correct direction on majority of parts with meaningful gaps, OR
        correct on all parts but weak reasoning throughout.
    2 — Weak: correct on a minority of parts, or all verdicts correct with no
        reasoning attempted.
    1 — Off-track: shows awareness but doesn't hit the core requirement.
    0 — Wrong / blank / off-topic.

    Do not include prose outside the JSON. Do not wrap the JSON in backticks or code
    fences. Do not exceed the JSON schema shape.
    """

    private static let reasoningSystemPrompt = """
    You are an experienced CFA charterholder evaluating whether a candidate's
    reasoning path is sound for a Level III multiple-choice question.

    Return your grade as a valid JSON object with this exact shape, and NOTHING else:

    {
      "grade": <integer 0-5>,
      "verdict": "<one-line summary>",
      "strengths": ["<bullet 1>", "<bullet 2>"],
      "gaps": ["<bullet 1>", "<bullet 2>"],
      "corrections": ["<bullet 1>", "<bullet 2>"],
      "model_answer": "<a 2-4 sentence exemplar explanation of the correct reasoning>"
    }

    Focus on whether the reasoning would lead to the correct answer and demonstrates
    CFA-level understanding. Reward concise, direct reasoning; do not penalize brevity.

    Do not include prose outside the JSON. Do not wrap the JSON in backticks or code
    fences.
    """

    func gradeEssay(
        vignette: String,
        stem: String,
        essayText: String,
        canonicalAnswer: String?,
        points: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let userMessage = buildUserMessage(
            vignette: vignette,
            stem: stem,
            response: essayText,
            canonicalAnswer: canonicalAnswer,
            points: points
        )
        return streamGrading(system: Self.systemPrompt, userMessage: userMessage)
    }

    func gradeReasoning(
        vignette: String,
        stem: String,
        reasoning: String,
        correctOption: String,
        correctRationale: String
    ) -> AsyncThrowingStream<String, Error> {
        let userMessage = """
        CASE VIGNETTE:
        \(vignette)

        QUESTION:
        \(stem)

        CORRECT ANSWER:
        \(correctOption)

        OFFICIAL RATIONALE:
        \(correctRationale)

        CANDIDATE'S REASONING:
        \(reasoning)

        Grade whether the candidate's reasoning path is sound.
        """
        return streamGrading(system: Self.reasoningSystemPrompt, userMessage: userMessage)
    }

    func collectStream(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var full = ""
        for try await chunk in stream {
            full += chunk
        }
        return full
    }

    private func buildUserMessage(
        vignette: String,
        stem: String,
        response: String,
        canonicalAnswer: String?,
        points: Int?
    ) -> String {
        var message = """
        CASE VIGNETTE:
        \(vignette)

        QUESTION:
        \(stem)

        """
        if let points {
            message += """
            POINTS AVAILABLE: \(points). Award points_earned (0-\(points)) and also
            return the normalized grade = round(5 * points_earned / \(points)).

            """
        }
        if let canonicalAnswer, !canonicalAnswer.isEmpty {
            message += """
            GRADING KEY (for your reference — this lists accepted alternatives; do not
            expect the candidate to enumerate all of them; do not repeat this back
            verbatim in the returned model_answer field):
            \(canonicalAnswer)

            """
        }
        message += """
        CANDIDATE'S RESPONSE:
        \(response)

        Grade this response per your instructions. Reward conciseness. Accept any
        listed alternative for full credit on the corresponding part.
        """
        return message
    }

    /// Transient statuses eligible for a single bounded retry.
    static func isRetryable(status: Int) -> Bool {
        status == 429 || (500...529).contains(status)
    }

    private func streamGrading(system: String, userMessage: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var yieldedAny = false
                    var attempt = 0
                    while true {
                        attempt += 1
                        do {
                            try await self.performStream(
                                system: system,
                                userMessage: userMessage,
                                onText: { text in
                                    yieldedAny = true
                                    continuation.yield(text)
                                }
                            )
                            break
                        } catch let error as ClaudeGraderError {
                            if case .apiError(let status, _) = error,
                               attempt == 1, !yieldedAny,
                               Self.isRetryable(status: status) {
                                try await Task.sleep(nanoseconds: 2_000_000_000)
                                continue
                            }
                            throw error
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performStream(
        system: String,
        userMessage: String,
        onText: (String) -> Void
    ) async throws {
        var request = URLRequest(url: GraderConfig.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(GraderConfig.proxyToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": selectedModel.rawValue,
            "max_tokens": 2000,
            "stream": true,
            "system": system,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 4096 { break }   // error bodies are small; cap defensively
            }
            throw ClaudeGraderError.apiError(
                status: http.statusCode,
                message: Self.parseAPIErrorMessage(body)
            )
        }

        // Anthropic SSE protocol: terminate on message_stop,
        // surface in-stream error events.
        streamLoop: for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            switch type {
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    onText(text)
                }
            case "message_stop":
                break streamLoop
            case "error":
                let message = (json["error"] as? [String: Any])?["message"] as? String
                throw ClaudeGraderError.streamError(message: message ?? "unknown error")
            default:
                continue   // ping, message_start, content_block_start/stop, message_delta
            }
        }
    }
}

enum ClaudeGraderError: LocalizedError {
    case apiError(status: Int, message: String?)
    case streamError(message: String)

    var errorDescription: String? {
        switch self {
        case .apiError(let status, let message):
            switch status {
            case 401:
                return "Grader endpoint rejected the request — check GraderConfig."
            case 404:
                return "Selected model is not available on this account. "
                     + "Choose another model in Settings."
            case 429:
                return "Rate limited by the API. Wait a moment and resubmit."
            case 500...529:
                return "Anthropic servers are busy. Try again shortly."
            default:
                return message ?? "Grading request failed (HTTP \(status))."
            }
        case .streamError(let message):
            return "Grading stream failed: \(message)"
        }
    }
}
