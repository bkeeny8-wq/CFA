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

    func testDeltaUsesPlannedThroughYesterday() {
        let completions = schedule.days.prefix(6).map {
            DayCompletion(dateKey: $0.date, completedHours: $0.hours)
        }
        let reference = ScheduleDates.parse("2026-07-12")!
        let delta = ScheduleProgress.delta(schedule: schedule, completions: completions, now: reference)
        XCTAssertEqual(delta, 0.0, accuracy: 0.001)
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
    }
}
