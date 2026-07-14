import Foundation

struct ContentTargets: Codable {
    let version: Int
    let description: String
    let grandTotal: GrandTotal
    let essayShare: Double
    let areas: [ContentTargetArea]
    let readings: [ContentTargetReading]

    enum CodingKeys: String, CodingKey {
        case version, description, areas, readings
        case grandTotal = "grand_total"
        case essayShare = "essay_share"
    }
}

struct GrandTotal: Codable {
    let total: Int
    let mc: Int
    let essay: Int
    let readings: Int
}

struct ContentTargetArea: Codable, Identifiable {
    let id: String
    let name: String
    let examWeight: String
    let total: Int
    let mc: Int
    let essay: Int
    let readings: Int
    let avgPerReading: Int

    enum CodingKeys: String, CodingKey {
        case id, name, total, mc, essay, readings
        case examWeight = "exam_weight"
        case avgPerReading = "avg_per_reading"
    }
}

struct ContentTargetReading: Codable, Identifiable {
    var id: String { readingID }
    let readingID: String
    let readingNumber: Int
    let readingName: String
    let areaID: String
    let losCount: Int
    let targetTotal: Int
    let targetDrillMC: Int
    let targetCaseMC: Int
    let targetEssay: Int

    enum CodingKeys: String, CodingKey {
        case readingID = "reading_id"
        case readingNumber = "reading_number"
        case readingName = "reading_name"
        case areaID = "area_id"
        case losCount = "los_count"
        case targetTotal = "target_total"
        case targetDrillMC = "target_drill_mc"
        case targetCaseMC = "target_case_mc"
        case targetEssay = "target_essay"
    }
}

struct ContentDensityProgress: Identifiable {
    let areaID: String
    let areaName: String
    let examWeight: String
    let haveTotal: Int
    let haveMC: Int
    let haveEssay: Int
    let targetTotal: Int
    let targetMC: Int
    let targetEssay: Int

    var id: String { areaID }

    var totalProgress: Double {
        guard targetTotal > 0 else { return 0 }
        return Double(haveTotal) / Double(targetTotal)
    }
}
