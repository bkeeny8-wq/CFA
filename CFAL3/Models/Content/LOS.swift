import Foundation

struct LOS: Codable, Identifiable, Hashable {
    let id: String
    let letter: String
    let text: String
    let readingID: String
    let areaID: String

    enum CodingKeys: String, CodingKey {
        case id, letter, text
        case readingID = "reading_id"
        case areaID = "area_id"
    }
}

struct Reading: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let areaID: String
    let los: [LOS]

    enum CodingKeys: String, CodingKey {
        case id, name, los
        case areaID = "area_id"
    }
}

struct CurriculumArea: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let readings: [Reading]
}

struct LOSMaster: Codable {
    let areas: [CurriculumArea]
    let losFlat: [LOS]

    enum CodingKeys: String, CodingKey {
        case areas
        case losFlat = "los_flat"
    }
}
