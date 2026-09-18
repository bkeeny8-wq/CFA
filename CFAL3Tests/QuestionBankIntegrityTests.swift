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

    /// A uniquely longest or uniquely shortest correct option is a length cue.
    func testDrillCorrectOptionIsNotUniquelyLongestOnMostItems() throws {
        let content = ContentLoader()
        content.load()
        XCTAssertNil(content.loadError, content.loadError ?? "")

        var total = 0
        var uniqueLongest = 0
        var uniqueShortest = 0
        var distractorTails = 0
        var keys: [String: Int] = [:]
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
                    let keyLen = keyText.count
                    let other = options.compactMap { $0.key == correct ? nil : $0.value.count }
                    if let longestOther = other.max(), keyLen > longestOther {
                        uniqueLongest += 1
                    }
                    if let shortestOther = other.min(), keyLen < shortestOther {
                        uniqueShortest += 1
                    }
                    for (letter, text) in options where letter != correct {
                        let range = NSRange(text.startIndex..<text.endIndex, in: text)
                        if tail.firstMatch(in: text, range: range) != nil {
                            distractorTails += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(total, 2_667)
        XCTAssertEqual(uniqueLongest, 0, "correct option uniquely longest on \(uniqueLongest)/\(total)")
        XCTAssertEqual(uniqueShortest, 0, "correct option uniquely shortest on \(uniqueShortest)/\(total)")
        XCTAssertEqual(distractorTails, 0, "grammatical length tails remain on \(distractorTails) distractors")
        XCTAssertEqual(keys["A"], 889)
        XCTAssertEqual(keys["B"], 889)
        XCTAssertEqual(keys["C"], 889)
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
                "case_study_in_portfolio_management_institutional_endowment.a",
                "case_study_in_portfolio_management_institutional_endowment.c",
                "asset_allocation_to_alternative_investments.g",
            ]
        )
        XCTAssertEqual(
            try los("elbe_society_the_elbe_society_essay_q8"),
            [
                "asset_allocation_to_alternative_investments.e",
                "asset_allocation_to_alternative_investments.a",
                "case_study_in_portfolio_management_institutional_swf.c",
            ]
        )
        XCTAssertEqual(
            try los("gambier_advisory_lucas_thompson_essay_q7"),
            [
                "asset_allocation_to_alternative_investments.a",
                "asset_allocation_to_alternative_investments.f",
                "case_study_in_portfolio_management_institutional_swf.d",
            ]
        )
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
            if case .losSection(let number, _) = block { return number }
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
