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
    private(set) var schedule: StudySchedule?
    private(set) var loadError: String?

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

    func load() {
        do {
            let bank: QuestionBank = try loadJSON("question_bank")
            let los: LOSMaster = try loadJSON("los_master")
            let summaries: [TopicSummary] = try loadJSON("topics")
            let notes: ReadingNotesBundle = try loadJSON("reading_notes")
            let targets: ContentTargets? = try? loadJSON("content_targets")

            questionBank = bank
            losMaster = los
            topicSummaries = summaries
            readingNotesBundle = notes
            contentTargets = targets

            try loadDrillBundles()

            if let loaded: StudySchedule = try? loadJSON("study_schedule") {
                schedule = loaded
            } else {
                schedule = nil
                #if DEBUG
                print("CFAL3: study_schedule.json failed to decode")
                #endif
            }

            rebuildIndexes(from: bank, los: los, notes: notes)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
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

    func drillBundle(forReading readingID: String) -> LOSDrillBundle? {
        losDrillBundles[readingID]
    }

    func drillQuestion(id: String) -> DrillQuestion? {
        drillQuestionsByID[id]
    }

    func drills(forLOS losID: String) -> [DrillQuestion] {
        drillQuestionsByID.values.filter { $0.primaryLOS == losID }.sorted { $0.number < $1.number }
    }

    func question(id: String) -> Question? { questionsByID[id] }
    func caseStudy(id: String) -> CaseStudy? { casesByID[id] }
    func topic(id: String) -> BankTopic? { topicsByID[id] }
    func los(id: String) -> LOS? { losByID[id] }
    func readingNotes(id: String) -> ReadingNotesEntry? { readingNotesByID[id] }

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

    private func loadJSON<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw ContentLoadError.missingFile(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
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

    private func loadDrillBundles() throws {
        losDrillBundles = [:]
        guard let index: LOSDrillIndex = try? loadJSON("los_drills_index") else { return }

        for entry in index.bundles {
            let bundle: LOSDrillBundle = try loadJSON(entry.filename)
            if let readingID = bundle.readingID {
                losDrillBundles[readingID] = bundle
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
                Text("\(content.totalQuestions) questions · \(content.totalReadingNotes) study notes · \(content.totalDrillQuestions) drills")
            }
        }
        .navigationTitle("Content Stats")
    }
}
