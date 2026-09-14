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
        // v3 bank: 490 questions (267 MC + 223 essay). If the content pipeline
        // changes these, update the pins deliberately.
        let qs = allQuestions(try loadBank())
        XCTAssertEqual(qs.count, 490)
        XCTAssertEqual(qs.filter { $0.type == .mc }.count, 267)
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

    /// The "Attempted" tile divides distinct attempted questionIds by this
    /// total. Attempts come from the bank AND the drills, so a bank-only
    /// denominator let the fraction exceed 100%. Pin the union.
    func testAttemptedDenominatorSpansBankAndDrills() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")

        XCTAssertEqual(content.totalQuestions, 490)
        XCTAssertEqual(content.totalDrillQuestions, 2_625)
        XCTAssertEqual(
            content.totalBankAndDrillQuestions,
            content.totalQuestions + content.totalDrillQuestions
        )
        XCTAssertEqual(content.totalBankAndDrillQuestions, 3_115)
    }

    /// Every attemptable question is seeded a ReviewCard, so the due-count
    /// universe and the Attempted denominator must be the same set — that
    /// equality is what makes the two numbers legible side by side.
    func testReviewCardUniverseMatchesTheAttemptedDenominator() throws {
        let content = ContentLoader()
        content.load()

        let bankIDs = Set(allQuestions(try loadBank()).map(\.id))
        var drillIDs = Set<String>()
        for bundle in content.losDrillBundles.values {
            for group in bundle.drills {
                for question in group.questions { drillIDs.insert(question.id) }
            }
        }

        XCTAssertTrue(bankIDs.isDisjoint(with: drillIDs), "A drill reuses a bank question ID")
        XCTAssertEqual(bankIDs.union(drillIDs).count, content.totalBankAndDrillQuestions)
    }

    /// Case titles are user-facing. Guard the defects the cleanup removed so a
    /// regenerated bank cannot reintroduce them.
    func testCaseTitlesAreCleanAndUnique() throws {
        let bank = try loadBank()
        let cases = bank.topics.flatMap(\.cases)

        for caseStudy in cases {
            let title = caseStudy.title
            XCTAssertEqual(title, title.trimmingCharacters(in: .whitespaces),
                           "Untrimmed title: \(caseStudy.id)")
            XCTAssertFalse(title.hasSuffix(":"), "Trailing colon: \(caseStudy.id)")
            XCTAssertFalse(title.contains("  "), "Doubled space: \(caseStudy.id)")
            XCTAssertFalse(title.contains(")C"), "Missing space after paren: \(caseStudy.id)")
            XCTAssertEqual(title.filter { $0 == "(" }.count,
                           title.filter { $0 == ")" }.count,
                           "Unbalanced parentheses: \(caseStudy.id)")

            // A parenthetical that merely repeats what precedes it.
            if let open = title.lastIndex(of: "("), title.hasSuffix(")") {
                let inner = String(title[title.index(after: open)..<title.index(before: title.endIndex)])
                let stem = title[..<open].trimmingCharacters(in: .whitespaces)
                XCTAssertNotEqual(inner.lowercased(), stem.lowercased(),
                                  "Title repeats itself: \(caseStudy.id) — \(title)")
            }
        }

        let titles = cases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "Duplicate case titles")
    }
}
