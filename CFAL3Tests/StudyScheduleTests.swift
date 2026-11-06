import XCTest
@testable import CFAL3

final class StudyScheduleTests: XCTestCase {
    private var schedule: StudySchedule!

    override func setUp() {
        super.setUp()
        let url = Bundle(identifier: "com.brandonkeeny.CFAL3")?
            .url(forResource: "study_schedule", withExtension: "json")
            ?? Bundle(for: StudyScheduleTests.self)
                .url(forResource: "study_schedule", withExtension: "json")
        let data = try! Data(contentsOf: try XCTUnwrap(url, "study_schedule.json not found"))
        schedule = try! JSONDecoder().decode(StudySchedule.self, from: data)
    }

    /// 506.0. Everything from 6 November to the exam was rebuilt against the
    /// owner's own 316-hour slate, replacing 268.5 planned hours. The day count
    /// is unchanged because those 107 days already existed; only their contents
    /// and hours moved.
    ///
    /// Both assertions stay. The declared total and the summed days are
    /// independent, and the split is the only thing that catches a day edit
    /// that forgets the header.
    func testSchedulePins() {
        XCTAssertEqual(schedule.version, 1)
        XCTAssertEqual(schedule.days.count, 230)
        XCTAssertEqual(schedule.totalPlannedHours, 506.0, accuracy: 0.001)
        let summed = schedule.days.reduce(0.0) { $0 + $1.hours }
        XCTAssertEqual(summed, 506.0, accuracy: 0.001)
        XCTAssertEqual(schedule.examDate, "2027-02-20")
    }

    func testCompletedFirstSevenDays() {
        let firstSeven = Array(schedule.days.prefix(7))
        XCTAssertEqual(firstSeven.map(\.date), [
            "2026-07-06",
            "2026-07-07",
            "2026-07-08",
            "2026-07-09",
            "2026-07-10",
            "2026-07-11",
            "2026-07-12",
        ])
        let expectedHours = firstSeven.reduce(0.0) { $0 + $1.hours }
        XCTAssertEqual(expectedHours, 6.0, accuracy: 0.001)

        let completions = firstSeven.map {
            DayCompletion(dateKey: $0.date, completedHours: $0.hours)
        }
        XCTAssertEqual(ScheduleProgress.completedHours(completions: completions), 6.0, accuracy: 0.001)
    }

    /// The cutoff is planned-through-YESTERDAY: today's hours are not a debt
    /// until today is over, or the plan would report you behind from the
    /// moment you wake up.
    ///
    /// The reference date matters more than it looks. This used to sit on
    /// 2026-07-12, which the bundled schedule gives 0.0 hours — a rest day —
    /// so "through yesterday" and "through today" both summed to 6.0 and the
    /// assertion held whichever cutoff the code used. 2026-07-13 is worth
    /// 1.25h, so the two answers differ and the test can see which one it got.
    func testDeltaUsesPlannedThroughYesterday() throws {
        let reference = try XCTUnwrap(ScheduleDates.parse("2026-07-13"))
        let todaysHours = try XCTUnwrap(schedule.days.first { $0.date == "2026-07-13" }?.hours)

        // The reference day has to carry hours or the two cutoffs give the
        // same answer and this test proves nothing. That is exactly what it
        // used to do: it sat on 2026-07-12, a 0.0-hour rest day, so `delta`
        // could have used either function and still read 0.0.
        XCTAssertEqual(todaysHours, 1.25, accuracy: 0.001)

        let throughYesterday = ScheduleProgress.plannedThroughYesterday(schedule: schedule, now: reference)
        let throughToday = ScheduleProgress.plannedToDate(schedule: schedule, now: reference)
        XCTAssertEqual(throughYesterday, 6.0, accuracy: 0.001)
        XCTAssertEqual(throughToday, 7.25, accuracy: 0.001)
        XCTAssertNotEqual(throughYesterday, throughToday, "the cutoffs must differ here")

        // Six planned, six done: level. Today's 1.25h is not a debt until
        // today is over, or the plan reports you behind the moment you wake up.
        let completions = schedule.days.prefix(6).map {
            DayCompletion(dateKey: $0.date, completedHours: $0.hours)
        }
        let delta = ScheduleProgress.delta(schedule: schedule, completions: completions, now: reference)
        XCTAssertEqual(delta, 0.0, accuracy: 0.001,
                       "delta counted today's hours as already owed")
    }

