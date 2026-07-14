import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ClaudeGrader.self) private var grader
    @Environment(PracticeBuilderPreference.self) private var practicePref
    @Environment(ContentLoader.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Query private var attempts: [Attempt]
    @Query private var cards: [ReviewCard]
    @Query private var sessions: [Session]
    @Query private var losStudyStatuses: [LOSStudyStatus]

    @State private var showAPIKeySheet = false
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importSummary: String?

    private var maskedKey: String {
        guard let key = KeychainStore.loadAPIKey() else { return "Not set" }
        return Formatting.maskedAPIKey(key)
    }

    var body: some View {
        List {
            Section("Anthropic") {
                LabeledContent("API key", value: maskedKey)
                Button("Update API key") { showAPIKeySheet = true }
                Picker("Grader model", selection: Bindable(grader).selectedModel) {
                    ForEach(GraderModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
            }

            Section {
                Picker("Question type", selection: Bindable(practicePref).typeFilter) {
                    ForEach(QuestionTypeFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
            } header: {
                Text("Practice")
            } footer: {
                Text("Applies to the Practice builder and due-review sessions from Home. Opening a specific case shows all its questions regardless.")
                    .font(.footnote)
            }

            Section("Data") {
                Button("Export progress JSON") { exportData() }
                Button("Import progress JSON") { showImporter = true }
                if let importSummary {
                    Text(importSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showAPIKeySheet) {
            APIKeySheet()
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportURL.map { ExportDocument(url: $0) },
            contentType: .json,
            defaultFilename: "cfal3-export"
        ) { _ in
            exportURL = nil
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in
            if case .success(let url) = result { importData(from: url) }
        }
    }

    private func exportData() {
        let payload = ExportPayload(
            exportedAt: .now,
            attempts: attempts.map {
                AttemptExport(
                    id: $0.id,
                    questionId: $0.questionId,
                    caseId: $0.caseId,
                    topicId: $0.topicId,
                    timestamp: $0.timestamp,
                    durationSeconds: $0.durationSeconds,
                    selectedOption: $0.selectedOption,
                    wasCorrect: $0.wasCorrect,
                    essayText: $0.essayText,
                    grade: $0.grade,
                    claudeFeedback: $0.claudeFeedback,
                    reasoningText: $0.reasoningText,
                    quality: $0.quality,
                    pointsEarned: $0.pointsEarned,
                    pointsPossible: $0.pointsPossible
                )
            },
            reviewCards: cards.map {
                ReviewCardExport(
                    questionId: $0.questionId,
                    caseId: $0.caseId,
                    topicId: $0.topicId,
                    readingIds: $0.readingIds,
                    losIds: $0.losIds,
                    easeFactor: $0.easeFactor,
                    interval: $0.interval,
                    repetitions: $0.repetitions,
                    dueDate: $0.dueDate,
                    totalAttempts: $0.totalAttempts,
                    totalCorrect: $0.totalCorrect,
                    lastAttemptedAt: $0.lastAttemptedAt,
                    flaggedForReview: $0.flaggedForReview
                )
            },
            sessions: sessions.map {
                SessionExport(
                    id: $0.id,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    mode: $0.mode,
                    filterDescription: $0.filterDescription,
                    attemptIds: $0.attemptIds
                )
            },
            losStudyStatuses: losStudyStatuses.map {
                LOSStudyStatusExport(
                    losId: $0.losId,
                    readingId: $0.readingId,
                    areaId: $0.areaId,
                    state: $0.state,
                    notes: $0.notes,
                    updatedAt: $0.updatedAt
                )
            }
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cfal3-export-\(Int(Date().timeIntervalSince1970)).json")
        do {
            // Default JSONEncoder date strategy — importer mirrors this so old
            // backups remain readable.
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url)
            exportURL = url
            showExporter = true
        } catch {
            // no-op
        }
    }

    private func importData(from url: URL) {
        do {
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            // Match exporter encoding (default `Date` strategy) so existing
            // backup files stay importable.
            let payload = try JSONDecoder().decode(ExportPayload.self, from: data)

            var inserted = 0
            var updated = 0
            var skipped = 0

            let existingAttemptIDs = Set(attempts.map(\.id))
            for item in payload.attempts {
                if existingAttemptIDs.contains(item.id) {
                    skipped += 1
                    continue
                }
                modelContext.insert(Attempt(
                    id: item.id,
                    questionId: item.questionId,
                    caseId: item.caseId,
                    topicId: item.topicId,
                    timestamp: item.timestamp,
                    durationSeconds: item.durationSeconds,
                    selectedOption: item.selectedOption,
                    wasCorrect: item.wasCorrect,
                    essayText: item.essayText,
                    grade: item.grade,
                    claudeFeedback: item.claudeFeedback,
                    reasoningText: item.reasoningText,
                    quality: item.quality,
                    pointsEarned: item.pointsEarned,
                    pointsPossible: item.pointsPossible
                ))
                inserted += 1
            }

            let cardsByQuestion = Dictionary(uniqueKeysWithValues: cards.map { ($0.questionId, $0) })
            for item in payload.reviewCards {
                if let local = cardsByQuestion[item.questionId] {
                    let importedLater = (item.lastAttemptedAt ?? .distantPast)
                        >= (local.lastAttemptedAt ?? .distantPast)
                    if importedLater {
                        local.easeFactor = item.easeFactor
                        local.interval = item.interval
                        local.repetitions = item.repetitions
                        local.dueDate = item.dueDate
                        local.totalAttempts = item.totalAttempts
                        local.totalCorrect = item.totalCorrect
                        local.lastAttemptedAt = item.lastAttemptedAt
                        local.flaggedForReview = item.flaggedForReview
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    let meta = importCardMetadata(for: item)
                    let card = ReviewCard(
                        questionId: item.questionId,
                        caseId: meta.caseId,
                        topicId: meta.topicId,
                        readingIds: meta.readingIds,
                        losIds: meta.losIds
                    )
                    card.easeFactor = item.easeFactor
                    card.interval = item.interval
                    card.repetitions = item.repetitions
                    card.dueDate = item.dueDate
                    card.totalAttempts = item.totalAttempts
                    card.totalCorrect = item.totalCorrect
                    card.lastAttemptedAt = item.lastAttemptedAt
                    card.flaggedForReview = item.flaggedForReview
                    modelContext.insert(card)
                    inserted += 1
                }
            }

            let existingSessionIDs = Set(sessions.map(\.id))
            for item in payload.sessions {
                if existingSessionIDs.contains(item.id) {
                    skipped += 1
                    continue
                }
                modelContext.insert(Session(
                    id: item.id,
                    startedAt: item.startedAt,
                    endedAt: item.endedAt,
                    mode: item.mode,
                    filterDescription: item.filterDescription,
                    attemptIds: item.attemptIds
                ))
                inserted += 1
            }

            let statusesByLOS = Dictionary(uniqueKeysWithValues: losStudyStatuses.map { ($0.losId, $0) })
            for item in payload.losStudyStatuses {
                if let local = statusesByLOS[item.losId] {
                    if item.updatedAt >= local.updatedAt {
                        local.readingId = item.readingId
                        local.areaId = item.areaId
                        local.state = item.state
                        local.notes = item.notes
                        local.updatedAt = item.updatedAt
                        updated += 1
                    } else {
                        skipped += 1
                    }
                } else {
                    modelContext.insert(LOSStudyStatus(
                        losId: item.losId,
                        readingId: item.readingId,
                        areaId: item.areaId,
                        state: LOSStudyState(rawValue: item.state) ?? .notStarted,
                        notes: item.notes,
                        updatedAt: item.updatedAt
                    ))
                    inserted += 1
                }
            }

            try modelContext.save()
            importSummary = "Imported: \(inserted) new, \(updated) updated, \(skipped) skipped"
        } catch {
            modelContext.rollback()
            importSummary = "Import failed: \(error.localizedDescription)"
        }
    }

    private func importCardMetadata(for item: ReviewCardExport) -> (caseId: String, topicId: String, readingIds: [String], losIds: [String]) {
        if let caseId = item.caseId, let topicId = item.topicId {
            return (caseId, topicId, item.readingIds ?? [], item.losIds ?? [])
        }
        if let q = content.question(id: item.questionId),
           let ctx = content.context(for: item.questionId) {
            return (ctx.caseId, ctx.topicId, q.primaryReadingIDs, q.candidateLOS)
        }
        if let drill = content.drillQuestion(id: item.questionId) {
            return (
                DrillAttemptContext.caseId(readingID: drill.readingID),
                drill.areaID,
                [drill.readingID],
                [drill.primaryLOS]
            )
        }
        return (
            item.caseId ?? "imported",
            item.topicId ?? "imported",
            item.readingIds ?? [],
            item.losIds ?? []
        )
    }
}

// MARK: - Export / import payload (shared; mirrors default JSONEncoder date strategy)

private struct ExportPayload: Codable {
    let exportedAt: Date
    let attempts: [AttemptExport]
    let reviewCards: [ReviewCardExport]
    let sessions: [SessionExport]
    let losStudyStatuses: [LOSStudyStatusExport]
}

private struct AttemptExport: Codable {
    let id: UUID
    let questionId: String
    let caseId: String
    let topicId: String
    let timestamp: Date
    let durationSeconds: Int
    let selectedOption: String?
    let wasCorrect: Bool?
    let essayText: String?
    let grade: Int?
    let claudeFeedback: String?
    let reasoningText: String?
    let quality: Int?
    let pointsEarned: Int?
    let pointsPossible: Int?
}

private struct ReviewCardExport: Codable {
    let questionId: String
    let caseId: String?
    let topicId: String?
    let readingIds: [String]?
    let losIds: [String]?
    let easeFactor: Double
    let interval: Int
    let repetitions: Int
    let dueDate: Date
    let totalAttempts: Int
    let totalCorrect: Int
    let lastAttemptedAt: Date?
    let flaggedForReview: Bool
}

private struct SessionExport: Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let mode: String
    let filterDescription: String
    let attemptIds: [UUID]
}

private struct LOSStudyStatusExport: Codable {
    let losId: String
    let readingId: String
    let areaId: String
    let state: String
    let notes: String
    let updatedAt: Date
}

private struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let url: URL

    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnknown)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}
