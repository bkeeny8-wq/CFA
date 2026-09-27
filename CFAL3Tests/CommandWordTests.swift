import XCTest
@testable import CFAL3

/// The command-word section is authored content that points at real LOS and
/// real bank items by id. Nothing in Swift's type system stops a worked
/// example from naming an essay that does not exist, or a "confused with"
/// entry from naming a verb the bundle does not carry — the screen would just
/// render an empty card. These tests are what makes those references load-bearing.
final class CommandWordContentTests: XCTestCase {

    private func loadedContent() throws -> ContentLoader {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")
        return content
    }

    private func words(_ content: ContentLoader) throws -> [CommandWord] {
        let words = content.allCommandWords
        try XCTSkipIf(words.isEmpty, "command_words.json did not load")
        return words
    }

    /// Mutation: drop a word from the JSON — the count fails.
    ///
    /// Deliberately does NOT go through the skipping `words(_:)` helper. Every
    /// other test here skips when the bundle is empty, which is right for them
    /// but would make the whole file pass green if `command_words.json` ever
    /// stopped being bundled. This one test fails instead, so that can't
    /// happen quietly.
    func testTheBundleCarriesEveryCommandWordInTheOutline() throws {
        let content = try loadedContent()
        let words = content.allCommandWords
        XCTAssertFalse(
            words.isEmpty,
            "command_words.json is not in the app bundle — check the Resources build phase"
        )

        XCTAssertEqual(words.count, 17, "the command-word set moved")
        XCTAssertEqual(
            Set(words.map(\.word)).count, words.count,
            "two entries claim the same command word"
        )
        for word in words {
            XCTAssertEqual(word.word, word.word.lowercased(), "\(word.word): stored verbs are lower case")
            XCTAssertNotNil(content.commandWord(word.word.uppercased()),
                            "\(word.word): lookup must be case-insensitive")
        }
    }

    /// Every worked example must name a bank item that exists AND whose type
    /// matches what the JSON claims, because the view hands `id` straight to
    /// the loader and renders whatever comes back.
    ///
    /// Mutation: change one `workedExample.id` by a character — this fails.
    func testEveryWorkedExampleResolvesToARealBankItemOfTheStatedKind() throws {
        let content = try loadedContent()
        var checked = 0

        for word in try words(content) {
            let example = word.workedExample
            let question = content.question(id: example.id)
            XCTAssertNotNil(
                question,
                "\(word.word): worked example '\(example.id)' is not in the bank"
            )
            if let question {
                XCTAssertEqual(
                    question.type, example.kind,
                    "\(word.word): example claims \(example.kind) but the bank says \(question.type)"
                )
            }
            XCTAssertFalse(example.note.isEmpty, "\(word.word): example has no note")
            checked += 1
        }
        XCTAssertEqual(checked, 17)
    }

    /// A confusion entry that names a verb the bundle does not carry renders a
    /// dead cross-link. Mutation: point one at "summarise".
    func testEveryConfusionNamesAnotherWordInTheBundle() throws {
        let content = try loadedContent()
        let words = try words(content)
        let known = Set(words.map(\.word))
        var links = 0

        for word in words {
            XCTAssertFalse(
                word.confusedWith.isEmpty,
                "\(word.word): every verb needs at least one contrast — that is where the answer changes"
            )
            for confusion in word.confusedWith {
                XCTAssertTrue(
                    known.contains(confusion.word),
                    "\(word.word): confused with '\(confusion.word)', which is not in the bundle"
                )
                XCTAssertNotEqual(confusion.word, word.word, "\(word.word) is confused with itself")
                XCTAssertFalse(confusion.difference.isEmpty)
                links += 1
            }
        }
        XCTAssertGreaterThan(links, 17, "the contrasts were thinned out")
    }

    /// The guidance is the whole point of the section. An entry with an empty
    /// `highlight` or `leaveOut` renders a titled card with nothing in it.
    func testEveryWordCarriesActualGuidance() throws {
        for word in try words(try loadedContent()) {
            XCTAssertFalse(word.asking.isEmpty, "\(word.word): no 'what it's asking for'")
            XCTAssertFalse(word.highlight.isEmpty, "\(word.word): nothing to highlight")
            XCTAssertFalse(word.leaveOut.isEmpty, "\(word.word): nothing to leave out")
            XCTAssertFalse(word.pointLosers.isEmpty, "\(word.word): no point-losers")
            XCTAssertFalse(word.shape.length.isEmpty, "\(word.word): no length guidance")
            XCTAssertFalse(word.shape.structure.isEmpty, "\(word.word): no structure guidance")

            for line in word.highlight + word.leaveOut + word.pointLosers {
                XCTAssertFalse(
                    line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(word.word): a blank bullet"
                )
            }
        }
    }

