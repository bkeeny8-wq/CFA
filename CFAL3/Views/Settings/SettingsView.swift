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
                .disabled(!ResetScope.hasQuizHistory(attempts: attempts, sessions: sessions))

                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Erase all progress", systemImage: "trash")
                }
                // Flashcard rows are seeded like ReviewCards, so only a RATED
                // one counts as progress worth erasing. Without this a
                // Cards-only user found both buttons permanently disabled.
                .disabled(!ResetScope.hasAnyProgress(
                    attempts: attempts,
                    sessions: sessions,
                    dayCompletions: dayCompletions,
                    losStatuses: losStudyStatuses,
                    flashcards: flashcardProgress
                ))
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

            Section {
                Text("Cards are not a sidebar row. Review the daily mix from Today, or open a reading in Notes to sit that deck. An in-progress sitting hides the sidebar so it cannot dump the sitting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Accessibility")
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
        // seeded per question at launch, so counting them would report ~3,164
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
        // "Erase all progress" promises a clean slate; leaving every seeded
        // flashcard schedule in place made that promise false.
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
        let payload = ProgressBackup.payload(
            attempts: attempts,
            cards: cards,
            sessions: sessions,
            losStudyStatuses: losStudyStatuses,
            dayCompletions: dayCompletions,
            flashcardProgress: flashcardProgress
        )
        do {
            exportURL = try ProgressBackup.write(payload)
            showExporter = true
        } catch {
            importSummary = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importData(from url: URL) {
        do {
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            let payload = try ProgressBackup.decode(from: url)

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
