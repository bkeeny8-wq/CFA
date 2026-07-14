import XCTest
@testable import CFAL3

final class GradingResponseParserTests: XCTestCase {
    private let goldenJSON = """
    {
      "grade": 4,
      "verdict": "Strong answer with a minor gap.",
      "strengths": ["Correct core concept"],
      "gaps": ["Missing tax detail"],
      "corrections": ["Clarify IPS constraint"],
      "model_answer": "A concise exemplar."
    }
    """

    func testParsesGoldenJSON() throws {
        let result = try GradingResponseParser.parse(goldenJSON)
        XCTAssertEqual(result.grade, 4)
        XCTAssertEqual(result.verdict, "Strong answer with a minor gap.")
        XCTAssertEqual(result.strengths, ["Correct core concept"])
        XCTAssertEqual(result.modelAnswer, "A concise exemplar.")
    }

    func testParsesJSONWrappedInCodeFences() throws {
        let wrapped = """
        ```json
        \(goldenJSON)
        ```
        """
        let result = try GradingResponseParser.parse(wrapped)
        XCTAssertEqual(result.grade, 4)
    }

    func testThrowsForTruncatedJSON() {
        XCTAssertThrowsError(try GradingResponseParser.parse("{ \"grade\": 3,")) { error in
            XCTAssertEqual(error as? GradingResponseParser.ParserError, .invalidJSON)
        }
    }

    func testThrowsForEmptyInput() {
        XCTAssertThrowsError(try GradingResponseParser.parse("   ")) { error in
            XCTAssertEqual(error as? GradingResponseParser.ParserError, .empty)
        }
    }

    func testParsesPointsBasedJSON() throws {
        let json = """
        {
          "grade": 4,
          "points_earned": 5,
          "points_possible": 6,
          "verdict": "Strong with one gap.",
          "strengths": ["Correct verdict on part ii"],
          "gaps": ["Thin justification on part iii"],
          "corrections": ["Add UIP reasoning for Denmark"],
          "model_answer": "Correct / Incorrect / Correct with brief justifications."
        }
        """
        let result = try GradingResponseParser.parse(json)
        XCTAssertEqual(result.pointsEarned, 5)
        XCTAssertEqual(result.pointsPossible, 6)
        XCTAssertEqual(result.pointsSummary, "5/6 points")
        XCTAssertTrue(result.feedbackMarkdown.contains("5/6 points"))
    }
}
