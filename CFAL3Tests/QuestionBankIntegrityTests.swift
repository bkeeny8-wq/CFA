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
        // v3 bank plus original SWF/Endowment cases: 497 (270 MC + 227 essay).
        // If the content pipeline changes these, update the pins deliberately.
        let qs = allQuestions(try loadBank())
        XCTAssertEqual(qs.count, 497)
        XCTAssertEqual(qs.filter { $0.type == .mc }.count, 270)
        XCTAssertEqual(qs.filter { $0.type == .essay }.count, 227)
    }

    /// LOS-scoped essays come from the existing bank. Do not invent items.
    func testLOSScopedEssaysAreBankEssaysAlreadyTagged() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")

        var tagged = Set<String>()
        var total = 0
        for area in content.losMaster?.areas ?? [] {
            for reading in area.readings {
                for los in reading.los {
                    let essays = content.essays(forLOS: los.id)
                    total += essays.count
                    if !essays.isEmpty { tagged.insert(los.id) }
                    for essay in essays {
                        XCTAssertEqual(essay.type, .essay, essay.id)
                        XCTAssertTrue(essay.candidateLOS.contains(los.id), essay.id)
                    }
                }
            }
        }
        XCTAssertEqual(tagged.count, 149)
        XCTAssertGreaterThan(total, 225, "essays can tag more than one LOS")
        XCTAssertEqual(content.essays(forLOS: "no.such.los").count, 0)
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

        XCTAssertEqual(content.totalQuestions, 497)
        XCTAssertEqual(content.totalDrillQuestions, 2_667)
        XCTAssertEqual(
            content.totalBankAndDrillQuestions,
            content.totalQuestions + content.totalDrillQuestions
        )
        XCTAssertEqual(content.totalBankAndDrillQuestions, 3_164)
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

    /// Nine Ethics readings use numbered sections instead of "LOS N —"
    /// headers, so the header-skip found no anchor and the export preamble
    /// rendered as page content.
    func testNotesNeverRenderTheExportPreambleAsContent() throws {
        let content = ContentLoader()
        content.load()
        let master = try XCTUnwrap(content.losMaster)

        var offenders: [String] = []
        for area in master.areas {
            for reading in area.readings {
                guard let entry = content.readingNotes(id: reading.id) else { continue }
                let blocks = NotesContentParser.parse(entry.content)
                let rendered = blocks.compactMap { block -> String? in
                    switch block {
                    case .subheading(let t): return t
                    case .paragraph(let t): return t
                    default: return nil
                    }
                }
                if rendered.contains(where: {
                    $0.contains("Study Notes") || $0.hasPrefix("Topic Area:") || $0.hasPrefix("Reading:")
                }) {
                    offenders.append(reading.id)
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Export preamble leaked into notes: \(offenders)")
    }

    /// Every reading's notes must produce something to read.
    func testEveryReadingsNotesParseToBlocks() throws {
        let content = ContentLoader()
        content.load()
        let master = try XCTUnwrap(content.losMaster)
        for area in master.areas {
            for reading in area.readings {
                guard let entry = content.readingNotes(id: reading.id) else { continue }
                XCTAssertFalse(NotesContentParser.parse(entry.content).isEmpty,
                               "No renderable blocks for \(reading.id)")
            }
        }
    }

    /// A question with no reading is unreachable from any reading-scoped
    /// practice session and invisible to LOS coverage.
    func testEveryQuestionIsTaggedToAReading() throws {
        let untagged = allQuestions(try loadBank())
            .filter { $0.primaryReadingIDs.isEmpty }
            .map(\.id)
        XCTAssertTrue(untagged.isEmpty, "Questions with no reading: \(untagged)")
    }

    /// And that reading must be one the curriculum actually has.
    func testQuestionReadingsResolve() throws {
        let content = ContentLoader()
        content.load()
        let master = try XCTUnwrap(content.losMaster)
        let readingIDs = Set(master.areas.flatMap { $0.readings.map(\.id) })

        var unknown: [String] = []
        for q in allQuestions(try loadBank()) {
            for readingID in q.primaryReadingIDs where !readingIDs.contains(readingID) {
                unknown.append("\(q.id) -> \(readingID)")
            }
        }
        XCTAssertTrue(unknown.isEmpty, "Unknown readings: \(unknown)")
    }

    /// Spray-tagging a question with its reading's entire LOS list made
    /// Practice-by-LOS and coverage credit readings the stem never tested.
    func testCaseQuestionsAreTaggedToAtMostThreeLOS() throws {
        let content = ContentLoader()
        content.load()
        let master = try XCTUnwrap(content.losMaster)
        let known = Set(master.losFlat.map(\.id))

        var empty: [String] = []
        var wide: [String] = []
        var unknown: [String] = []
        for q in allQuestions(try loadBank()) {
            if q.candidateLOS.isEmpty { empty.append(q.id) }
            if q.candidateLOS.count > 3 {
                wide.append("\(q.id) (\(q.candidateLOS.count))")
            }
            for losID in q.candidateLOS where !known.contains(losID) {
                unknown.append("\(q.id) -> \(losID)")
            }
        }
        XCTAssertTrue(empty.isEmpty, "Questions with no LOS: \(empty)")
        XCTAssertTrue(wide.isEmpty, "Questions with more than 3 LOS: \(wide)")
        XCTAssertTrue(unknown.isEmpty, "Unknown LOS ids: \(unknown)")
    }

    /// Practice-by-LOS shows master text and serves that group's drills.
    /// After the spine repair, every drill group must quote the same statement.
    func testDrillLOSTextMatchesMaster() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")
        let master = try XCTUnwrap(content.losMaster)
        let textByID = Dictionary(uniqueKeysWithValues: master.losFlat.map { ($0.id, $0.text) })

        var mismatches: [String] = []
        for bundle in content.losDrillBundles.values {
            for group in bundle.drills {
                guard let masterText = textByID[group.losID] else {
                    mismatches.append("unknown \(group.losID)")
                    continue
                }
                if group.losText != masterText {
                    mismatches.append(group.losID)
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "drill los_text != master: \(mismatches)")
    }

    /// Option length must not predict the answer.
    ///
    /// This test previously asserted `uniqueLongest == 0` AND
    /// `uniqueShortest == 0`, and both passed. Those two conditions cannot
    /// hold together without a third: if the key is never the longest and
    /// never the shortest of three options, it is ALWAYS the middle one. It
    /// was, on 96.4% of drills, and on the 1,586 items whose gaps exceed about
    /// three words "pick the middle option" was correct 1,586 times out of
    /// 1,586. The test was not failing to catch the cue — it was specifying
    /// it, and any correct fix would have been reverted to make CI green.
    ///
    /// Each tail is a cue worth 33 points over chance; squeezing both into the
    /// middle is a cue worth 63. The property actually wanted is that all
    /// three positions are roughly equally likely, so that is what is asserted
    /// now. Bounds are wide enough to permit honest drift and tight enough to
    /// fail both the old state (100% middle) and a naive revert to the
    /// pre-balancing data (76.6% longest).
    func testDrillOptionLengthDoesNotPredictTheAnswer() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")

        var total = 0
        var uniqueLongest = 0
        var uniqueShortest = 0
        var distractorTails = 0
        var boilerplateDistractors = 0
        var boilerplateOnKeys = 0
        var loneLowercaseIsKey = 0
        var loneUppercaseIsKey = 0
        var keys: [String: Int] = [:]
        // The stock sentences the balancing passes appended. Kept separate
        // from `tail` above because that pattern was written alongside the
        // padding and misses the commonest form of it entirely.
        let boilerplate = try NSRegularExpression(
            pattern: #"That specification would be used as-is|That approach would be applied without further adjustment"#,
            options: [.caseInsensitive]
        )
        let tail = try NSRegularExpression(
            pattern: #"(namely\s+.+\bas a complete account of|\bas the .{2,80} reading\.?$|\bas a complete reading of |every implication that reading is usually thought to carry|[—–-]\s*as (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?$|\.\s+As (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?$|,\s+as (?:that|those) [A-Za-z][\w\-]{0,30}(?:\s+[A-Za-z][\w\-]{0,30}){0,4}\.?$)"#,
            options: [.caseInsensitive]
        )
        for bundle in content.losDrillBundles.values {
            for group in bundle.drills {
                for q in group.questions {
                    guard let options = q.options, options.count == 3,
                          let correct = q.correct, let keyText = options[correct]
                    else { continue }
                    total += 1
                    keys[correct, default: 0] += 1

                    // The generator wrote distractors as capitalised standalone
                    // sentences and keys as lowercase continuations of the stem,
                    // so "the option that carries on from the stem" named the
                    // answer on 919 drills. Present in the data from generation
                    // onward — neither balancing pass caused it and neither
                    // earlier audit caught it.
                    let lowerStart = options.filter { $0.value.first?.isLowercase == true }
                    if lowerStart.count == 1, lowerStart.first?.key == correct {
                        loneLowercaseIsKey += 1
                    }
                    // The mirror, which this test did not check until the
                    // rewrite pass produced four of them. Lowercase options
                    // are correct CFA style -- they continue the stem -- so an
                    // option forced into upper case by a leading proper noun
                    // ("Robertson only."), a letter-shape name ("U-shaped.")
                    // or an "About" becomes the odd one out, and on four
                    // drills that odd one was the key. Counting only the
                    // lowercase direction measured half of a symmetric cue.
                    let upperStart = options.filter { $0.value.first?.isUppercase == true }
                    if upperStart.count == 1, upperStart.first?.key == correct {
                        loneUppercaseIsKey += 1
                    }
                    let keyLen = keyText.count
                    let other = options.compactMap { $0.key == correct ? nil : $0.value.count }
                    if let longestOther = other.max(), keyLen > longestOther {
                        uniqueLongest += 1
                    }
                    if let shortestOther = other.min(), keyLen < shortestOther {
                        uniqueShortest += 1
                    }
                    for (letter, text) in options {
                        let range = NSRange(text.startIndex..<text.endIndex, in: text)
                        let padded = boilerplate.firstMatch(in: text, range: range) != nil
                        if letter == correct {
                            if padded { boilerplateOnKeys += 1 }
                            continue
                        }
                        if tail.firstMatch(in: text, range: range) != nil {
                            distractorTails += 1
                        }
                        if padded { boilerplateDistractors += 1 }
                    }
                }
            }
        }
        XCTAssertEqual(total, 2_667)

        let longest = Double(uniqueLongest) / Double(total)
        let shortest = Double(uniqueShortest) / Double(total)
        let middle = 1.0 - longest - shortest
        for (name, share) in [("longest", longest), ("middle", middle), ("shortest", shortest)] {
            XCTAssertGreaterThan(
                share, 0.10,
                "correct option is \(name) on only \(Int(share * 100))% of drills — "
                + "length is predicting the answer again")
            XCTAssertLessThan(
                share, 0.55,
                "correct option is \(name) on \(Int(share * 100))% of drills — "
                + "that is a usable answer key without reading the question")
        }

        // Boilerplate bolted onto a distractor is its own cue: the phrase
        // marks a wrong option every time it appears. The balancing passes
        // added "That specification would be used as-is…" to 1,797
        // distractors, and the regex above — written at the same time — did
        // not match it, so this count read 0 while two thirds of the corpus
        // carried it. Removing the padding took it to 902; rewriting the
        // distractors, which is what it actually needed, took it to 144. The
        // remainder sits on the 377 drills the rewrite pass never reached.
        XCTAssertLessThanOrEqual(
            boilerplateDistractors, 144,
            "machine-written padding on \(boilerplateDistractors) distractors")
        // `tail` matches one legitimately-worded option — "…as that would
        // invade financial privacy" — so this is 1, not 0, and has been since
        // the padding was removed. Kept as a ratchet rather than retuned,
        // because the pattern earns its keep on the forms it does catch.
        XCTAssertLessThanOrEqual(
            distractorTails, 1,
            "grammatical length tails on \(distractorTails) distractors")
        XCTAssertEqual(boilerplateOnKeys, 0, "padding on a correct option marks the answer")

        // Within one item the three options agree on case, so neither case can
        // single the key out. Both directions are zero, not ratchets: nothing
        // about correct content requires the key to be the odd one out, and
        // whichever case an item settles on, the fix is to make all three
        // match it.
        XCTAssertEqual(
            loneLowercaseIsKey, 0,
            "the key is the only lowercase-initial option on \(loneLowercaseIsKey) drills — "
            + "it can be picked out without reading the stem")
        XCTAssertEqual(
            loneUppercaseIsKey, 0,
            "the key is the only uppercase-initial option on \(loneUppercaseIsKey) drills — "
            + "it can be picked out without reading the stem")

        XCTAssertEqual(keys["A"], 889)
        XCTAssertEqual(keys["B"], 889)
        XCTAssertEqual(keys["C"], 889)
    }

    // MARK: - House style

    /// A drill, stripped to what the test needs.
    private struct DrillItem {
        let id: String
        let stem: String
        let options: [String: String]
        let correct: String
    }

    private func drillItems(_ content: ContentLoader) -> [DrillItem] {
        content.losDrillBundles.values.flatMap { bundle in
            bundle.drills.flatMap { group in
                group.questions.compactMap { q -> DrillItem? in
                    guard let options = q.options, options.count == 3,
                          let correct = q.correct, options[correct] != nil
                    else { return nil }
                    return DrillItem(id: q.id, stem: q.stem,
                                     options: options, correct: correct)
                }
            }
        }
    }

    private func matches(_ pattern: String, _ text: String) throws -> Bool {
        let re = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Sentences, counted the way scripts/drill_style_lint.py counts them, so
    /// the two cannot disagree about whether an option runs to two.
    ///
    /// Two details carry the whole rule. A full stop only ends a sentence when
    /// WHITESPACE follows it, or "2.5%" is two sentences. And abbreviations
    /// that do take a following space -- "U.S. Treasuries", "e.g. a swap" --
    /// are masked first. Counting bare "." characters made this read 1,158
    /// against the linter's 1,038.
    private static let abbreviation = try! NSRegularExpression(
        pattern: #"\b(?:[A-Za-z]\.){2,}|\b(?:e\.g|i\.e|vs|No|Mr|Ms|Dr|St|Inc|Co)\."#)
    private static let sentenceBreak = try! NSRegularExpression(pattern: #"[.!?]\s+"#)

    private func sentenceCount(_ text: String) -> Int {
        let masked = Self.abbreviation.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "@")
        let flattened = Self.sentenceBreak.stringByReplacingMatches(
            in: masked, range: NSRange(masked.startIndex..., in: masked), withTemplate: "\u{1}")
        return flattened.components(separatedBy: "\u{1}")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    /// A plain 0-9 digit. `Character.isNumber` also accepts "²" and "½", which
    /// made the mixed-types count read 427 against the linter's 419 -- the
    /// difference being options carrying "18²".
    private func hasDigit(_ text: String) -> Bool {
        text.contains { $0.isASCII && $0.isNumber }
    }

    /// The real test of a question bank is how well you score on it knowing
    /// nothing at all about the curriculum.
    ///
    /// Six strategies have been found in this corpus, each needing no
    /// knowledge whatever, and the counting of them has twice been reported
    /// too kindly because only some of the family was measured. So they are
    /// all scored here, together, and the assertion is on the BEST of them --
    /// closing four cues while a fifth still scores 74% is not progress.
    ///
    /// These are ratchets. They tighten as the corpus is rewritten and they
    /// are never loosened: a number going up means a cue came back.
    func testDrillsCannotBeAnsweredWithoutReadingThem() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")
        let items = drillItems(content)
        XCTAssertEqual(items.count, 2_667)

        let boilerplate = try NSRegularExpression(
            pattern: #"That specification would be used as-is"#
            + #"|That approach would be applied without further adjustment"#,
            options: [.caseInsensitive])
        func isBoilerplate(_ s: String) -> Bool {
            boilerplate.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
        func byLength(_ item: DrillItem, _ pool: [String]) -> String {
            pool.max { item.options[$0]!.count < item.options[$1]!.count } ?? item.correct
        }

        var strategies: [String: (DrillItem) -> String] = [:]
        strategies["take the longest option"] = { byLength($0, Array($0.options.keys)) }
        strategies["take the shortest option"] = { item in
            item.options.keys.min { item.options[$0]!.count < item.options[$1]!.count }!
        }
        strategies["take the middle-length option"] = { item in
            item.options.keys.sorted { item.options[$0]!.count > item.options[$1]!.count }[1]
        }
        strategies["drop the two-sentence option, then longest"] = { item in
            let live = item.options.filter { self.sentenceCount($0.value) == 1 }.map(\.key)
            if live.count == 1 { return live[0] }
            return byLength(item, live.isEmpty ? Array(item.options.keys) : live)
        }
        strategies["drop the boilerplate option, then longest"] = { item in
            let live = item.options.filter { !isBoilerplate($0.value) }.map(\.key)
            if live.count == 1 { return live[0] }
            return byLength(item, live.isEmpty ? Array(item.options.keys) : live)
        }
        strategies["take the odd option out by type"] = { item in
            let numeric = item.options.filter { self.hasDigit($0.value) }.map(\.key)
            if numeric.count == 1 { return numeric[0] }
            let prose = item.options.filter { !self.hasDigit($0.value) }.map(\.key)
            if prose.count == 1 { return prose[0] }
            return byLength(item, Array(item.options.keys))
        }

        var worst = (name: "", score: 0.0)
        for (name, pick) in strategies.sorted(by: { $0.key < $1.key }) {
            let hits = items.filter { pick($0) == $0.correct }.count
            let score = Double(hits) / Double(items.count)
            if score > worst.score { worst = (name, score) }
            // Floor as well as ceiling. A strategy that scores far BELOW
            // chance is just as usable inverted -- "the shortest option is
            // never right" was worth 13% here, which is to say 87% as a rule
            // about where the answer is not.
            //
            // This bound is load-bearing, not slack: "take the shortest
            // option" sits at 20.5% after the rewrite pass, half a point
            // above it. Shortening options closes the longest-option cue and
            // opens this one, so a future pass that trims further has to
            // lengthen some keys to stay honest.
            XCTAssertGreaterThan(
                score, 0.20,
                "\"\(name)\" scores \(Int(score * 100))%, so its inverse is a usable rule")
        }
        XCTAssertLessThanOrEqual(
            worst.score, 0.51,
            "\"\(worst.name)\" answers \(Int(worst.score * 100))% of the drills "
            + "without reading one of them (chance is 33%)")
    }

    /// The house style, measured against the corpus that already has it.
    ///
    /// question_bank.json holds 270 real-format item-set questions and passes
    /// these rules on 91% of them; the drills passed 12% when this was
    /// written and 84% after 2,290 of them were rewritten. Every count here is
    /// a ratchet taken from the state of the corpus at the time, and
    /// `scripts/drill_style_lint.py` computes the same numbers outside Xcode.
    ///
    /// Where what remains actually sits, measured rather than assumed. The
    /// first commit after the pass claimed all of it was in the 377 drills the
    /// usage limit stopped the pass from reaching. That is true of five rules
    /// and false of two:
    ///
    ///   too_long            100% in the 377    boilerplate   100% in the 377
    ///   dangling_reference  100% in the 377    multi_sentence 99% in the 377
    ///   shouting             99% in the 377    mixed_types     76% in the 377
    ///   heading_stem         55% in the 377
    ///   inconsistent_case     0% in the 377 — the pass INTRODUCED every one
    ///
    /// The last line is the one worth keeping. Shortening options into
    /// lowercase continuations of the stem is right, and it collides with the
    /// options a proper noun forces into upper case, so a rewrite that
    /// improves an item can still leave its three options disagreeing. The
    /// pass produced 13. Five of them had the odd option sitting on the key,
    /// which is a cue; normalising those five cleared four of the 13, and 9
    /// remain where the case splits without naming the answer.
    func testDrillStyleMatchesTheCaseBank() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")
        let items = drillItems(content)

        // A drill has no vignette: no exhibit field in the data model, one
        // question on screen at a time. So an item that cites Example 14 is
        // pointing at a table that does not exist in this app. The case bank
        // cites exhibits constantly and is right to -- it has them.
        let dangling = #"\b(?:Example|Exhibit|Table|Figure|Section|Equation|Case)\s+\d+"#
            + #"|according to the (?:CFA Institute )?curriculum"#
            + #"|the curriculum (?:states|says|notes|identifies|warns)"#
        // A CFA stem is a sentence ending in a qualifier. "The LDI Model most
        // likely:" is a heading with a colon after it, and the heading is what
        // this rule is for.
        //
        // It used to look for a "finite verb" before the qualifier, where the
        // pattern was a whitelist of auxiliaries and determiners rather than a
        // verb detector. So a stem whose verb is a CONTENT verb failed it:
        // "Fiscal policy plays a smaller role than monetary policy most likely
        // because:", "An institutional investor's IPS most likely codifies:",
        // "Banks and insurance companies differ from other investors most
        // likely because they:". Those are the stems the house style asks for.
        //
        // That rule counted 266, and 207 of them sat in drills the rewrite
        // pass had just improved, because a rewritten stem uses a content verb
        // where the generator's heading used "the". Ratcheting it would have
        // failed the build for getting better, which is the one thing a
        // ratchet must never do.
        //
        // Two conditions together find the heading and leave the clause alone:
        // the qualifier is the LAST thing in the stem bar a colon, AND no
        // auxiliary appears anywhere in it. "A good capital market forecast is
        // most likely:" ends in a bare qualifier but has "is", so it is a
        // sentence; "Liquidity aggregators most likely:" has neither and is a
        // heading. 89 across the corpus, and the list has no false positive in
        // it. scripts/drill_style_lint.py computes the same number.
        let bareQualifier = #"\b(?:most likely|least likely|closest to|best describes?"#
            + #"|best characteri[sz]ed|most appropriate|best explains?|most accurate"#
            + #"|least accurate|best supported)\s*:?\s*$"#
        let auxiliary = #"\b(?:is|are|was|were|will|would|should|does|do|did|has|have"#
            + #"|had|can|could|may|might|must|be|been|being"#
            + #"|which|what|who|whose|the|if|when|using|based|given|after"#
            + #"|for|under|accord\w*|compared|relative)\b"#

        var counts: [String: Int] = [:]
        for item in items {
            if try item.options.values.contains(where: {
                try matches(#"That specification would be used as-is"#
                            + #"|That approach would be applied without further adjustment"#, $0)
            }) { counts["boilerplate", default: 0] += 1 }

            if item.options.values.contains(where: { sentenceCount($0) > 1 }) {
                counts["multi_sentence", default: 0] += 1
            }
            if item.options.values.contains(where: { $0.contains("=") }) {
                counts["equation", default: 0] += 1
            }
            if item.options.values.contains(where: { $0.count > 120 }) {
                counts["too_long", default: 0] += 1
            }
            let numeric = Set(item.options.values.map(hasDigit))
            if numeric.count > 1 { counts["mixed_option_types", default: 0] += 1 }
            // New rule, and the only defect the rewrite pass added rather than
            // removed, so it is ratcheted here from the start.
            //
            // The test is "is the first character lowercase", NOT "is it
            // uppercase", because an option may open with a digit and the
            // linter groups a digit with the capitals. Asking the question the
            // other way round reads 5 here against the linter's 9, the
            // difference being items whose options open with figures.
            let initials = Set(item.options.values.compactMap {
                $0.first.map { $0.isLowercase }
            })
            if initials.count > 1 { counts["inconsistent_case", default: 0] += 1 }

            if try matches(dangling, item.stem) {
                counts["dangling_reference", default: 0] += 1
            }
            if try matches(bareQualifier, item.stem),
               try !matches(auxiliary, item.stem) {
                counts["heading_stem", default: 0] += 1
            }
        }

        // Ratchets, from the corpus as it stood. Never loosen one; a rise
        // means the defect came back.
        let ceiling = [
            "boilerplate": 144,
            "multi_sentence": 177,
            "equation": 0,
            "too_long": 339,
            "mixed_option_types": 70,
            "dangling_reference": 64,
            "heading_stem": 89,
            "inconsistent_case": 9,
        ]
        for (rule, limit) in ceiling.sorted(by: { $0.key < $1.key }) {
            let found = counts[rule] ?? 0
            XCTAssertLessThanOrEqual(
                found, limit,
                "\(found) drills break \"\(rule)\", up from \(limit) — "
                + "see scripts/drill_house_style.md")
        }
    }

    /// Where the answer SITS must carry no information either.
    ///
    /// The generator laid the key down in strict rotation: inside a single LOS
    /// group — which is exactly what "Run all N" serves, in file order, with
    /// options never shuffled at display time — 2,418 of 2,420 consecutive
    /// pairs went A to B to C to A. 99.9%. Answer the first question and you
    /// have every answer after it.
    ///
    /// Nothing in this file caught that. Every assertion above is about the
    /// TEXT of an option, and the cycle is not in the text. `fix_drill_answer_
    /// cycle.py` permuted each question's options, rationales and key together
    /// to break it.
    ///
    /// The assertion is a band, not a target. Forcing any of these three
    /// transitions to zero would be the same mistake as the one that produced
    /// a 96% length cue: "never the next letter" is as usable a rule as
    /// "always the next letter". A third each, give or take sampling noise, is
    /// the only shape that leaks nothing.
    func testDrillAnswerPositionIsNotASequence() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")

        let forward: [String: String] = ["A": "B", "B": "C", "C": "A"]
        var transitions: [String: Int] = ["same": 0, "forward": 0, "backward": 0]
        var pairs = 0
        var longestRun = 1

        for bundle in content.losDrillBundles.values {
            for group in bundle.drills {
                let keys = group.questions.compactMap { q -> String? in
                    guard let options = q.options, options.count == 3,
                          let correct = q.correct, options[correct] != nil
                    else { return nil }
                    return correct
                }
                var run = 1
                for (previous, next) in zip(keys, keys.dropFirst()) {
                    pairs += 1
                    if previous == next {
                        transitions["same", default: 0] += 1
                        run += 1
                        longestRun = max(longestRun, run)
                    } else {
                        run = 1
                        let name = forward[previous] == next ? "forward" : "backward"
                        transitions[name, default: 0] += 1
                    }
                }
            }
        }

        XCTAssertGreaterThan(pairs, 2_000, "not enough drills to measure a sequence")
        for (name, count) in transitions.sorted(by: { $0.key < $1.key }) {
            let share = Double(count) / Double(pairs)
            XCTAssertGreaterThan(
                share, 0.20,
                "the key follows the previous key's \(name) transition on only "
                + "\(Int(share * 100))% of consecutive drills — rare enough to bet against")
            XCTAssertLessThan(
                share, 0.47,
                "the key follows the previous key's \(name) transition on "
                + "\(Int(share * 100))% of consecutive drills — answer one and you have the rest")
        }

        // A long enough run of one letter reads as a pattern even when it is
        // not one, and the learner cannot tell the difference. The permutation
        // refuses a fourth repeat while any quota is left to refuse it with.
        XCTAssertLessThanOrEqual(
            longestRun, 4,
            "\(longestRun) drills in a row share an answer letter")
    }

    /// Practice-by-LOS finds Standards I–VII via candidate_los; Progress
    /// coverage uses primary_reading_ids. Those must agree after unparking.
    func testEthicsStandardCasesAreNotParkedOnCodeReading() throws {
        var parked: [String] = []
        var standardCoverage: [String: Int] = [:]
        for q in allQuestions(try loadBank()) {
            var seen = Set<String>()
            let ordered = q.candidateLOS.compactMap { losID -> String? in
                guard let dot = losID.lastIndex(of: ".") else { return nil }
                return String(losID[..<dot])
            }.filter { seen.insert($0).inserted }
            if q.primaryReadingIDs == ["code_and_standards"],
               ordered.contains(where: { $0 != "code_and_standards" }) {
                parked.append(q.id)
            }
            for readingID in q.primaryReadingIDs {
                standardCoverage[readingID, default: 0] += 1
            }
        }
        XCTAssertTrue(parked.isEmpty, "Parked on code_and_standards: \(parked)")
        for readingID in [
            "guidance_standard_i_professionalism",
            "guidance_standard_ii_integrity_capital_markets",
            "guidance_standard_iii_duties_to_clients",
            "guidance_standard_iv_duties_to_employers",
            "guidance_standard_v_investment_analysis",
            "guidance_standard_vi_conflicts_of_interest",
            "guidance_standard_vii_responsibilities",
            "asset_manager_code_of_professional_conduct",
        ] {
            XCTAssertGreaterThan(
                standardCoverage[readingID] ?? 0,
                0,
                "no case coverage for \(readingID)"
            )
        }
    }

    /// Human retags after the 2027 letter repair — not another cosine dump.
    func testKnownStemMissesUseStableLetters() throws {
        let byID = Dictionary(uniqueKeysWithValues: allQuestions(try loadBank()).map { ($0.id, $0) })
        func los(_ id: String) throws -> [String] {
            try XCTUnwrap(byID[id], "missing \(id)").candidateLOS
        }
        XCTAssertEqual(try los("options_duane_armitage_duane_q2"), ["options_strategies.g"])
        XCTAssertEqual(try los("options_duane_armitage_duane_essay_q6"), ["options_strategies.g"])
        XCTAssertEqual(
            try los("elbe_society_the_elbe_society_q3"),
            ["asset_allocation_to_alternative_investments.c"]
        )
        XCTAssertEqual(
            try los("elbe_society_the_elbe_society_essay_q6"),
            ["asset_allocation_to_alternative_investments.c"]
        )
        XCTAssertEqual(
            try los("gambier_advisory_lucas_thompson_q2"),
            ["asset_allocation_to_alternative_investments.c"]
        )
        XCTAssertEqual(
            try los("gambier_advisory_lucas_thompson_essay_q6"),
            ["asset_allocation_to_alternative_investments.c"]
        )
        XCTAssertEqual(
            try los("cme_foundation_the_united_states_q1"),
            ["capital_market_expectations_part_1_framework_and_macro_considerations.g"]
        )
        XCTAssertEqual(
            try los("cme_foundation_the_united_states_essay_q8"),
            ["capital_market_expectations_part_1_framework_and_macro_considerations.g"]
        )
        XCTAssertEqual(
            try los("cme_foundation_the_united_states_q3"),
            ["capital_market_expectations_part_2_forecasting_asset_class_returns.e"]
        )
        XCTAssertEqual(
            try los("cme_foundation_the_united_states_essay_q5"),
            ["capital_market_expectations_part_2_forecasting_asset_class_returns.e"]
        )
        XCTAssertEqual(
            try los("silverline_trading_pathway_essay_q2"),
            [
                "trading_costs_and_electronic_markets.c",
                "trading_costs_and_electronic_markets.a",
            ]
        )
        XCTAssertEqual(
            try los("active_equity_investing_construction_lisette_langham_lisette_essay_q9"),
            ["active_equity_investing_portfolio_construction.c"]
        )
        XCTAssertEqual(
            try los("overview_of_fi_danny_moynahan_danny_q1"),
            ["overview_of_fixed_income_portfolio_management.a"]
        )
        XCTAssertEqual(
            try los("athena_investment_services_case_scenario_essay_q7"),
            [
                "asset_manager_code_of_professional_conduct.c",
                "guidance_standard_iii_duties_to_clients.a",
            ]
        )
        XCTAssertEqual(try los("ava_chan_ava_chan_q1"), ["asset_allocation_to_alternative_investments.g"])
        XCTAssertEqual(try los("ava_chan_ava_chan_q2"), ["asset_allocation_to_alternative_investments.d"])
        XCTAssertEqual(try los("ava_chan_ava_chan_q4"), ["asset_allocation_to_alternative_investments.h"])
        XCTAssertEqual(
            try los("ava_chan_ava_chan_essay_q5"),
            [
                "case_study_in_portfolio_management_institutional_endowment.b",
                "asset_allocation_to_alternative_investments.g",
                "asset_allocation_to_alternative_investments.e",
            ]
        )
        XCTAssertEqual(try los("ava_chan_ava_chan_essay_q6"), ["asset_allocation_to_alternative_investments.d"])
        XCTAssertEqual(try los("ava_chan_ava_chan_essay_q7"), ["an_overview_of_private_wealth_management.e"])
        XCTAssertEqual(try los("ava_chan_ava_chan_essay_q8"), ["asset_allocation_to_alternative_investments.e"])
        XCTAssertEqual(
            try los("ptolemy_foundation_the_ptolemy_foundation_q4"),
            ["capital_market_expectations_part_2_forecasting_asset_class_returns.c"]
        )
        XCTAssertEqual(
            try los("ptolemy_foundation_the_ptolemy_foundation_essay_q7"),
            ["capital_market_expectations_part_2_forecasting_asset_class_returns.c"]
        )
        XCTAssertEqual(
            try los("ptolemy_foundation_the_ptolemy_foundation_essay_q8"),
            [
                "capital_market_expectations_part_2_forecasting_asset_class_returns.c",
                "capital_market_expectations_part_2_forecasting_asset_class_returns.d",
            ]
        )
        XCTAssertEqual(
            try los("active_equity_investing_construction_the_epsilon_institute_t_q3"),
            ["active_equity_investing_portfolio_construction.c"]
        )
        XCTAssertEqual(
            try los("active_equity_investing_construction_the_epsilon_institute_t_q4"),
            ["active_equity_investing_portfolio_construction.c"]
        )
        XCTAssertEqual(
            try los("active_equity_investing_construction_the_epsilon_institute_t_q5"),
            ["active_equity_investing_portfolio_construction.f"]
        )
        XCTAssertEqual(
            try los("active_equity_investing_construction_the_epsilon_institute_t_essay_q8"),
            ["active_equity_investing_portfolio_construction.c"]
        )
        XCTAssertEqual(
            try los("active_equity_investing_construction_the_epsilon_institute_t_essay_q9"),
            ["active_equity_investing_portfolio_construction.c"]
        )
        XCTAssertEqual(
            try los("active_equity_investing_construction_the_epsilon_institute_t_essay_q10"),
            ["active_equity_investing_portfolio_construction.f"]
        )
        XCTAssertEqual(
            try los("gambier_advisory_lucas_thompson_essay_q8"),
            ["asset_allocation_to_alternative_investments.h"]
        )
    }

    /// Standards I–VII share two templates; the picker prefixes the standard.
    func testEthicsStandardLOSDisplayTextIsPrefixed() throws {
        let content = ContentLoader()
        content.load()
        let master = try XCTUnwrap(content.losMaster)

        var prefixed = Set<String>()
        for area in master.areas {
            for reading in area.readings {
                for los in reading.los {
                    if let prefix = LOS.ethicsStandardPrefix(for: los.readingID) {
                        prefixed.insert(los.readingID)
                        XCTAssertTrue(
                            los.displayText.hasPrefix("\(prefix) — "),
                            los.displayText
                        )
                        XCTAssertNotEqual(los.displayText, los.text)
                    } else if let note = LOS.indexBasedCompareNote(for: los.id) {
                        XCTAssertTrue(los.displayText.hasSuffix(note), los.displayText)
                        XCTAssertNotEqual(los.displayText, los.text)
                    } else {
                        XCTAssertEqual(los.displayText, los.text)
                    }
                }
            }
        }
        XCTAssertEqual(prefixed.count, 7)
    }

    /// Per-LOS Progress pools are candidate_los ∪ drill primary_los, so a
    /// Standard or GIPS letter is visible even when the reading row is busy.
    func testPerLOSCoverageUsesCandidateLOSUnionDrills() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")
        let coverage = ProgressStats.losCoverage(content: content, attempts: [])

        func reading(_ areaID: String, _ readingID: String) throws -> LOSReadingCoverage {
            let area = try XCTUnwrap(coverage.first { $0.areaID == areaID })
            return try XCTUnwrap(area.readings.first { $0.readingID == readingID })
        }
        func item(_ reading: LOSReadingCoverage, letter: String) throws -> LOSItemCoverage {
            try XCTUnwrap(reading.items.first { $0.letter == letter })
        }

        let standardIII = try reading(
            "ethical_and_professional_standards",
            "guidance_standard_iii_duties_to_clients"
        )
        XCTAssertGreaterThan(standardIII.questionCount, 0)
        XCTAssertGreaterThan(try item(standardIII, letter: "a").questionCount, 0)

        let gips = try reading(
            "performance_measurement",
            "overview_of_the_global_investment_performance_standards"
        )
        XCTAssertGreaterThan(try item(gips, letter: "k").questionCount, 0)

        let swf = try reading(
            "portfolio_construction",
            "case_study_in_portfolio_management_institutional_swf"
        )
        XCTAssertGreaterThan(swf.questionCount, 0)
        XCTAssertGreaterThan(try item(swf, letter: "c").questionCount, 0)

        let endowment = try reading(
            "portfolio_management_pathway",
            "case_study_in_portfolio_management_institutional_endowment"
        )
        XCTAssertGreaterThan(endowment.questionCount, 0)
        XCTAssertGreaterThan(try item(endowment, letter: "a").questionCount, 0)
    }

    func testSWFAndEndowmentCaseStudyStemsAreTagged() throws {
        let byID = Dictionary(uniqueKeysWithValues: allQuestions(try loadBank()).map { ($0.id, $0) })
        func los(_ id: String) throws -> [String] {
            try XCTUnwrap(byID[id], "missing \(id)").candidateLOS
        }
        XCTAssertEqual(
            try los("elbe_society_the_elbe_society_q4"),
            [
                "case_study_in_portfolio_management_institutional_endowment.a",
                "asset_allocation_to_alternative_investments.g",
            ]
        )
        XCTAssertEqual(
            try los("elbe_society_the_elbe_society_essay_q7"),
            [
                "case_study_in_portfolio_management_institutional_endowment.c",
                "asset_allocation_to_alternative_investments.g",
            ]
        )
        XCTAssertEqual(
            try los("elbe_society_the_elbe_society_essay_q8"),
            [
                "asset_allocation_to_alternative_investments.e",
                "asset_allocation_to_alternative_investments.a",
            ]
        )
        XCTAssertEqual(
            try los("gambier_advisory_lucas_thompson_essay_q7"),
            [
                "asset_allocation_to_alternative_investments.d",
            ]
        )
        XCTAssertEqual(try los("karelia_heritage_fund_swf_q1"), [
            "case_study_in_portfolio_management_institutional_swf.a",
        ])
        XCTAssertEqual(try los("karelia_heritage_fund_swf_q2"), [
            "case_study_in_portfolio_management_institutional_swf.b",
        ])
        XCTAssertEqual(try los("karelia_heritage_fund_swf_essay_q3"), [
            "case_study_in_portfolio_management_institutional_swf.e",
        ])
        XCTAssertEqual(try los("karelia_heritage_fund_swf_essay_q4"), [
            "case_study_in_portfolio_management_institutional_swf.c",
        ])
        XCTAssertEqual(try los("karelia_heritage_fund_swf_essay_q5"), [
            "case_study_in_portfolio_management_institutional_swf.d",
        ])
        XCTAssertEqual(try los("ridgewood_college_endowment_essay_q1"), [
            "case_study_in_portfolio_management_institutional_endowment.d",
        ])
        XCTAssertEqual(try los("ridgewood_college_endowment_q2"), [
            "case_study_in_portfolio_management_institutional_endowment.e",
        ])
        XCTAssertEqual(
            try los("rothhaven_foundation_alt_pathway_essay_q4"),
            [
                "case_study_in_portfolio_management_institutional_endowment.g",
                "asset_allocation_to_alternative_investments.d",
            ]
        )
        XCTAssertEqual(
            try los("aventine_pension_swaps_pathway_essay_q3"),
            [
                "swaps_forwards_and_futures_strategies.a",
                "case_study_in_portfolio_management_institutional_endowment.f",
            ]
        )
    }

    /// Index-Based `.b` vs `.c` are the outline's two compare-statements.
    func testIndexBasedCompareStatementsAreLabeled() throws {
        let content = ContentLoader()
        content.load()
        let master = try XCTUnwrap(content.losMaster)
        let byID = Dictionary(uniqueKeysWithValues: master.losFlat.map { ($0.id, $0) })
        let strategies = try XCTUnwrap(byID["index_based_equity_strategies.b"])
        let investing = try XCTUnwrap(byID["index_based_equity_strategies.c"])
        XCTAssertTrue(strategies.displayText.contains("outline compare-statement: strategies"))
        XCTAssertTrue(investing.displayText.contains("outline compare-statement: investing"))
        XCTAssertNotEqual(strategies.displayText, investing.displayText)
    }

    /// AMC `.a`–`.d`, PWM `.a`/`.c`, and alts `.b` now have original drill groups.
    func testPreviouslyEmptyOfficialLOSHaveOriginalDrills() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")

        func count(reading: String, letter: String) throws -> Int {
            let bundle = try XCTUnwrap(content.drillBundle(forReading: reading))
            let group = try XCTUnwrap(bundle.drills.first { $0.losLetter == letter })
            XCTAssertEqual(group.losText, content.los(id: "\(reading).\(letter)")?.text)
            XCTAssertGreaterThanOrEqual(group.questions.count, 6)
            return group.questions.count
        }

        XCTAssertEqual(try count(reading: "asset_manager_code_of_professional_conduct", letter: "a"), 6)
        XCTAssertEqual(try count(reading: "asset_manager_code_of_professional_conduct", letter: "b"), 6)
        XCTAssertEqual(try count(reading: "asset_manager_code_of_professional_conduct", letter: "c"), 6)
        XCTAssertEqual(try count(reading: "asset_manager_code_of_professional_conduct", letter: "d"), 6)
        XCTAssertEqual(try count(reading: "an_overview_of_private_wealth_management", letter: "a"), 6)
        XCTAssertEqual(try count(reading: "an_overview_of_private_wealth_management", letter: "c"), 6)
        XCTAssertEqual(try count(reading: "asset_allocation_to_alternative_investments", letter: "b"), 6)
    }

    func testAssetManagerCodeHasOriginalStudyNotes() throws {
        let content = ContentLoader()
        content.load()
        let entry = try XCTUnwrap(
            content.readingNotes(id: "asset_manager_code_of_professional_conduct")
        )
        let blocks = NotesContentParser.parse(entry.content)
        XCTAssertFalse(blocks.isEmpty)
        let losHeaders = blocks.compactMap { block -> Int? in
            if case .losSection(let numbers, _, _) = block { return numbers.first }
            return nil
        }
        XCTAssertEqual(losHeaders, [1, 2, 3, 4])
        XCTAssertFalse(blocks.contains { block in
            switch block {
            case .subheading(let t), .paragraph(let t):
                return t.contains("Study Notes") || t.hasPrefix("Topic Area:") || t.hasPrefix("Reading:")
            default:
                return false
            }
        })
    }
}
