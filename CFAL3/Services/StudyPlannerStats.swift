import Foundation

struct AreaStudyProgress: Identifiable {
    let areaID: String
    let name: String
    let total: Int
    let mastered: Int
    let reviewing: Int

    var id: String { areaID }

    var masteredFraction: Double {
        total == 0 ? 0 : Double(mastered) / Double(total)
    }
}

struct ReadingStudyProgress: Identifiable {
    let readingID: String
    let name: String
    let total: Int
    let mastered: Int
    let reviewing: Int

    var id: String { readingID }

    var masteredFraction: Double {
        total == 0 ? 0 : Double(mastered) / Double(total)
    }
}

enum StudyPlannerStats {
    static func areaProgress(
        master: LOSMaster,
        statuses: [LOSStudyStatus]
    ) -> [AreaStudyProgress] {
        let byLOS = Dictionary(uniqueKeysWithValues: statuses.map { ($0.losId, $0) })

        return master.areas.map { area in
            let losItems = area.readings.flatMap(\.los)
            let mastered = losItems.filter { byLOS[$0.id]?.studyState == .mastered }.count
            let reviewing = losItems.filter { byLOS[$0.id]?.studyState == .reviewing }.count
            return AreaStudyProgress(
                areaID: area.id,
                name: area.name,
                total: losItems.count,
                mastered: mastered,
                reviewing: reviewing
            )
        }
    }

    static func readingProgress(
        reading: Reading,
        statuses: [LOSStudyStatus]
    ) -> ReadingStudyProgress {
        let byLOS = Dictionary(uniqueKeysWithValues: statuses.map { ($0.losId, $0) })
        let mastered = reading.los.filter { byLOS[$0.id]?.studyState == .mastered }.count
        let reviewing = reading.los.filter { byLOS[$0.id]?.studyState == .reviewing }.count
        return ReadingStudyProgress(
            readingID: reading.id,
            name: reading.name,
            total: reading.los.count,
            mastered: mastered,
            reviewing: reviewing
        )
    }

    static func overall(
        master: LOSMaster,
        statuses: [LOSStudyStatus]
    ) -> (mastered: Int, reviewing: Int, total: Int) {
        let total = master.losFlat.count
        let byLOS = Dictionary(uniqueKeysWithValues: statuses.map { ($0.losId, $0) })
        let mastered = master.losFlat.filter { byLOS[$0.id]?.studyState == .mastered }.count
        let reviewing = master.losFlat.filter { byLOS[$0.id]?.studyState == .reviewing }.count
        return (mastered, reviewing, total)
    }

    static func questionStats(
        losID: String,
        content: ContentLoader,
        attempts: [Attempt]
    ) -> (attempted: Int, correctRate: Double?) {
        let questionIDs = content.questions(matchingLOS: [losID])
        guard !questionIDs.isEmpty else { return (0, nil) }
        let relevant = attempts.filter { questionIDs.contains($0.questionId) }
        let unique = Set(relevant.map(\.questionId)).count
        let gradable = relevant.filter { $0.wasCorrect != nil }
        let rate: Double? = gradable.isEmpty
            ? nil
            : Double(gradable.filter { $0.wasCorrect == true }.count) / Double(gradable.count)
        return (unique, rate)
    }
}
