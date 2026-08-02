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
        let index = QuizAssembler.readingTopicIndex(content: content)
        var books = Set<String>()
        for bundle in content.losDrillBundles.values {
            for drill in bundle.drills.flatMap(\.questions)
            where drill.type == .mc && drill.correct != nil {
                books.formUnion(index[drill.readingID] ?? [])
            }
        }
        XCTAssertFalse(books.isEmpty)

        // Each returned item fills at least one under-quota book slot, and every
        // book is capped at `quota`, so the whole-curriculum draw can never
        // exceed quota × books.
        XCTAssertGreaterThan(ids.count, 0)
        XCTAssertLessThanOrEqual(ids.count, quota * books.count)
        XCTAssertEqual(Set(ids).count, ids.count)
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