    /// `losCount` is the headline number on every row, and it is derived, not
    /// typed. It must agree with the LOS outline that ships beside it.
    ///
    /// The rule is clause-initial: the verb opens the LOS, or opens a clause
    /// after a comma, semicolon, "and", "or" or "then". Each LOS contributes at
    /// most one to a given verb. That is why the counts SUM ABOVE 247 — eight
    /// of ten `justify` LOS read "recommend and justify", so those statements
    /// are counted by both verbs, correctly.
    ///
    /// Mutation: change any losCount by one — that word fails.
    func testLOSCountsMatchTheOutline() throws {
        let content = try loadedContent()
        let words = try words(content)
        let master = try XCTUnwrap(content.losMaster)
        let statements = master.areas.flatMap(\.readings).flatMap(\.los)
        XCTAssertEqual(statements.count, 247, "the LOS outline moved")

        for word in words {
            let measured = statements.filter { los in
                Self.clauseInitialVerbs(in: los.text).contains(word.word)
            }.count
            XCTAssertEqual(
                measured, word.losCount,
                "\(word.word): JSON says \(word.losCount), the outline says \(measured)"
            )
        }

        XCTAssertGreaterThan(
            words.reduce(0) { $0 + $1.losCount }, statements.count,
            "split-verb LOS mean the counts overlap; a total at or below 247 means the rule changed"
        )
    }

    /// The same clause-initial rule `scripts/derive_command_word_counts.py`
    /// applies, reimplemented here on purpose: if the two ever disagree, one of
    /// them is wrong and this test is how that surfaces.
    private static func clauseInitialVerbs(in text: String) -> Set<String> {
        let breakWords: Set<String> = ["and", "or", "then"]
        var verbs: Set<String> = []
        var expectingClauseStart = true

        let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "," && $0 != ";" })
        for raw in tokens {
            var token = String(raw)
            let endedClause = token.hasSuffix(",") || token.hasSuffix(";")
            token = token.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            guard !token.isEmpty else { continue }

            if expectingClauseStart { verbs.insert(token) }
            expectingClauseStart = endedClause || breakWords.contains(token)
        }
        return verbs
    }

    /// Words with no essay in the bank must SAY so rather than cite an item
    /// that does not use the verb. The section renders a gap notice for these,
    /// and the count is pinned so a later content drop is noticed.
    func testTheEssayGapIsKnownAndDeclared() throws {
        let content = try loadedContent()
        let words = try words(content)

        let withoutEssays = words
            .filter { content.essays(forCommandWord: $0.word).isEmpty }
            .map(\.word)
            .sorted()

        XCTAssertEqual(
            withoutEssays,
            ["contrast", "demonstrate", "distinguish", "formulate", "select"],
            "the set of command words with no practice essay changed"
        )

        // And every other word can actually hand off to practice.
        for word in words where !withoutEssays.contains(word.word) {
            XCTAssertFalse(
                content.essays(forCommandWord: word.word).isEmpty,
                "\(word.word): practice hand-off would open an empty sitting"
            )
        }
    }

    /// The essay index must only return essays, and only ones whose stem
    /// actually uses the verb — otherwise "practice all N essays that use
    /// discuss" is a lie.
    func testTheEssayIndexReturnsOnlyEssaysThatUseTheWord() throws {
        let content = try loadedContent()

        for word in try words(content) {
            let essays = content.essays(forCommandWord: word.word)
            for essay in essays {
                XCTAssertEqual(essay.type, .essay, "\(word.word): a non-essay leaked into the index")
                XCTAssertTrue(
                    essay.stem.lowercased().contains(word.word),
                    "\(word.word): essay \(essay.id) does not use the verb"
                )
            }
            XCTAssertEqual(
                Set(essays.map(\.id)).count, essays.count,
                "\(word.word): the index repeats an essay"
            )
        }
    }
}
