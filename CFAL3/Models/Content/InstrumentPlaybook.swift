import Foundation

/// Pro, con, when to recommend and what the vignette is signalling, for every
/// instrument the curriculum covers.
///
/// Mirrors `instrument_playbook.json`. Unlike the notes, the Meldrum PDFs and
/// the cycle map, this content is GENERATED rather than supplied, which is why
/// every point carries a `source` and every instrument a `confidence`: the
/// reader can see which claims came from their own notes and which are standard
/// curriculum material written to fill a gap.
struct InstrumentPlaybook: Decodable {
    let version: Int
    let source: String
    /// Family order as shown. Comes from the file so the UI does not hardcode
    /// a taxonomy that the content might outgrow.
    let families: [String]
    let instruments: [PlaybookInstrument]

    func instrument(_ key: String) -> PlaybookInstrument? {
        instruments.first { $0.key == key }
    }

    func instruments(inFamily family: String) -> [PlaybookInstrument] {
        instruments.filter { $0.family == family }
    }

    /// Families that actually have instruments, in file order. Guards against a
    /// family heading rendering above an empty list.
    var populatedFamilies: [String] {
        families.filter { !instruments(inFamily: $0).isEmpty }
    }
}

/// A point with its provenance.
///
/// `source` is a reading id when the candidate's own notes already said it, and
/// the literal "curriculum" when it is standard material added because the
/// notes were thin on that instrument. The distinction is shown, not hidden.
struct PlaybookPoint: Decodable, Hashable {
    let text: String
    let source: String

    var isFromNotes: Bool { source != "curriculum" }
}

/// What a vignette plants, and what it rules in or out.
///
/// The highest-value field in an entry: exam questions carry constraints that
/// silently eliminate instruments, and recognising the constraint is most of
/// the work. "The IPS prohibits counterparty exposure" rules out every OTC
/// instrument, which is the whole answer to a question that never mentions
/// forwards or swaps.
struct PlaybookCue: Decodable, Hashable {
    let signal: String
    let implication: String
}

struct PlaybookInstrument: Decodable, Identifiable, Hashable {
    let key: String
    let name: String
    let family: String
    let summary: String
    let pros: [PlaybookPoint]
    let cons: [PlaybookPoint]
    let whenToRecommend: [String]
    let whenNotTo: [String]
    let pitfalls: [String]
    let cues: [PlaybookCue]
    /// Keys of siblings a candidate genuinely has to choose between. Drives the
    /// compare selector's suggestions.
    let comparesWith: [String]
    /// "high", "medium" or "low", declared by the author. Shown for anything
    /// below high so the reader knows to check it against the curriculum.
    let confidence: String

    var id: String { key }

    var isHighConfidence: Bool { confidence.lowercased() == "high" }

    /// How much of this entry came from the candidate's own notes rather than
    /// being written to fill a gap. Shown as provenance, not as quality.
    var pointsFromNotes: Int {
        (pros + cons).filter(\.isFromNotes).count
    }

    var totalPoints: Int { pros.count + cons.count }
}
