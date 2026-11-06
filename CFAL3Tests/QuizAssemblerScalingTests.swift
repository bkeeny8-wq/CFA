import XCTest
@testable import CFAL3

/// Covers the per-unit scaling contract of `QuizAssembler.assemble`: each
/// in-scope book / reading / LOS contributes up to `pref.count` questions, so
/// the session total grows with how much scope is selected.
final class QuizAssemblerScalingTests: XCTestCase {

    private func loadedContent() -> ContentLoader {
        let content = ContentLoader()
        content.load()
        return content
    }

    /// An isolated defaults suite so a real device/simulator's stored practice
    /// preferences can never leak into (or out of) these tests.
    private func freshPreference() -> PracticeBuilderPreference {
        let name = "QuizAssemblerScalingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PracticeBuilderPreference(defaults: defaults)
    }

    private func gradeableDrillCount(_ bundle: LOSDrillBundle) -> Int {
        bundle.drills.flatMap(\.questions).filter { $0.correct != nil }.count
    }

    // MARK: - Per-reading quota

    func testPerReadingQuotaCapsEachReadingAndScalesWithScope() {
        let content = loadedContent()
        XCTAssertNil(content.loadError, content.loadError ?? "")
        let quota = 5

        // Readings whose gradeable drill count comfortably clears the quota, so
        // each one is a genuine cap rather than merely "everything available".
        let richReadings = content.losDrillBundles
            .filter { gradeableDrillCount($0.value) >= quota + 1 }
            .keys
            .sorted()
        XCTAssertGreaterThanOrEqual(
            richReadings.count, 2,
            "Fixture needs ≥2 drill-rich readings for this test"
        )

        func session(readings: [String]) -> [String] {
            let pref = freshPreference()
            pref.sourceFilter = .drillsOnly
            pref.typeFilter = .mixed
            pref.weaknessWeighted = false
            pref.count = .five
            pref.selectedReadings = Set(readings)
            return QuizAssembler.assemble(pref: pref, content: content, attempts: [])
        }

        let twoReadings = Array(richReadings.prefix(2))
        let ids = session(readings: twoReadings)

        // No question is ever returned twice.
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate question IDs in session")

        // Each rich reading yields exactly the quota → total = quota × units.
        XCTAssertEqual(ids.count, quota * twoReadings.count)

        // Per-reading cap holds when mapped back to source readings.
        var perReading: [String: Int] = [:]
        for id in ids {
            if let drill = content.drillQuestion(id: id) {
                perReading[drill.readingID, default: 0] += 1
            }
        }
        for reading in twoReadings {
            XCTAssertLessThanOrEqual(perReading[reading] ?? 0, quota, "Reading \(reading) exceeded quota")
        }

        // Widening scope to a third reading grows the session.
        if richReadings.count >= 3 {
            let threeIDs = session(readings: Array(richReadings.prefix(3)))
            XCTAssertEqual(threeIDs.count, quota * 3)
            XCTAssertGreaterThan(threeIDs.count, ids.count)
        }
    }

    // MARK: - Whole-curriculum breakdown by book

