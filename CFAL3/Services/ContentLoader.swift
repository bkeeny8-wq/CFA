import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
final class ContentLoader {
    private(set) var questionBank: QuestionBank?
    private(set) var losMaster: LOSMaster?
    private(set) var topicSummaries: [TopicSummary] = []
    private(set) var readingNotesBundle: ReadingNotesBundle?
    private(set) var contentTargets: ContentTargets?
    private(set) var losDrillBundles: [String: LOSDrillBundle] = [:]
    private(set) var flashcardBundle: FlashcardBundle?
    private(set) var schedule: StudySchedule?
    private(set) var mmReview: MMReviewBundle?
    private(set) var loadError: String?

    private var flashcardsByID: [String: Flashcard] = [:]
    private var flashcardsByReading: [String: [Flashcard]] = [:]

    private var questionsByID: [String: Question] = [:]
    private var drillQuestionsByID: [String: DrillQuestion] = [:]
    private var casesByID: [String: CaseStudy] = [:]
    private var topicsByID: [String: BankTopic] = [:]
    private var losByID: [String: LOS] = [:]
    private var readingNotesByID: [String: ReadingNotesEntry] = [:]
    private var questionContext: [String: (caseId: String, topicId: String)] = [:]

    var isLoaded: Bool { questionBank != nil }

    var totalQuestions: Int { questionBank?.totalQuestions ?? 0 }
    var totalTopics: Int { questionBank?.topics.count ?? 0 }
    var totalReadingNotes: Int { readingNotesByID.count }
    var totalDrillQuestions: Int { drillQuestionsByID.count }

    /// Every question a session or a review card can draw from: the case bank
    /// plus the LOS drills. This is the universe `bootstrapReviewCards` spans
    /// and the one an Attempt's questionId comes from, so it — not the
    /// bank-only `totalQuestions` — is the denominator for "attempted".
    var totalBankAndDrillQuestions: Int { totalQuestions + totalDrillQuestions }

    /// Tests and anything that already owns the main actor keep the sync path.
    func load() {
        do {
            apply(try Self.decodeSnapshot())
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Decode the ~9 MB bundle off the main actor, then publish ON it.
    ///
    /// The hop back is explicit and load-bearing. `ContentLoader` carries no
    /// actor isolation, so this `async` method resumes on the cooperative
    /// pool, not on the main actor — which meant `apply` rebuilt all seven
    /// lookup dictionaries on a background thread while SwiftUI was reading
    /// them on the main one. `rebuildIndexes` empties each dictionary before
    /// refilling it, so a view reading `drillQuestionsByID` during that window
    /// saw a half-built table and crashed inside `Dictionary._Variant.lookup`
    /// with `doesNotRecognizeSelector`. Eleven crash reports over two days,
    /// all with the same stack: HomeView.body -> ReviewQueue.plan ->
    /// ContentLoader.drillQuestion(id:).
    ///
    /// Verified rather than assumed: logging `Thread.isMainThread` from
    /// `apply` printed NO before this change and YES after.
    func loadOffMainActor() async {
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try ContentLoader.decodeSnapshot()
            }.value
            await MainActor.run {
                apply(snapshot)
                loadError = nil
            }
        } catch {
            let message = error.localizedDescription
            await MainActor.run { loadError = message }
        }
    }

    func bootstrapReviewCards(context: ModelContext) {
        guard let bank = questionBank else { return }

        let descriptor = FetchDescriptor<ReviewCard>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingIDs = Set(existing.map(\.questionId))

        for topic in bank.topics {
            for caseStudy in topic.cases {
                for question in caseStudy.questions {
                    guard !existingIDs.contains(question.id) else { continue }
                    let card = ReviewCard(
                        questionId: question.id,
                        caseId: caseStudy.id,
                        topicId: topic.id,
                        readingIds: question.primaryReadingIDs,
                        losIds: question.candidateLOS
                    )
                    context.insert(card)
                }
            }
        }

        for drill in drillQuestionsByID.values {
            guard !existingIDs.contains(drill.id) else { continue }
            let card = ReviewCard(
                questionId: drill.id,
                caseId: DrillAttemptContext.caseId(readingID: drill.readingID),
                topicId: drill.areaID,
                readingIds: [drill.readingID],
                losIds: [drill.primaryLOS]
            )
            context.insert(card)
        }
        try? context.save()
    }

    // MARK: - Decode

