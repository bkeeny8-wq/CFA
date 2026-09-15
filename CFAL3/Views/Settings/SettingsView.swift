import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ClaudeGrader.self) private var grader
    @Environment(ContentLoader.self) private var content
    @Environment(PracticeBuilderPreference.self) private var practicePref
    @Environment(\.modelContext) private var modelContext
    @Query private var attempts: [Attempt]
    @Query private var cards: [ReviewCard]
    @Query private var sessions: [Session]
    @Query private var dayCompletions: [DayCompletion]
    @Query private var losStudyStatuses: [LOSStudyStatus]
    @Query private var flashcardProgress: [FlashcardProgress]

    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importSummary: String?
    @State private var showResetConfirm = false
    @State private var showClearAttemptsConfirm = false
    @State private var resetSummary: String?

    var body: some View {
        List {
            Section {
                Picker("Grader model", selection: Bindable(grader).selectedModel) {
                    ForEach(GraderModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
            } header: {
                Text("Grading")
            } footer: {
                Text("Essay grading runs through your private proxy. Model choice trades speed against depth of feedback.")
            }

            Section {
                Picker("New questions per day", selection: Bindable(practicePref).dailyNewLimit) {
                    ForEach(ReviewQueue.newLimitOptions, id: \.self) { limit in
                        Text(limit == 0 ? "Off" : "\(limit)").tag(limit)
                    }
                }
                LabeledContent("Introduced today") {
                    Text("\(ReviewQueue.introducedToday(attempts: attempts))/\(practicePref.dailyNewLimit)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Picker("New cards per day", selection: Bindable(practicePref).dailyNewFlashcardLimit) {
                    ForEach(FlashcardQueue.newLimitOptions, id: \.self) { limit in
                        Text(limit == 0 ? "Off" : "\(limit)").tag(limit)
                    }
                }
            } header: {
                Text("Review")
            } footer: {
                Text(newPerDayFooter)
            }

            Section {
                Button {
                    exportData()
                } label: {
                    Label("Export progress", systemImage: "square.and.arrow.up")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import progress", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Backups")
            } footer: {
                Text(importSummary ?? "Attempts, review schedule, sessions, and LOS states export as one JSON file. Import merges — newer data wins, nothing is deleted.")
            }

            Section {
                Button(role: .destructive) {
                    showClearAttemptsConfirm = true
                } label: {
                    Label("Clear quiz attempts", systemImage: "arrow.counterclockwise")
                }
                // ReviewCards are seeded for every question at launch, so
                // including them here left both buttons permanently enabled —
                // and a confirmed erase then reported "0 records".
                .disabled(attempts.isEmpty && sessions.isEmpty)

                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Erase all progress", systemImage: "trash")
                }
                // Flashcard rows are seeded like ReviewCards, so only a RATED
                // one counts as progress worth erasing. Without this a
                // Cards-only user found both buttons permanently disabled.
                .disabled(attempts.isEmpty && sessions.isEmpty
                          && dayCompletions.isEmpty && losStudyStatuses.isEmpty
                          && !flashcardProgress.contains { $0.totalAttempts > 0 })
            } header: {
                Text("Reset")
            } footer: {
                Text(resetSummary ?? "“Clear quiz attempts” wipes your attempt history, sessions, and review schedule but keeps LOS study checkmarks and plan check-offs. “Erase all progress” removes everything for a clean slate. Both are permanent — export a backup first if unsure.")
            }

            Section("About") {
                LabeledContent(
                    "Version",
                    value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
                )
                NavigationLink {
                    ContentStatsView()
                } label: {
                    Label("Content stats", systemImage: "books.vertical")
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            GraderConfig.purgeLegacyAPIKey()
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
        .confirmationDialog(
            "Erase all progress?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) { resetAllProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all attempts, the review schedule, sessions, LOS states, and plan check-offs. It cannot be undone.")
        }
        .confirmationDialog(
            "Clear quiz attempts?",
            isPresented: $showClearAttemptsConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear attempts", role: .destructive) { clearQuizAttempts() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your quiz attempts, sessions, and review schedule. Your LOS study checkmarks and plan check-offs are kept. It cannot be undone.")
        }
    }

    /// Explains what the limit does and, when the chosen pace cannot finish
    /// the remaining material before exam day, says so with the rate needed.
    private var newPerDayFooter: String {
        let base = "Questions you've already answered come back on schedule and are never limited. This caps how many brand-new ones enter a review session each day; questions you answer in Practice count toward the same number."
        // Must match ReviewQueue's definition of "seen", or this warning
        // contradicts the count on Home. Attempts count even when
        // totalAttempts is still 0 (grading dismissed backwards).
        let attempted = Set(attempts.map(\.questionId))
        let notStarted = cards.filter {
            $0.totalAttempts == 0 && !attempted.contains($0.questionId)
        }.count
        let days = Formatting.daysUntilExam()
        guard notStarted > 0, days > 0 else { return base }

        let needed = Int(ceil(Double(notStarted) / Double(days)))
        guard practicePref.dailyNewLimit < needed else { return base }
        return base + "\n\nAt this rate you won't reach all \(notStarted.formatted()) unseen questions before the exam — that needs about \(needed)/day over \(days) days."
    }

    /// Clears quiz history only — attempts, sessions, and the (attempt-derived)
    /// review schedule — while preserving LOS study states and plan check-offs.
    private func clearQuizAttempts() {
        // ReviewCards are excluded from the count, not from the delete: one is
        // seeded per question at launch, so counting them would report ~3,115
        // "quiz records" to someone who answered three questions.
        let removed = attempts.count + sessions.count
        for item in attempts { modelContext.delete(item) }
        for item in sessions { modelContext.delete(item) }
        for item in cards { modelContext.delete(item) }
        do {
            try modelContext.save()
            // Re-seed immediately: bootstrapReviewCards only runs once per
            // launch, so without this the app reads "All caught up" over an
            // untouched corpus until the user quits and reopens it.
            content.bootstrapReviewCards(context: modelContext)
            resetSummary = "Cleared \(removed) quiz records. LOS study progress and plan are untouched."
        } catch {
            modelContext.rollback()
            resetSummary = "Clear failed: \(error.localizedDescription)"
        }
    }

    private func resetAllProgress() {
        // Same as above: seeded scheduling rows are erased but not counted —
        // for flashcards that means only the rated ones are user progress.
        let ratedCards = flashcardProgress.filter { $0.totalAttempts > 0 }.count
        let removed = attempts.count + sessions.count
            + dayCompletions.count + losStudyStatuses.count + ratedCards
        for item in attempts { modelContext.delete(item) }
        for item in cards { modelContext.delete(item) }
        for item in sessions { modelContext.delete(item) }
        for item in dayCompletions { modelContext.delete(item) }
        for item in losStudyStatuses { modelContext.delete(item) }
        // "Erase all progress" promises a clean slate; leaving 445 flashcard
        // schedules in place made that promise false.
        for item in flashcardProgress { modelContext.delete(item) }
        do {
            try modelContext.save()
            content.bootstrapReviewCards(context: modelContext)
            content.bootstrapFlashcardProgress(context: modelContext)
            resetSummary = "Erased \(removed) records. Progress is back to a clean slate."
        } catch {
            modelContext.rollback()
            resetSummary = "Reset failed: \(error.localizedDescription)"
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
            },
            dayCompletions: dayCompletions.map {
                DayCompletionExport(dateKey: $0.dateKey,
                                    completedHours: $0.completedHours)
            },
            // Only rated cards: the other 400-odd are seeded scaffolding that
            // the destination device regenerates for itself.
            flashcardProgress: flashcardProgress
                .filter { $0.totalAttempts > 0 }
                .map {
                    FlashcardProgressExport(
                        cardId: $0.cardId,
                        readingId: $0.readingId,
                        areaId: $0.areaId,
                        easeFactor: $0.easeFactor,
                        interval: $0.interval,
                        repetitions: $0.repetitions,
                        dueDate: $0.dueDate,
                        totalAttempts: $0.totalAttempts,
                        totalCorrect: $0.totalCorrect,
                        lastAttemptedAt: $0.lastAttemptedAt,
                        firstAttemptedAt: $0.firstAttemptedAt,
                        flaggedForReview: $0.flaggedForReview
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
            // Was a silent no-op: the button did nothing and said nothing.
            importSummary = "Export failed: \(error.localizedDescription)"
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

            // Same newer-wins merge as review cards. Absent in backups written
            // before flashcards shipped, which is why the field is optional.
            let progressByCard = Dictionary(
                flashcardProgress.map { ($0.cardId, $0) }, uniquingKeysWith: { a, _ in a }
            )
            for item in payload.flashcardProgress ?? [] {
                guard let card = content.flashcard(id: item.cardId) else {
                    skipped += 1
                    continue
                }
                let local = progressByCard[item.cardId] ?? {
                    let row = FlashcardProgress(
                        cardId: item.cardId,
                        readingId: item.readingId ?? card.readingID,
                        areaId: item.areaId ?? card.areaID
                    )
                    modelContext.insert(row)
                    inserted += 1
                    return row
                }()
                let importedLater = (item.lastAttemptedAt ?? .distantPast)
                    >= (local.lastAttemptedAt ?? .distantPast)
                guard importedLater else {
                    skipped += 1
                    continue
                }
                local.easeFactor = item.easeFactor
                local.interval = item.interval
                local.repetitions = item.repetitions
                local.dueDate = item.dueDate
                local.totalAttempts = item.totalAttempts
                local.totalCorrect = item.totalCorrect
                local.lastAttemptedAt = item.lastAttemptedAt
                local.firstAttemptedAt = item.firstAttemptedAt
                local.flaggedForReview = item.flaggedForReview
                updated += 1
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
            // Day completions (plan check-offs): upsert by dateKey.
            if let items = payload.dayCompletions {
                let existing = Dictionary(uniqueKeysWithValues:
                    dayCompletions.map { ($0.dateKey, $0) })
                for item in items {
                    if let row = existing[item.dateKey] {
                        if row.completedHours != item.completedHours {
                            row.completedHours = item.completedHours
                            updated += 1
                        } else { skipped += 1 }
                    } else {
                        modelContext.insert(DayCompletion(
                            dateKey: item.dateKey,
                            completedHours: item.completedHours))
                        inserted += 1
                    }
                }
            }

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
    var dayCompletions: [DayCompletionExport]?
    /// Optional so backups written before flashcards existed still decode.
    var flashcardProgress: [FlashcardProgressExport]?
}

private struct FlashcardProgressExport: Codable {
    let cardId: String
    let readingId: String?
    let areaId: String?
    let easeFactor: Double
    let interval: Int
    let repetitions: Int
    let dueDate: Date
    let totalAttempts: Int
    let totalCorrect: Int
    let lastAttemptedAt: Date?
    let firstAttemptedAt: Date?
    let flaggedForReview: Bool
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

private struct DayCompletionExport: Codable {
    var dateKey: String
    var completedHours: Double
}

struct LOSStudyStatusExport: Codable {
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
