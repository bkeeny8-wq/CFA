import Foundation

/// Resolving the Cycle Map's reading tags, and building the practice pool.
///
/// Kept out of the view because both are name-matching against los_master,
/// which is the kind of thing that fails silently: an unresolvable tag renders
/// a dead badge and an empty pool disables the CTA, and neither is visible
/// without a test that walks the real bundle.
enum CycleMapLinks {

    /// The reading a `reading_tag` ("R13") points at, with the book it lives
    /// in — the pair `StudyReadingDetailView` needs.
    ///
    /// `reading_links` maps a tag to a reading TITLE, matched against
    /// los_master by exact name, so a retitled reading breaks the link rather
    /// than silently opening the wrong one.
    static func reading(
        forTag tag: String,
        map: CycleMap,
        content: ContentLoader
    ) -> (area: CurriculumArea, reading: Reading)? {
        guard let title = map.readingLinks[tag], let master = content.losMaster else { return nil }
        for area in master.areas {
            if let match = area.readings.first(where: { $0.name == title }) {
                return (area, match)
            }
        }
        return nil
    }

    /// Every reading a phase touches: the readings behind its moves' tags,
    /// plus R1 and R2, which underpin every phase.
    static func readingIDs(
        phase: CyclePhase,
        map: CycleMap,
        content: ContentLoader
    ) -> Set<String> {
        var tags = Set(phase.moves.map(\.readingTag))
        tags.formUnion(["R1", "R2"])
        var ids: Set<String> = []
        for tag in tags {
            if let match = reading(forTag: tag, map: map, content: content) {
                ids.insert(match.reading.id)
            }
        }
        return ids
    }

    /// The LOS ids under those readings.
    static func losIDs(
        phase: CyclePhase,
        map: CycleMap,
        content: ContentLoader
    ) -> Set<String> {
        let readings = readingIDs(phase: phase, map: map, content: content)
        guard let master = content.losMaster else { return [] }
        var ids: Set<String> = []
        for area in master.areas {
            for reading in area.readings where readings.contains(reading.id) {
                ids.formUnion(reading.los.map(\.id))
            }
        }
        return ids
    }

    /// Bank questions whose `candidateLOS` intersects the phase's LOS.
    ///
    /// Returned in sitting order — case by case, question order within a case
    /// — so a phase sitting reads like a paper rather than a shuffle.
    static func practiceQuestionIDs(
        phase: CyclePhase,
        map: CycleMap,
        content: ContentLoader
    ) -> [String] {
        let los = losIDs(phase: phase, map: map, content: content)
        guard !los.isEmpty, let bank = content.questionBank else { return [] }
        var ids: [String] = []
        for topic in bank.topics {
            for caseStudy in topic.cases {
                for question in caseStudy.questions
                where !Set(question.candidateLOS).isDisjoint(with: los) {
                    ids.append(question.id)
                }
            }
        }
        return ids
    }
}
