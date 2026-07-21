import Foundation

enum ProgressDisplay {
    static let examWeights: [String: String] = [
        "asset_allocation": "15–20%",
        "portfolio_construction": "15–20%",
        "performance_measurement": "5–10%",
        "derivatives_and_risk_management": "10–15%",
        "ethical_and_professional_standards": "10–15%",
        "portfolio_management_pathway": "30–35%",
    ]

    static let shortNames: [String: String] = [
        "asset_allocation": "Asset allocation",
        "portfolio_construction": "Portfolio constr.",
        "performance_measurement": "Perf. measurement",
        "derivatives_and_risk_management": "Derivatives",
        "ethical_and_professional_standards": "Ethics",
        "portfolio_management_pathway": "PM pathway",
    ]

    static func shortName(_ id: String, fallback: String) -> String {
        shortNames[id] ?? fallback
    }
}