    private struct ContentSnapshot {
        let bank: QuestionBank
        let los: LOSMaster
        let summaries: [TopicSummary]
        let notes: ReadingNotesBundle
        let targets: ContentTargets?
        let drillBundles: [String: LOSDrillBundle]
        let flashcardBundle: FlashcardBundle?
        let schedule: StudySchedule?
        let mmReview: MMReviewBundle?
    }

    private static func decodeSnapshot() throws -> ContentSnapshot {
        let bank: QuestionBank = try decodeJSON("question_bank")
        let los: LOSMaster = try decodeJSON("los_master")
        let summaries: [TopicSummary] = try decodeJSON("topics")
        let notes: ReadingNotesBundle = try decodeJSON("reading_notes")
        let targets: ContentTargets? = try? decodeJSON("content_targets")
        let drillBundles = try decodeDrillBundles()
        let flashcardBundle: FlashcardBundle? = try? decodeJSON("flashcards")
        let schedule: StudySchedule? = try? decodeJSON("study_schedule")
        // Optional in the same sense as flashcards: the manifest is tracked,
        // but the PDFs it indexes are not, so a clone decodes this fine and
        // simply has nothing to open.
        let mmReview: MMReviewBundle? = try? decodeJSON("mm_review")
        #if DEBUG
        if schedule == nil {
            print("CFAL3: study_schedule.json failed to decode")
        }
        #endif
        return ContentSnapshot(
            bank: bank,
            los: los,
            summaries: summaries,
            notes: notes,
            targets: targets,
            drillBundles: drillBundles,
            flashcardBundle: flashcardBundle,
            schedule: schedule,
            mmReview: mmReview
        )
    }