    func testUnknownBlockKindDecodesAsOther() throws {
        let json = """
        {
          "start": "06:00",
          "label": "Custom block",
          "minutes": 30,
          "kind": "future_kind"
        }
        """.data(using: .utf8)!
        let block = try JSONDecoder().decode(ScheduleBlock.self, from: json)
        XCTAssertEqual(block.kind, .other)
        XCTAssertNil(block.readingID)
        XCTAssertNil(block.questionSource, "an absent source must stay absent, not default to app")
        XCTAssertTrue(block.readingIDs.isEmpty)
    }

    func testQuestionSourceDecodes() throws {
        let json = """
        {
          "start": "09:00",
          "label": "MM Q: B6-M5 Yield Curve Strategies",
          "minutes": 60,
          "kind": "questions",
          "book": 6,
          "reading_id": "yield_curve_strategies",
          "question_source": "mm"
        }
        """.data(using: .utf8)!
        let block = try JSONDecoder().decode(ScheduleBlock.self, from: json)
        XCTAssertEqual(block.questionSource, .mm)
        XCTAssertTrue(block.questionSource?.isMeldrum == true)
    }

    /// The failure this guards is not cosmetic. Without the fallback init, one
    /// bad value throws, ContentLoader's `try?` turns the throw into a nil
    /// schedule, and the Plan tab renders "No study schedule" while nothing is
    /// logged — a whole-tab outage from a typo in one of 300 blocks.
    func testUnknownQuestionSourceDecodesAsOtherAndDoesNotThrow() throws {
        let json = """
        {
          "start": "06:00",
          "label": "Q: somewhere new",
          "minutes": 60,
          "kind": "questions",
          "question_source": "schweser"
        }
        """.data(using: .utf8)!
        let block = try JSONDecoder().decode(ScheduleBlock.self, from: json)
        XCTAssertEqual(block.questionSource, .other)
        XCTAssertNil(BlockSourceBadge.text(for: .other),
                     "an unknown source is a content bug to leave invisible, not a fourth badge")
        // "cfai" used to be the unknown value here, which stopped testing
        // anything the moment CFA Institute's bank became a real case.
        XCTAssertEqual(BlockSourceBadge.text(for: .cfai), "CFAI")
    }

    /// Every reading has to appear somewhere in the run to the exam, or the
    /// plan quietly leaves part of the curriculum unpractised. Counted through
    /// `readingIDs` so a bundled block credits both of its readings.
    func testEveryReadingGetsABlockBeforeTheExam() {
        let plan = schedule.days.filter { $0.date >= "2026-11-06" }
        let covered = Set(plan.flatMap(\.blocks).flatMap(\.readingIDs))
        XCTAssertEqual(covered.count, 36, "readings with no block: see los_master")
    }

    /// Scoped to the rebuilt window on purpose. The invariant does NOT hold
    /// file-wide: blocks before 6 November predate the distinction and carry
    /// no source at all.
    func testEveryQuestionBlockDeclaresABank() {
        let plan = schedule.days.filter { $0.date >= "2026-11-06" }.flatMap(\.blocks)
        XCTAssertEqual(plan.count, 162)

        for block in plan {
            if block.kind == .questions {
                XCTAssertNotNil(block.questionSource, "unsourced question block: \(block.label)")
                XCTAssertNotEqual(block.questionSource, .other, block.label)
            } else {
                XCTAssertNil(block.questionSource,
                             "\(block.label) is \(block.kind), it has nothing to source")
            }
        }

        // All three banks are in play. A regression that collapsed the plan
        // onto one of them would still satisfy every assertion above.
        let sources = plan.compactMap(\.questionSource)
        XCTAssertEqual(sources.filter { $0 == .app }.count, 51)
        XCTAssertEqual(sources.filter { $0 == .mm }.count, 44)
        XCTAssertEqual(sources.filter { $0 == .cfai }.count, 36)
    }

