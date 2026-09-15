import XCTest
@testable import CFAL3

final class ClaudeGraderErrorTests: XCTestCase {
    func testParsesAnthropicErrorBody() {
        let body = #"{"type":"error","error":{"type":"authentication_error","#
                 + #""message":"invalid x-api-key"}}"#
        XCTAssertEqual(ClaudeGrader.parseAPIErrorMessage(body), "invalid x-api-key")
    }

    func testUnparseableBodyReturnsNil() {
        XCTAssertNil(ClaudeGrader.parseAPIErrorMessage("<html>502</html>"))
    }

    func testStatusSpecificMessages() {
        XCTAssertTrue(ClaudeGraderError.apiError(status: 404, message: nil)
            .errorDescription!.contains("model"))
        XCTAssertTrue(ClaudeGraderError.apiError(status: 429, message: nil)
            .errorDescription!.contains("Rate limited"))
    }

    /// These strings reach shipped users, so they must say what happened and
    /// what to do — never name a source file, and never consist solely of a
    /// raw API message the user has no way to act on.
    func testMessagesAreUserFacing() {
        for status in [400, 401, 403, 404, 418, 429, 500] {
            let text = ClaudeGraderError
                .apiError(status: status, message: "internal: token_gate_denied")
                .errorDescription ?? ""
            XCTAssertFalse(text.isEmpty, "status \(status)")
            XCTAssertFalse(text.contains("GraderConfig"),
                           "status \(status) names a source file the user cannot open")
            XCTAssertNotEqual(text, "internal: token_gate_denied",
                              "status \(status) is only the raw API message")
        }

        // An unrecognised status still tells the user what to try, and keeps
        // the API's own text as trailing context.
        let fallback = ClaudeGraderError
            .apiError(status: 418, message: "teapot").errorDescription ?? ""
        XCTAssertTrue(fallback.contains("418"))
        XCTAssertTrue(fallback.contains("teapot"))
    }

    func testSelectedModelPersistsAndDefaults() {
        UserDefaults.standard.removeObject(forKey: "graderModel")
        let grader = ClaudeGrader()
        XCTAssertEqual(grader.selectedModel, .fable)
        grader.selectedModel = .haiku
        XCTAssertEqual(UserDefaults.standard.string(forKey: "graderModel"),
                       GraderModel.haiku.rawValue)
        XCTAssertEqual(ClaudeGrader().selectedModel, .haiku)
        UserDefaults.standard.removeObject(forKey: "graderModel")
    }

    func testRetryEligibleStatuses() {
        for s in [429, 500, 529] { XCTAssertTrue(ClaudeGrader.isRetryable(status: s)) }
        for s in [400, 401, 404] { XCTAssertFalse(ClaudeGrader.isRetryable(status: s)) }
    }
}
