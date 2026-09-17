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

    /// Standards I–VII share the same two templates. Prefix the standard so
    /// the Practice LOS picker and Study checklist can tell the rows apart.
    var displayText: String {
        if let prefix = Self.ethicsStandardPrefix(for: readingID) {
            return "\(prefix) — \(text)"
        }
        return text
    }

    static func ethicsStandardPrefix(for readingID: String) -> String? {
        switch readingID {
        case "guidance_standard_i_professionalism":
            return "I. Professionalism"
        case "guidance_standard_ii_integrity_capital_markets":
            return "II. Integrity of Capital Markets"
        case "guidance_standard_iii_duties_to_clients":
            return "III. Duties to Clients"
        case "guidance_standard_iv_duties_to_employers":
            return "IV. Duties to Employers"
        case "guidance_standard_v_investment_analysis":
            return "V. Investment Analysis, Recommendations, and Actions"
        case "guidance_standard_vi_conflicts_of_interest":
            return "VI. Conflicts of Interest"
        case "guidance_standard_vii_responsibilities":
            return "VII. Responsibilities as a CFA Institute Member or CFA Candidate"
        default:
            return nil
        }
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