    /// The six papers are the scarcest resource on the plan and the whole
    /// point of the December-January shape. Each is sat on its own day and
    /// reviewed the next, and all of them land before February, which is when
    /// the plan switches to weak topics only.
    func testSixPracticeExamsAreSatAndReviewedBeforeFebruary() throws {
        let mocks = schedule.days
            .filter { $0.date >= "2026-11-06" }
            .flatMap { day in day.blocks.filter { $0.kind == .mock }.map { (day.date, $0) } }
        XCTAssertEqual(mocks.count, 6)
        XCTAssertEqual(Set(mocks.map(\.0)).count, 6, "two papers sat on one day")

        for (date, block) in mocks {
            XCTAssertEqual(block.minutes, 360, "\(date) is not a full sitting")
            XCTAssertLessThan(date, "2027-02-01", "\(date) leaves no time to act on it")

            let next = try XCTUnwrap(
                schedule.days.first { $0.date > date && !$0.isRestDay },
                "nothing follows \(date)"
            )
            XCTAssertTrue(
                next.blocks.contains { $0.kind == .review && $0.label.contains("REVIEW") },
                "\(date) is sat but never reviewed; next study day is \(next.date)"
            )
        }
    }

    /// `ScheduleBlock.id` is start-label, which repeats across days, so
    /// anything persisted has to key on the date too. This pins the property
    /// the storage key depends on.
    func testResultKeyIsUniqueAcrossTheWholePlan() {
        var keys: Set<String> = []
        for day in schedule.days {
            for block in day.blocks {
                XCTAssertTrue(keys.insert(block.resultKey(on: day.date)).inserted,
                              "duplicate result key on \(day.date) at \(block.start)")
            }
        }
        XCTAssertEqual(keys.count, schedule.days.reduce(0) { $0 + $1.blocks.count })

        // And the reason it is needed: the plain block id is NOT unique.
        let ids = schedule.days.flatMap { $0.blocks.map(\.id) }
        XCTAssertLessThan(Set(ids).count, ids.count,
                          "if block ids became unique this key could be simplified")
    }

    /// Labels are data: `ScheduleBlock.id` is built from them and the bundled
    /// Ethics blocks name both modules there. A stored ellipsis would lose the
    /// second one and re-key every saved result the day it was fixed.
    func testNoScheduleLabelIsTruncated() {
        for day in schedule.days {
            for block in day.blocks {
                XCTAssertFalse(block.label.hasSuffix("..."), "\(day.date) \(block.label)")
                XCTAssertFalse(block.label.contains("\u{2026}"), "\(day.date) \(block.label)")
            }
        }
    }

    /// Replaces two tests that counted "B5-M1"-style substrings in block
    /// labels. Every block carrying those codes sat inside the window the
    /// rebuild replaced, so both assertions had quietly become counts of
    /// zero — and substring matching over labels was always the fragile part:
    /// any future "B5-M2x" silently joined the bucket it was meant to exclude.
    ///
    /// What those tests were really protecting is that a plan block opens the
    /// reading it names. That is asserted here directly, against every block
    /// in the file, without depending on how a label happens to be spelled.
    func testEveryBlockReadingIDResolvesToARealReading() throws {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")
        let known = Set((content.losMaster?.areas ?? []).flatMap(\.readings).map(\.id))
        XCTAssertFalse(known.isEmpty)

        var checked = 0
        for day in schedule.days {
            for block in day.blocks {
                for readingID in block.readingIDs {
                    XCTAssertTrue(
                        known.contains(readingID),
                        "\(day.date) \(block.label) points at '\(readingID)'"
                    )
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 100, "the plan barely references any readings")
    }

    func testScheduleBlockReadingIDDecodes() throws {
        let json = """
        {
          "start": "06:00",
          "label": "D3: B5-M4 Asset Manager Code of Professional Conduct",
          "minutes": 120,
          "kind": "deep3",
          "book": 5,
          "reading_id": "asset_manager_code_of_professional_conduct"
        }
        """.data(using: .utf8)!
        let block = try JSONDecoder().decode(ScheduleBlock.self, from: json)
        XCTAssertEqual(block.readingID, "asset_manager_code_of_professional_conduct")
        XCTAssertEqual(block.book, 5)
    }

    func testScheduleBlockTitlesDropProductionCodes() {
        XCTAssertEqual(
            StudyDisplay.stripPlanCode("D3: B1-M1 Capital Market Expectations I"),
            "Capital Market Expectations I"
        )
        XCTAssertEqual(
            StudyDisplay.stripPlanCode("MM Video: B4-M2 Swaps, Forwards & Futures"),
            "Swaps, Forwards & Futures"
        )
        XCTAssertEqual(
            StudyDisplay.stripPlanCode("MM Q: B2-M1 Overview of Equity PM"),
            "Overview of Equity PM"
        )
        XCTAssertEqual(StudyDisplay.stripPlanCode("Foster"), "Foster")
    }
}
