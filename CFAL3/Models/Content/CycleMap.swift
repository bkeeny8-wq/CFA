import Foundation

/// The Cycle Map: business cycle → capital market expectations → asset stances
/// → what you actually trade, one phase at a time.
///
/// Mirrors `cycle_map.json` exactly. The content was authored and approved
/// through the content pipeline; corrections arrive as JSON replacements, so
/// nothing here invents, defaults or repairs a value.

/// A `[label, value]` pair, which the JSON writes as a two-element
/// heterogeneous array rather than an object.
struct CycleBar: Decodable, Hashable {
    let label: String
    let value: Double

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        label = try c.decode(String.self)
        value = try c.decode(Double.self)
    }
}

struct CycleGlossaryTerm: Decodable, Hashable {
    let term: String
    let definition: String

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        term = try c.decode(String.self)
        definition = try c.decode(String.self)
    }
}

struct CycleFrameworkStatic: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    let formula: String
    let glossary: [CycleGlossaryTerm]
}

struct CycleCashFramework: Decodable, Hashable {
    let now: Double
    let avg: Double
    let note: String
}

/// Only the two inputs that vary by phase. The rest of Singer-Terhaar is
/// `CycleMap.singerTerhaarInputs`, shared across all five.
struct CycleSingerTerhaarPhase: Decodable, Hashable {
    let rf: Double
    let phi: Double
}

struct CycleSingerTerhaarInputs: Decodable, Hashable {
    let sigma: Double
    let sharpeGIM: Double
    let rho: Double

    enum CodingKeys: String, CodingKey {
        case sigma
        case sharpeGIM = "sharpe_gim"
        case rho
    }
}

/// One phase's numbers for all eight frameworks.
///
/// The keys here do NOT match `frameworks_static`'s ids — `govt_bonds` is
/// `govt`, `dm_equity` is `gk` (Grinold-Kroner), `em_equity` is
/// `singer_terhaar`, `fx_carry` is `fx`. They line up by POSITION, which
/// `CycleMap.frameworkKeyOrder` records so the pairing lives in one place
/// rather than being re-guessed at every call site.
struct CyclePhaseFrameworks: Decodable, Hashable {
    let cash: CycleCashFramework
    let govt: [CycleBar]
    let credit: [CycleBar]
    let gk: [CycleBar]
    let singerTerhaar: CycleSingerTerhaarPhase
    let realEstate: [CycleBar]
    let commodities: [CycleBar]
    let fx: [CycleBar]

    enum CodingKeys: String, CodingKey {
        case cash, govt, credit, gk, commodities, fx
        case singerTerhaar = "singer_terhaar"
        case realEstate = "real_estate"
    }
}

/// The phase-specific half of a move. The reusable half — plain English, the
/// worked numbers, the glossary, the trap and the exam line — is
/// `CycleMap.movesStatic` at the same index.
struct CyclePhaseMove: Decodable, Hashable {
    let name: String
    let what: String
    let readingTag: String
    let how: String
    let why: String

    enum CodingKeys: String, CodingKey {
        case name, what, how, why
        case readingTag = "reading_tag"
    }
}

struct CycleMoveStatic: Decodable, Hashable {
    let plain: String
    let worked: String
    let terms: [CycleGlossaryTerm]
    let trap: String
    let exam: String
}

struct CyclePhase: Decodable, Hashable, Identifiable {
    let name: String
    let description: String
    let curveKind: String
    let curveLabel: String
    let taylor: String
    let frameworks: CyclePhaseFrameworks
    /// "OW", "N" or "UW", one per asset in `CycleMap.assets`.
    let stances: [String]
    /// One per asset, positionally.
    let mechanisms: [String]
    let moves: [CyclePhaseMove]

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, description, taylor, frameworks, stances, mechanisms, moves
        case curveKind = "curve_kind"
        case curveLabel = "curve_label"
    }
}

struct CycleMap: Decodable {
    let version: Int
    let source: String
    let assets: [String]
    /// One per asset, positionally: the transmission chain from policy to price.
    let assetChains: [String]
    /// One per asset, positionally.
    let assetTraps: [String]
    let frameworksStatic: [CycleFrameworkStatic]
    let singerTerhaarInputs: CycleSingerTerhaarInputs
    let movesStatic: [CycleMoveStatic]
    /// "R13" → the reading's title, matched against los_master by exact name.
    let readingLinks: [String: String]
    let phases: [CyclePhase]

    enum CodingKeys: String, CodingKey {
        case version, source, assets, phases
        case assetChains = "asset_chains"
        case assetTraps = "asset_traps"
        case frameworksStatic = "frameworks_static"
        case singerTerhaarInputs = "singer_terhaar_inputs"
        case movesStatic = "moves_static"
        case readingLinks = "reading_links"
    }

    /// `frameworks_static[i]` describes the framework whose per-phase numbers
    /// live under `frameworkKeyOrder[i]`. Recorded once because the two naming
    /// schemes genuinely differ and a positional assumption spread across the
    /// view would be invisible until a framework rendered another's numbers.
    static let frameworkKeyOrder = [
        "cash", "govt", "credit", "gk", "singer_terhaar", "real_estate", "commodities", "fx",
    ]

    /// The bar rows to draw for a framework in a phase.
    ///
    /// Cash and Singer-Terhaar are the two that are not a plain list: cash
    /// carries a now/average pair, and Singer-Terhaar is computed from the
    /// shared inputs and the phase's own rf and phi.
    func bars(frameworkIndex: Int, phase: CyclePhase) -> [CycleBar] {
        guard CycleMap.frameworkKeyOrder.indices.contains(frameworkIndex) else { return [] }
        let f = phase.frameworks
        switch CycleMap.frameworkKeyOrder[frameworkIndex] {
        case "cash":
            return [
                CycleBar(label: "Policy now", value: f.cash.now),
                CycleBar(label: "Expected average", value: f.cash.avg),
            ]
        case "govt": return f.govt
        case "credit": return f.credit
        case "gk": return f.gk
        case "singer_terhaar":
            let i = singerTerhaarInputs
            let integrated = i.rho * i.sigma * i.sharpeGIM
            let segmented = i.sigma * i.sharpeGIM
            let st = f.singerTerhaar
            return [
                CycleBar(label: "RF", value: st.rf),
                CycleBar(label: "φ × RP integrated", value: st.phi * integrated),
                CycleBar(label: "(1−φ) × RP segmented", value: (1 - st.phi) * segmented),
            ]
        case "real_estate": return f.realEstate
        case "commodities": return f.commodities
        case "fx": return f.fx
        default: return []
        }
    }

    /// The note under the bars, where a framework has one.
    func note(frameworkIndex: Int, phase: CyclePhase) -> String? {
        guard CycleMap.frameworkKeyOrder.indices.contains(frameworkIndex) else { return nil }
        switch CycleMap.frameworkKeyOrder[frameworkIndex] {
        case "cash":
            return phase.frameworks.cash.note
        case "singer_terhaar":
            let i = singerTerhaarInputs
            let phi = String(format: "%.2f", phase.frameworks.singerTerhaar.phi)
            return "σ \(Int(i.sigma))%, ρ \(i.rho), Sharpe GIM \(i.sharpeGIM), φ = \(phi). "
                + "Integration falls in stress, so the segmentation slice grows into contraction."
        default:
            return nil
        }
    }
}

extension CycleBar {
    init(label: String, value: Double) {
        self.label = label
        self.value = value
    }
}
