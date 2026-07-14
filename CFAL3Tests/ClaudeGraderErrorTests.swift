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
        XCTAssertTrue(ClaudeGraderError.apiError(status: 401, message: nil)
            .errorDescription!.contains("API key"))
        XCTAssertTrue(ClaudeGraderError.apiError(status: 404, message: nil)
            .errorDescription!.contains("model"))
        XCTAssertTrue(ClaudeGraderError.apiError(status: 429, message: nil)
            .errorDescription!.contains("Rate limited"))
        XCTAssertEqual(
            ClaudeGraderError.apiError(status: 418, message: "teapot").errorDescription,
            "teapot")
    }

    func testSelectedModelPersistsAndDefaults() {
        UserDefaults.standard.removeObject(forKey: "graderModel")
        let grader = ClaudeGrader()
        XCTAssertEqual(grader.selectedModel, .opus)
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
