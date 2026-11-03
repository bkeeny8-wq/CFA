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

    /// 458.5, not the original 444.0: November 8-30 was rewritten from 38.5
    /// hours of Meldrum video and deep-read blocks into 53 one-hour question
    /// sittings. The day count is unchanged because those 23 days already
    /// existed; only their contents and hours moved.
    ///
    /// Both assertions stay. The declared total and the summed days are
    /// independent, and the split is the only thing that catches a day edit
    /// that forgets the header.
    func testSchedulePins() {
        XCTAssertEqual(schedule.version, 1)
        XCTAssertEqual(schedule.days.count, 230)
        XCTAssertEqual(schedule.totalPlannedHours, 458.5, accuracy: 0.001)
        let summed = schedule.days.reduce(0.0) { $0 + $1.hours }
        XCTAssertEqual(summed, 458.5, accuracy: 0.001)
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
          "question_source": "cfai"
        }
        """.data(using: .utf8)!
        let block = try JSONDecoder().decode(ScheduleBlock.self, from: json)
        XCTAssertEqual(block.questionSource, .other)
        XCTAssertNil(BlockSourceBadge.text(for: .other),
                     "an unknown source is a content bug to leave invisible, not a third badge")
    }

    /// A bundled block covers two readings, and only the first is `reading_id`.
    /// Without `also_covers` the plan would claim to cover 32 readings while
    /// the content covers 36.
    func testBundledEthicsBlocksDeclareBothReadings() throws {
        let november = schedule.days.filter { $0.date >= "2026-11-08" && $0.date <= "2026-11-30" }
        let bundled = november.flatMap(\.blocks).filter { ($0.alsoCovers ?? []).isEmpty == false }
        XCTAssertEqual(bundled.count, 4, "the four paired Ethics sittings")
        for block in bundled {
            XCTAssertEqual(block.readingIDs.count, 2, block.label)
        }

        let covered = Set(november.flatMap(\.blocks).flatMap(\.readingIDs))
        XCTAssertEqual(covered.count, 36, "every reading gets a November sitting")
    }

    /// Scoped to November on purpose. The invariant does NOT hold file-wide:
    /// 56 `CFAI Q:` blocks from December onward are `kind: questions` with no
    /// source, because they predate the app-versus-Meldrum distinction.
    func testNovemberQuestionBlocksAllDeclareASource() {
        let november = schedule.days
            .filter { $0.date >= "2026-11-08" && $0.date <= "2026-11-30" }
            .flatMap(\.blocks)
        XCTAssertEqual(november.count, 53)

        for block in november {
            if block.kind == .questions {
                XCTAssertNotNil(block.questionSource, "unsourced question block: \(block.label)")
                XCTAssertNotEqual(block.questionSource, .other, block.label)
            } else {
                XCTAssertNil(block.questionSource,
                             "\(block.label) is \(block.kind), it has nothing to source")
            }
        }

        let sources = november.compactMap(\.questionSource)
        XCTAssertEqual(sources.filter { $0 == .app }.count, 34)
        XCTAssertEqual(sources.filter { $0 == .mm }.count, 11)
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

    func testAssetManagerCodePlanBlocksOpenTheAMCReading() {
        let amc = "asset_manager_code_of_professional_conduct"
        let blocks = schedule.days.flatMap(\.blocks).filter { $0.label.contains("B5-M4") }
        // 9 since the November rewrite added a sitting on 2026-11-21. This is
        // the SECOND place B5-M4 is counted; the table in
        // testEthicsPlanBlocksOpen2027Modules pins it too, and they have to
        // move together.
        XCTAssertEqual(blocks.count, 9)
        for block in blocks {
            XCTAssertEqual(block.readingID, amc)
            XCTAssertTrue(
                block.label.contains("Asset Manager Code of Professional Conduct"),
                block.label
            )
        }
    }

    /// Note the TRAILING SPACE on the B5-M2 needle. The November rewrite
    /// bundles the eight guidance standards into four sittings labelled
    /// B5-M2a/b/c, and a bare "B5-M2" matches all eleven blocks across four
    /// different reading ids — so the per-block readingID assertion below
    /// would fail three times no matter what count were written here. The
    /// space separates the original "B5-M2 Guidance for Standards I-VII"
    /// blocks from the new suffixed ones.
    ///
    /// B5-M1 still reads 8 by coincidence, not because it was left alone: the
    /// rewrite deleted the 2026-11-30 block and added one on 2026-11-19.
    func testEthicsPlanBlocksOpen2027Modules() {
        let expected: [(needle: String, readingID: String, count: Int)] = [
            ("B5-M1", "code_and_standards", 8),
            ("B5-M2 ", "guidance_standard_i_professionalism", 8),
            ("B5-M2a", "guidance_standard_ii_integrity_capital_markets", 1),
            ("B5-M2b", "guidance_standard_iv_duties_to_employers", 1),
            ("B5-M2c", "guidance_standard_vi_conflicts_of_interest", 1),
            ("B5-M3", "application_of_code_and_standards_l3", 10),
            ("B5-M4", "asset_manager_code_of_professional_conduct", 9),
        ]
        for row in expected {
            let blocks = schedule.days.flatMap(\.blocks).filter { $0.label.contains(row.needle) }
            XCTAssertEqual(blocks.count, row.count, row.needle)
            for block in blocks {
                XCTAssertEqual(block.readingID, row.readingID, block.label)
            }
        }
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