    private static func decodeJSON<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw ContentLoadError.missingFile(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func decodeDrillBundles() throws -> [String: LOSDrillBundle] {
        var bundles: [String: LOSDrillBundle] = [:]
        guard let index: LOSDrillIndex = try? decodeJSON("los_drills_index") else { return [:] }
        for entry in index.bundles {
            let bundle: LOSDrillBundle = try decodeJSON(entry.filename)
            if let readingID = bundle.readingID {
                bundles[readingID] = bundle
            }
        }
        return bundles
    }

    private func apply(_ snapshot: ContentSnapshot) {
        // Everything below replaces the lookup dictionaries wholesale, and
        // every reader of them is a SwiftUI view on the main thread. Publishing
        // from anywhere else is the race that produced eleven launch crashes.
        assert(Thread.isMainThread, "ContentLoader.apply must publish on the main thread")
        questionBank = snapshot.bank
        losMaster = snapshot.los
        topicSummaries = snapshot.summaries
        readingNotesBundle = snapshot.notes
        contentTargets = snapshot.targets
        losDrillBundles = snapshot.drillBundles
        schedule = snapshot.schedule
        mmReview = snapshot.mmReview
        applyFlashcards(snapshot.flashcardBundle)
        rebuildIndexes(from: snapshot.bank, los: snapshot.los, notes: snapshot.notes)
    }

    /// Flashcards are optional content: a build without the bundle simply shows
    /// an empty Cards tab rather than failing the whole content load.
    private func applyFlashcards(_ bundle: FlashcardBundle?) {
        flashcardsByID = [:]
        flashcardsByReading = [:]
        flashcardBundle = bundle
        guard let bundle else { return }
        for card in bundle.cards {
            flashcardsByID[card.id] = card
            flashcardsByReading[card.readingID, default: []].append(card)
        }
    }

    var allFlashcards: [Flashcard] { flashcardBundle?.cards ?? [] }
    var totalFlashcards: Int { flashcardsByID.count }

    func flashcard(id: String) -> Flashcard? { flashcardsByID[id] }

    func flashcards(forReading readingID: String) -> [Flashcard] {
        flashcardsByReading[readingID] ?? []
    }

    func flashcards(forArea areaID: String) -> [Flashcard] {
        allFlashcards.filter { $0.areaID == areaID }
    }

    /// Insert a progress row for every card that does not have one yet, so a
    /// newly added deck shows up as due instead of invisible.
    func bootstrapFlashcardProgress(context: ModelContext) {
        let cards = allFlashcards
        guard !cards.isEmpty else { return }

        let existing = (try? context.fetch(FetchDescriptor<FlashcardProgress>())) ?? []
        let existingIDs = Set(existing.map(\.cardId))
        var inserted = false

        for card in cards where !existingIDs.contains(card.id) {
            context.insert(
                FlashcardProgress(cardId: card.id, readingId: card.readingID, areaId: card.areaID)
            )
            inserted = true
        }
        if inserted { try? context.save() }
    }

    func drillBundle(forReading readingID: String) -> LOSDrillBundle? {
        losDrillBundles[readingID]
    }

    func drillQuestion(id: String) -> DrillQuestion? {
        drillQuestionsByID[id]
    }

    func drills(forLOS losID: String) -> [DrillQuestion] {
        drillQuestionsByID.values.filter { $0.primaryLOS == losID }.sorted { $0.number < $1.number }
    }

    /// Bank essays tagged to this LOS. Empty when the bank has none — callers
    /// must not invent items to fill the gap.
    func essays(forLOS losID: String) -> [Question] {
        questionsByID.values
            .filter { $0.type == .essay && $0.candidateLOS.contains(losID) }
            .sorted {
                let a = questionContext[$0.id]?.caseId ?? ""
                let b = questionContext[$1.id]?.caseId ?? ""
                if a != b { return a < b }
                if $0.number != $1.number { return $0.number < $1.number }
                return $0.id < $1.id
            }
    }

    func question(id: String) -> Question? { questionsByID[id] }
    func caseStudy(id: String) -> CaseStudy? { casesByID[id] }
    func topic(id: String) -> BankTopic? { topicsByID[id] }
    func los(id: String) -> LOS? { losByID[id] }
    func readingNotes(id: String) -> ReadingNotesEntry? { readingNotesByID[id] }

    func reading(id: String?) -> (area: CurriculumArea, reading: Reading)? {
        guard let id, let master = losMaster else { return nil }
        for area in master.areas {
            if let reading = area.readings.first(where: { $0.id == id }) {
                return (area, reading)
            }
        }
        return nil
    }

    func context(for questionId: String) -> (caseId: String, topicId: String)? {
        questionContext[questionId]
    }

    func allQuestionIDs() -> [String] {
        Array(questionsByID.keys)
    }

    func questions(matchingLOS losIDs: Set<String>) -> [String] {
        guard !losIDs.isEmpty else { return allQuestionIDs() }
        return questionsByID.values
            .filter { !Set($0.candidateLOS).isDisjoint(with: losIDs) }
            .map(\.id)
    }

    func cases(forTopic topicID: String, losFilter: Set<String> = []) -> [CaseStudy] {
        guard let topic = topicsByID[topicID] else { return [] }
        guard !losFilter.isEmpty else { return topic.cases }
        return topic.cases.filter { caseStudy in
            caseStudy.questions.contains { question in
                !Set(question.candidateLOS).isDisjoint(with: losFilter)
            }
        }
    }

    private func rebuildIndexes(from bank: QuestionBank, los: LOSMaster, notes: ReadingNotesBundle) {
        questionsByID = [:]
        casesByID = [:]
        topicsByID = [:]
        losByID = [:]
        readingNotesByID = [:]
        drillQuestionsByID = [:]
        questionContext = [:]

        for topic in bank.topics {
            topicsByID[topic.id] = topic
            for caseStudy in topic.cases {
                casesByID[caseStudy.id] = caseStudy
                for question in caseStudy.questions {
                    questionsByID[question.id] = question
                    questionContext[question.id] = (caseStudy.id, topic.id)
                }
            }
        }

        for item in los.losFlat {
            losByID[item.id] = item
        }

        for entry in notes.readings {
            readingNotesByID[entry.readingID] = entry
        }

        for bundle in losDrillBundles.values {
            for group in bundle.drills {
                for question in group.questions {
                    drillQuestionsByID[question.id] = question
                }
            }
        }
    }

}

enum ContentLoadError: LocalizedError {
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name):
            return "Missing bundled file: \(name).json"
        }
    }
}

struct ContentStatsView: View {
    @Environment(ContentLoader.self) private var content

    var body: some View {
        List {
            if let error = content.loadError {
                Text("Load error: \(error)")
            } else {
                // The union, matching every other total in the app — this
                // screen was the last one still advertising the bank's 490.
                Text("\(content.totalBankAndDrillQuestions.formatted()) questions (\(content.totalQuestions.formatted()) case · \(content.totalDrillQuestions.formatted()) drill) · \(content.totalReadingNotes) study notes · \(content.totalFlashcards.formatted()) cards")
            }
        }
        .navigationTitle("Content Stats")
    }
}