    func testWholeCurriculumBreaksDownByBook() {
        let content = loadedContent()
        let quota = 3

        let pref = freshPreference()
        pref.sourceFilter = .drillsOnly
        pref.typeFilter = .mcOnly
        pref.weaknessWeighted = false
        pref.count = .three          // 3 per book
        pref.selectedTopics = []     // "All" scope → break down by every book

        let ids = QuizAssembler.assemble(pref: pref, content: content, attempts: [])

        // Books represented among gradeable MC drills.
        //
        // Intersected with the bank's topic IDs, exactly as production does in
        // `targetUnits`. Without that intersection this set also picked up the
        // topics.json summary IDs (cme_1, equity, ethics…), 16 entries rather
        // than 6, and the bound below became 3 × 16 = 48 against a true
        // contract of 3 × 6 = 18. That is 2.7× too slack to catch the one
        // regression this test exists for: dropping `.intersection(bookIDs)`
        // from `targetUnits`/`units(of:)` — the regression the comment at
        // QuizAssembler.swift:121 says already shipped once — roughly doubles
        // the session, and every doubled draw still sat under 48.
        let bookIDs = Set(content.questionBank?.topics.map(\.id) ?? [])
        let index = QuizAssembler.readingTopicIndex(content: content)
        var books = Set<String>()
        for bundle in content.losDrillBundles.values {
            for drill in bundle.drills.flatMap(\.questions)
            where drill.type == .mc && drill.correct != nil {
                books.formUnion(index[drill.readingID] ?? [])
            }
        }
        books.formIntersection(bookIDs)
        XCTAssertEqual(books.count, 6, "six books carry gradeable MC drills")

        // Each returned item fills exactly one under-quota book slot, and every
        // book is capped at `quota`, so the draw can never exceed quota × books.
        XCTAssertGreaterThan(ids.count, 0)
        XCTAssertLessThanOrEqual(ids.count, quota * books.count)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - The reading → book map agrees with the scope UI

    /// The Books, Readings and LOS sheets are all built from `losMaster.areas`.
    /// If the assembler's map disagrees, the builder offers a reading under a
    /// book and then filters every one of its questions away.
    func testEveryReadingResolvesToTheBookLosMasterFilesItUnder() {
        let content = loadedContent()
        let index = QuizAssembler.readingTopicIndex(content: content)
        let areas = content.losMaster?.areas ?? []
        XCTAssertFalse(areas.isEmpty)

        for area in areas {
            for reading in area.readings {
                let resolved = index[reading.id] ?? []
                XCTAssertTrue(
                    resolved.contains(area.id),
                    "\(reading.id): los_master files it under \(area.id), "
                    + "the assembler resolves it to \(resolved.sorted())"
                )
            }
        }
    }

    /// The dead end this pins: book "Portfolio Construction" + reading
    /// "Overview of Equity Portfolio Management" matched 0 of that reading's
    /// 145 questions, because the two authorities disagreed about its book.
    func testBookPlusOneOfItsOwnReadingsIsNeverEmpty() {
        let content = loadedContent()
        let bookIDs = Set(content.questionBank?.topics.map(\.id) ?? [])

        func session(book: String?, reading: String) -> [String] {
            let pref = freshPreference()
            pref.sourceFilter = .both
            pref.typeFilter = .mixed
            pref.weaknessWeighted = false
            pref.count = .all
            pref.selectedTopics = book.map { [$0] } ?? []
            pref.selectedReadings = [reading]
            return QuizAssembler.assemble(pref: pref, content: content, attempts: [])
        }

        for area in content.losMaster?.areas ?? [] where bookIDs.contains(area.id) {
            for reading in area.readings {
                let alone = session(book: nil, reading: reading.id)
                guard !alone.isEmpty else { continue }   // nothing authored yet
                let scoped = session(book: area.id, reading: reading.id)
                XCTAssertFalse(
                    scoped.isEmpty,
                    "\(reading.id) has \(alone.count) questions on its own but 0 "
                    + "when its own book (\(area.id)) is also selected"
                )
            }
        }
    }

    // MARK: - Per-LOS quota

    /// Widening from one LOS to many must widen the session.
    ///
    /// It did not. A bank question used to carry its reading's whole
    /// candidate list — 213 of the 490 named 24 or more — and each pick was
    /// charged against every under-quota LOS it touched, so five wide-tagged
    /// questions filled all nine counters at once. A nine-LOS selection with
    /// 145 eligible questions returned as few as 5, the same as selecting a
    /// single LOS, and a different count on each visit.
    /// Tags are now 1–3 per item; one-charge-per-question is still the
    /// contract, and drills still carry exactly one LOS.
    func testPerLOSQuotaScalesWithTheNumberOfSelectedLOS() {
        let content = loadedContent()
        let quota = 5

        func session(los: Set<String>) -> [String] {
            let pref = freshPreference()
            pref.sourceFilter = .both          // .drillsOnly would hide the bug:
            pref.typeFilter = .mixed           // every drill carries exactly 1 LOS
            pref.weaknessWeighted = false
            pref.count = .five
            pref.selectedLOS = los
            return QuizAssembler.assemble(pref: pref, content: content, attempts: [])
        }

        // Everything available for one LOS, so the expectation below can be
        // exact rather than a loose bound. A "≥ 3 × quota" style assertion is
        // not enough: the collapse is total on some readings and mild on
        // others, and a slack bound passes on the mild ones while the severe
        // ones still return a fifth of what they promise.
        func available(_ losID: String) -> Int {
            let pref = freshPreference()
            pref.sourceFilter = .both
            pref.typeFilter = .mixed
            pref.weaknessWeighted = false
            pref.count = .all
            pref.selectedLOS = [losID]
            return QuizAssembler.assemble(pref: pref, content: content, attempts: []).count
        }

        // A reading where EVERY LOS can fill its quota. Then the contract is
        // exactly quota × units, with no "not enough content" excuse.
        let candidates = (content.losMaster?.areas ?? [])
            .flatMap(\.readings)
            .filter { $0.los.count >= 5 }
            .sorted { $0.los.count > $1.los.count }
            .prefix(6)

        guard let reading = candidates.first(where: { r in
            r.los.allSatisfy { available($0.id) >= quota }
        }) else {
            return XCTFail("fixture needs a reading whose every LOS has ≥\(quota) questions")
        }

        let all = Set(reading.los.map(\.id))
        let bound = quota * all.count
        let wide = session(los: all)

        XCTAssertLessThanOrEqual(wide.count, bound, "the quota is an upper bound")

        // Most of the bound, not all of it. Equality is not guaranteed even
        // with enough content: a LOS whose questions are all charged to
        // emptier LOS first can finish short, and the pool is reshuffled on
        // every call. Measured over 600 shuffles of this selection the fixed
        // walk never drops below 96% of the bound and the broken one never
        // reaches 55%, so three quarters separates them with room either side
        // and no flakiness.
        XCTAssertGreaterThanOrEqual(
            wide.count * 4, bound * 3,
            "\(reading.id): \(all.count) LOS in scope, each with at least \(quota) questions "
            + "available, so the session should approach \(bound) — got \(wide.count)"
        )
        XCTAssertEqual(Set(wide).count, wide.count, "duplicate question IDs in session")
    }

    // MARK: - "All" lifts the cap

    func testAllQuotaReturnsEntireFilteredPool() {
        let content = loadedContent()

        let pref = freshPreference()
        pref.sourceFilter = .drillsOnly
        pref.typeFilter = .mcOnly
        pref.weaknessWeighted = false
        pref.count = .all

        let ids = QuizAssembler.assemble(pref: pref, content: content, attempts: [])
        let expected = content.losDrillBundles.values
            .flatMap(\.drills)
            .flatMap(\.questions)
            .filter { $0.type == .mc && $0.correct != nil }
            .count

        XCTAssertEqual(ids.count, expected, "`.all` should return every matching question")
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

/// The commute contract.
///
/// 82 hours of this plan are 35 minutes each way on a phone, with no
/// calculator and no scratch paper. That only works if a no-calculator sitting
/// genuinely cannot serve a question needing one, so these tests are about the
/// one direction that costs something: a calculator question reaching the
/// phone pool breaks the session, while a phone question held back merely
/// wastes capacity.
final class CalculatorFilterTests: XCTestCase {

    private func loadedContent() -> ContentLoader {
        let content = ContentLoader()
        content.load()
        return content
    }

    private func freshPreference() -> PracticeBuilderPreference {
        let name = "CalculatorFilterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PracticeBuilderPreference(defaults: defaults)
    }

    /// Unclassified content must be excluded, not admitted. The classifier
    /// leaves nothing unlabelled today, but it is the default that decides
    /// what happens to any question added later.
    func testUnclassifiedIsTreatedAsNeedingACalculator() {
        XCTAssertFalse(CalculatorFilter.noCalculator.allows(needsCalculator: nil))
        XCTAssertTrue(CalculatorFilter.noCalculator.allows(needsCalculator: false))
        XCTAssertFalse(CalculatorFilter.noCalculator.allows(needsCalculator: true))

        XCTAssertTrue(CalculatorFilter.any.allows(needsCalculator: nil))
        XCTAssertTrue(CalculatorFilter.calculatorOnly.allows(needsCalculator: true))
        XCTAssertFalse(CalculatorFilter.calculatorOnly.allows(needsCalculator: nil))
    }

    func testEveryBundledQuestionIsClassified() throws {
        let content = loadedContent()
        let bank = try XCTUnwrap(content.questionBank)

        var unclassified: [String] = []
        for topic in bank.topics {
            for caseStudy in topic.cases {
                for q in caseStudy.questions where q.needsCalculator == nil {
                    unclassified.append(q.id)
                }
            }
        }
        for bundle in content.losDrillBundles.values {
            for group in bundle.drills {
                for d in group.questions where d.needsCalculator == nil {
                    unclassified.append(d.id)
                }
            }
        }
        XCTAssertTrue(unclassified.isEmpty,
                      "\(unclassified.count) unclassified, e.g. \(unclassified.prefix(3))")
    }

    /// The counts the commute plan is sized against. 2,670 phone-friendly
    /// questions is roughly 90 hours of material for 82 hours of commuting;
    /// if this number collapses, the plan's February load changes with it.
    func testPhonePoolIsBigEnoughToPlanAround() throws {
        let content = loadedContent()
        let bank = try XCTUnwrap(content.questionBank)

        let bankPhone = bank.topics
            .flatMap(\.cases).flatMap(\.questions).filter(\.isPhoneFriendly).count
        let drillPhone = content.losDrillBundles.values
            .flatMap(\.drills).flatMap(\.questions).filter(\.isPhoneFriendly).count

        XCTAssertEqual(bankPhone, 86)
        XCTAssertEqual(drillPhone, 2584)

        // No essay is ever phone work: they are written answers carrying
        // 1,018 marks of workings between them.
        let phoneEssays = bank.topics.flatMap(\.cases).flatMap(\.questions)
            .filter { $0.type == .essay && $0.isPhoneFriendly }
        XCTAssertTrue(phoneEssays.isEmpty, "\(phoneEssays.count) essays called phone work")
    }

    /// Every reading has to offer phone drills, or a commute lands on a
    /// reading with nothing to do.
    func testEveryReadingOffersPhoneDrills() {
        let content = loadedContent()
        for (readingID, bundle) in content.losDrillBundles {
            let phone = bundle.drills.flatMap(\.questions).filter(\.isPhoneFriendly).count
            XCTAssertGreaterThan(phone, 0, "\(readingID) has no phone-friendly drill")
        }
    }

    /// The contract itself, through the real assembler rather than a
    /// re-implementation of its predicate.
    func testNoCalculatorSittingServesNoCalculatorQuestions() throws {
        let content = loadedContent()
        let pref = freshPreference()
        pref.calculatorFilter = .noCalculator
        pref.count = .all
        pref.sourceFilter = .both
        pref.typeFilter = .mixed

        let ids = Set(QuizAssembler.assemble(pref: pref, content: content, attempts: []))
        XCTAssertFalse(ids.isEmpty)

        var offenders: [String] = []
        for topic in try XCTUnwrap(content.questionBank).topics {
            for caseStudy in topic.cases {
                for q in caseStudy.questions where ids.contains(q.id) && !q.isPhoneFriendly {
                    offenders.append(q.id)
                }
            }
        }
        for bundle in content.losDrillBundles.values {
            for group in bundle.drills {
                for d in group.questions where ids.contains(d.id) && !d.isPhoneFriendly {
                    offenders.append(d.id)
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "a commute sitting would serve \(offenders.count) unanswerable "
                      + "question(s): \(offenders.prefix(3))")
    }

    /// `DrillQuestion.asQuestion` rebuilds a Question through JSON, and that
    /// payload dictionary is the whole of what survives. A field left out of
    /// it vanishes with no error — and losing this one puts calculator work
    /// into a commute sitting.
    func testDrillRoundTripKeepsTheCalculatorFlag() throws {
        let content = loadedContent()
        let drills = content.losDrillBundles.values.flatMap(\.drills).flatMap(\.questions)

        let phone = try XCTUnwrap(drills.first { $0.needsCalculator == false })
        XCTAssertEqual(phone.asQuestion.needsCalculator, false)
        XCTAssertTrue(phone.asQuestion.isPhoneFriendly)

        let desk = try XCTUnwrap(drills.first { $0.needsCalculator == true })
        XCTAssertEqual(desk.asQuestion.needsCalculator, true)
        XCTAssertFalse(desk.asQuestion.isPhoneFriendly)
    }
}
