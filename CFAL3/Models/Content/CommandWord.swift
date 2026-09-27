import Foundation

/// What the answer should look like on the page before a word of it is written:
/// how long to run, how to lay it out, and whether arithmetic or a defended
/// position is part of what gets marked.
struct CommandWordShape: Codable, Hashable {
    let length: String
    let structure: String
    let requiresCalculation: Bool
    let requiresJustification: Bool
}

/// A bank item that answers this command word well, plus why its model answer
/// earns the marks. `kind` is the bank's own question type so a view can hand
/// `id` straight to `ContentLoader.question(id:)` and trust what comes back.
struct CommandWordExample: Codable, Hashable {
    let kind: QuestionType
    let id: String
    let note: String
}

/// A neighbouring command word and the one thing that changes in the answer
/// when the stem says that word instead of this one. `word` always names
/// another entry in the same bundle.
struct CommandWordConfusion: Codable, Hashable {
    let word: String
    let difference: String
}

struct CommandWord: Codable, Identifiable, Hashable {
    let word: String
    /// LOS in `los_master.json` that this verb leads. Derived clause-initially
    /// by `scripts/derive_command_word_counts.py`, which `--check` re-runs
    /// against the shipped value.
    let losCount: Int
    let asking: String
    let highlight: [String]
    let leaveOut: [String]
    let shape: CommandWordShape
    let workedExample: CommandWordExample
    let pointLosers: [String]
    let confusedWith: [CommandWordConfusion]

    var id: String { word }

    /// The JSON stores the verb the way a stem does, in lower case.
    var displayWord: String { word.capitalized }
}

struct CommandWordBundle: Codable {
    let version: Int
    let words: [CommandWord]
}
