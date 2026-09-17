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

    func testSchedulePins() {
        XCTAssertEqual(schedule.version, 1)
        XCTAssertEqual(schedule.days.count, 230)
        XCTAssertEqual(schedule.totalPlannedHours, 444.0, accuracy: 0.001)
        let summed = schedule.days.reduce(0.0) { $0 + $1.hours }
        XCTAssertEqual(summed, 444.0, accuracy: 0.001)
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
    }

    func testAssetManagerCodePlanBlocksOpenTheAMCReading() {
        let amc = "asset_manager_code_of_professional_conduct"
        let blocks = schedule.days.flatMap(\.blocks).filter { $0.label.contains("B5-M4") }
        XCTAssertEqual(blocks.count, 8)
        for block in blocks {
            XCTAssertEqual(block.readingID, amc)
            XCTAssertTrue(
                block.label.contains("Asset Manager Code of Professional Conduct"),
                block.label
            )
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
}
