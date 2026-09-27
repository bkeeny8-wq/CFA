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

    /// Five verbs match no essay STEM — the bank commands with eight verbs
    /// and these are not among them. That set is pinned so a later content
    /// drop is noticed rather than quietly closing it.
    func testTheStemGapIsKnownAndDeclared() throws {
        let content = try loadedContent()
        let words = try words(content)

        let withoutStemEssays = words
            .filter { content.essays(forCommandWord: $0.word).isEmpty }
            .map(\.word)
            .sorted()

        XCTAssertEqual(
            withoutStemEssays,
            ["contrast", "demonstrate", "distinguish", "formulate", "select"],
            "the set of command words with no essay stem changed"
        )
    }

    /// ...but every word must still have something to PRACTISE, via the
    /// statements it leads. This is the assertion that makes the second
    /// hand-off load-bearing: without it, five pages offer nothing at all.
    ///
    /// Mutation: have `essays(leadingLOSFor:)` return [] — this fails for
    /// every word, and the five stem-gap words have no practice route left.
    func testEveryWordHasPracticeThroughTheStatementsItLeads() throws {
        let content = try loadedContent()

        for word in try words(content) {
            let essays = content.essays(leadingLOSFor: word.word)
            XCTAssertFalse(
                essays.isEmpty,
                "\(word.word): no essay tests any statement this verb leads"
            )
            for essay in essays {
                XCTAssertEqual(essay.type, .essay, "\(word.word): a non-essay leaked in")
            }
            XCTAssertEqual(
                Set(essays.map(\.id)).count, essays.count,
                "\(word.word): the index repeats an essay"
            )
        }
    }

    /// The LOS route must actually route through the LOS: every essay it
    /// returns has to be tagged to a statement whose clause-initial verbs
    /// include this word. Mutation: index by stem instead — `evaluate` picks
    /// up essays on statements that never say evaluate, and this fails.
    func testTheStatementRouteOnlyReturnsEssaysTaggedToThatVerbsStatements() throws {
        let content = try loadedContent()
        let master = try XCTUnwrap(content.losMaster)
        var verbsByLOS: [String: Set<String>] = [:]
        for los in master.areas.flatMap(\.readings).flatMap(\.los) {
            verbsByLOS[los.id] = ContentLoader.clauseInitialWords(in: los.text)
        }

        for word in try words(content) {
            for essay in content.essays(leadingLOSFor: word.word) {
                let leads = essay.candidateLOS.contains { verbsByLOS[$0]?.contains(word.word) == true }
                XCTAssertTrue(
                    leads,
                    "\(word.word): essay \(essay.id) is not tagged to any statement this verb leads"
                )
            }
        }
    }

    /// The five stem-gap words are exactly the ones this route rescues, and
    /// the counts are pinned because they are the argument for the feature.
    func testTheStatementRouteRescuesTheStemGapWords() throws {
        let content = try loadedContent()
        let rescued = ["contrast": 2, "demonstrate": 14, "distinguish": 3, "formulate": 11, "select": 2]

        for (word, expected) in rescued {
            XCTAssertTrue(
                content.essays(forCommandWord: word).isEmpty,
                "\(word) now matches a stem — update the gap set"
            )
            XCTAssertEqual(
                content.essays(leadingLOSFor: word).count, expected,
                "\(word): statement-route practice count moved"
            )
        }
    }

    /// The two routes are different exercises, not one with a fallback. If
    /// they ever returned the same set for a busy verb, one of them is broken.
    func testTheTwoRoutesAreGenuinelyDifferentSets() throws {
        let content = try loadedContent()
        let byStem = Set(content.essays(forCommandWord: "discuss").map(\.id))
        let byLOS = Set(content.essays(leadingLOSFor: "discuss").map(\.id))

        XCTAssertFalse(byStem.isEmpty)
        XCTAssertFalse(byLOS.isEmpty)
        XCTAssertNotEqual(byStem, byLOS, "the two hand-offs collapsed into one")
        XCTAssertFalse(
            byLOS.subtracting(byStem).isEmpty,
            "the statement route found nothing the stem route missed"
        )
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
