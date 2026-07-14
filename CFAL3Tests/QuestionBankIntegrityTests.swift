import XCTest
@testable import CFAL3

final class QuestionBankIntegrityTests: XCTestCase {
    private func loadBank() throws -> QuestionBank {
        let bundle = Bundle(for: type(of: self))
        // Bank ships in the app bundle, not the test bundle.
        let url = Bundle(identifier: "com.brandonkeeny.CFAL3")?
            .url(forResource: "question_bank", withExtension: "json")
            ?? bundle.url(forResource: "question_bank", withExtension: "json")
        let data = try Data(contentsOf: try XCTUnwrap(url, "question_bank.json not found"))
        return try JSONDecoder().decode(QuestionBank.self, from: data)
    }

    private func allQuestions(_ bank: QuestionBank) -> [Question] {
        bank.topics.flatMap { $0.cases.flatMap(\.questions) }
    }

    func testNoDuplicateQuestionIDs() throws {
        var seen = Set<String>()
        var dupes = [String]()
        for q in allQuestions(try loadBank()) where !seen.insert(q.id).inserted {
            dupes.append(q.id)
        }
        XCTAssertTrue(dupes.isEmpty, "Duplicate question IDs: \(dupes)")
    }

    func testNoEmptyStems() throws {
        for q in allQuestions(try loadBank()) {
            XCTAssertFalse(
                q.stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Empty stem: \(q.id)"
            )
        }
    }

    func testPinnedBankCounts() throws {
        // v3 bank: 491 questions (268 MC + 223 essay). If the content pipeline
        // changes these, update the pins deliberately.
        let qs = allQuestions(try loadBank())
        XCTAssertEqual(qs.count, 491)
        XCTAssertEqual(qs.filter { $0.type == .mc }.count, 268)
        XCTAssertEqual(qs.filter { $0.type == .essay }.count, 223)
    }

    func testEveryGradeableMCHasCorrectInOptions() throws {
        for q in allQuestions(try loadBank()) where q.type == .mc && q.canGradeMC {
            let options = q.options ?? [:]
            XCTAssertNotNil(
                options[q.correct ?? ""],
                "Correct key not present in options: \(q.id)"
            )
        }
    }

    func testUngradeableMCCountMatchesTriage() throws {
        // v3 bank: 29 MCs carry no answer key (28 legacy + inflection q2).
        let count = allQuestions(try loadBank())
            .filter { $0.type == .mc && !$0.canGradeMC }
            .count
        XCTAssertEqual(count, 0,
            "Ungradeable MC count drifted; regenerate triage counts")
    }

    func testEveryEssayHasPointsAndModelAnswer() throws {
        for q in allQuestions(try loadBank()) where q.type == .essay {
            XCTAssertTrue([4, 6, 8].contains(q.points ?? -1), "Bad points: \(q.id)")
            XCTAssertFalse((q.modelAnswer ?? "").isEmpty, "No model answer: \(q.id)")
        }
    }

    func testDrillReadingsMapToTopics() throws {
        // Lightweight pin for drill-aware Progress: every drill reading must
        // resolve to ≥1 topic via QuizAssembler.readingTopicIndex.
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")
        XCTAssertFalse(content.losDrillBundles.isEmpty)

        let index = QuizAssembler.readingTopicIndex(content: content)
        var unmapped = [String]()
        for readingID in content.losDrillBundles.keys {
            if index[readingID]?.isEmpty != false {
                unmapped.append(readingID)
            }
        }
        XCTAssertTrue(unmapped.isEmpty, "Unmapped drill readings: \(unmapped)")
    }
}
