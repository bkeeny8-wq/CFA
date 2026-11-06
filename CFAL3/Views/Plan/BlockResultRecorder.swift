import SwiftUI
import SwiftData

/// Recording and reading back what a scheduled sitting scored.
///
/// Kept out of PlanView because the November plan asks two different questions
/// of the same rows: "how did this block go" (the sheet) and "which readings
/// am I worst at" (the readout), and only the second one needs the whole month
/// in scope at once.

// MARK: - Source badge

/// App versus Meldrum, or nothing at all.
///
/// Nil renders as no badge rather than as "app". Only November 2026 blocks
/// carry a source; the 104 earlier `MM Q:` and `CFAI Q:` blocks predate the
/// distinction, and labelling them "app" would be a confident lie about where
/// to go. Pine and copper are the only pair that actually differ — accent,
/// success and sage all resolve to pine.
struct BlockSourceBadge: View {
    let source: ScheduleBlockSource?

    var body: some View {
        if let source, let text = Self.text(for: source) {
            Text(text)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint(for: source).opacity(0.16)))
                .foregroundStyle(tint(for: source))
                .accessibilityLabel(Self.spoken(for: source))
        }
    }

    /// Only pine and copper are genuinely distinct in this palette: accent,
    /// success and sage all resolve to pine. The third bank therefore takes
    /// ink rather than inventing a colour that reads as one of the other two.
    private func tint(for source: ScheduleBlockSource) -> Color {
        switch source {
        case .app: return Theme.pine
        case .mm: return Theme.copper
        case .cfai: return Theme.ink
        case .other: return Theme.dust
        }
    }

    /// `.other` is a decode fallback for a value this build does not know, so
    /// it gets no badge: an unknown source is not a fourth option to show the
    /// reader, it is a content bug to leave invisible.
    static func text(for source: ScheduleBlockSource) -> String? {
        switch source {
        case .app: return "App"
        case .mm: return "MM"
        case .cfai: return "CFAI"
        case .other: return nil
        }
    }

    /// None of these abbreviations are speakable.
    static func spoken(for source: ScheduleBlockSource) -> String {
        switch source {
        case .app: return "Answer in this app"
        case .mm: return "Answer in Mark Meldrum's app"
        case .cfai: return "Answer in the CFA Institute online bank"
        case .other: return "Unknown source"
        }
    }
}

// MARK: - Recording sheet

/// Typing in what a sitting scored.
///
/// Manual entry is not a shortcut. Eleven November sittings happen in
/// Meldrum's app and can never produce an `Attempt`, so for those readings
/// this form is the only record that will ever exist.
struct BlockResultSheet: View {
    let dateKey: String
    let block: ScheduleBlock
    let existing: ScheduleBlockResult?
    let onSave: (ScheduleBlockResult) -> Void
    let onDelete: (ScheduleBlockResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ContentLoader.self) private var content

    @State private var attempted = ""
    @State private var correct = ""
    @State private var pointsEarned = ""
    @State private var pointsPossible = ""
    @State private var ranOutOfTime = false
    @State private var confidence: Int?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(StudyDisplay.scheduleBlockTitle(block, content: content))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        Text("\(block.start) · \(block.minutes)m")
                            .font(.caption)
                            .foregroundStyle(Theme.dust)
                        BlockSourceBadge(source: block.questionSource)
                    }
                    if block.questionSource?.isMeldrum == true {
                        Text("Answered in Meldrum's app, so nothing reached this one. "
                             + "What you type here is the whole record.")
                            .font(.caption)
                            .foregroundStyle(Theme.dust)
                    }
                }

                Section("Multiple choice") {
                    numberField("Questions attempted", text: $attempted, id: "attempted")
                    numberField("Correct", text: $correct, id: "correct")
                }

                Section("Essay points") {
                    numberField("Earned", text: $pointsEarned, id: "pointsEarned")
                    numberField("Available", text: $pointsPossible, id: "pointsPossible")
                }

                Section {
                    Toggle("Ran out of time", isOn: $ranOutOfTime)
                        .accessibilityIdentifier("plan.record.ranOutOfTime")
                    confidencePicker
                }

                if let problem {
                    Section {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Theme.copper)
                    }
                }

                if let existing {
                    Section {
                        Button("Delete this result", role: .destructive) {
                            onDelete(existing)
                            dismiss()
                        }
                        .accessibilityIdentifier("plan.record.delete")
                    }
                }
            }
            .navigationTitle(existing == nil ? "Record sitting" : "Edit sitting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("plan.record.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("plan.record.save")
                }
            }
        }
        .accessibilityIdentifier("plan.record.sheet")
        .onAppear(perform: load)
    }

    /// A plain 1 to 5 scale rather than `NamedQualitySelector`. That control is
    /// the SM-2 review rating: its captions read "10m" and "1d", which mean
    /// nothing for a sitting, and bending it would move the flashcard and
    /// question paths to serve this one screen.
    private var confidencePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Confidence")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        confidence = confidence == value ? nil : value
                    } label: {
                        Text("\(value)")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(confidence == value ? Theme.pine : Theme.cardFill)
                            )
                            .foregroundStyle(confidence == value ? .white : Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("plan.record.confidence.\(value)")
                    .accessibilityLabel("Confidence \(value) of 5")
                    .accessibilityAddTraits(confidence == value ? [.isSelected] : [])
                }
            }
            Text("1 guessed, 5 would bet the exam on it. Tap again to clear.")
                .font(.caption2)
                .foregroundStyle(Theme.dust)
        }
    }

    private func numberField(
        _ title: String, text: Binding<String>, id: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .accessibilityIdentifier("plan.record.\(id)")
        }
    }

    private func load() {
        guard let existing else { return }
        attempted = existing.questionsAttempted > 0 ? "\(existing.questionsAttempted)" : ""
        correct = existing.questionsAttempted > 0 ? "\(existing.questionsCorrect)" : ""
        pointsEarned = existing.pointsEarned.map(String.init) ?? ""
        pointsPossible = existing.pointsPossible.map(String.init) ?? ""
        ranOutOfTime = existing.ranOutOfTime
        confidence = existing.confidence
    }

    private func save() {
        let attemptedValue = Int(attempted.trimmingCharacters(in: .whitespaces)) ?? 0
        let correctValue = Int(correct.trimmingCharacters(in: .whitespaces)) ?? 0
        let earned = Int(pointsEarned.trimmingCharacters(in: .whitespaces))
        let possible = Int(pointsPossible.trimmingCharacters(in: .whitespaces))

        // Caught here rather than clamped, because a baseline built from
        // silently corrected numbers is worth less than one you had to retype.
        if correctValue > attemptedValue {
            problem = "More correct (\(correctValue)) than attempted (\(attemptedValue))."
            return
        }
        if let earned, let possible, earned > possible {
            problem = "More points earned (\(earned)) than available (\(possible))."
            return
        }
        if attemptedValue == 0 && earned == nil && confidence == nil {
            problem = "Nothing to record yet. Add a score or a confidence rating."
            return
        }

        let row = existing ?? ScheduleBlockResult(
            key: block.resultKey(on: dateKey),
            dateKey: dateKey,
            blockStart: block.start,
            blockLabel: block.label,
            readingID: block.readingID,
            source: block.questionSource?.rawValue
        )
        row.blockLabel = block.label
        row.readingID = block.readingID
        row.source = block.questionSource?.rawValue
        row.questionsAttempted = attemptedValue
        row.questionsCorrect = correctValue
        row.pointsEarned = earned
        row.pointsPossible = possible
        row.ranOutOfTime = ranOutOfTime
        row.confidence = confidence
        row.recordedAt = .now
        onSave(row)
        dismiss()
    }
}

// MARK: - Baseline readout

/// One reading's November standing.
struct BaselineRow: Identifiable {
    let readingID: String
    let name: String
    let book: Int
    let sources: [ScheduleBlockSource]
    let sessionsPlanned: Int
    let sessionsRecorded: Int
    let attempted: Int
    let correct: Int
    let pointsEarned: Int
    let pointsPossible: Int

    var id: String { readingID }

    var rate: Double? {
        guard attempted > 0 else { return nil }
        return Double(correct) / Double(attempted)
    }

    var essayRate: Double? {
        guard pointsPossible > 0 else { return nil }
        return Double(pointsEarned) / Double(pointsPossible)
    }

    var isMeldrumOnly: Bool { !sources.isEmpty && sources.allSatisfy(\.isMeldrum) }
}

enum BaselineReadout {
    /// Ranks the November readings by what was actually recorded.
    ///
    /// Built from `ScheduleBlockResult` rows ALONE, never mixed with `Attempt`
    /// derived accuracy. Three reasons, each of which would corrupt the
    /// ranking on its own: an app-sourced sitting produces both a row here and
    /// attempts, so adding them double counts it; `losCoverage` keeps only the
    /// latest attempt per question, so a December re-attempt would silently
    /// rewrite the November figure after the fact; and the eleven Meldrum
    /// sittings produce no attempts at all, which would leave holes in exactly
    /// the readings the plan sent elsewhere.
    ///
    /// This is therefore a record of sittings, not the app's accuracy
    /// statistic, and is labelled that way on screen.
    static func rows(
        schedule: StudySchedule,
        results: [ScheduleBlockResult],
        content: ContentLoader,
        from: String = "2026-11-08",
        to: String = "2026-11-30"
    ) -> [BaselineRow] {
        let resultsByKey = Dictionary(
            results.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }
        )

        var planned: [String: Int] = [:]
        var recorded: [String: Int] = [:]
        var sources: [String: [ScheduleBlockSource]] = [:]
        var attempted: [String: Int] = [:]
        var correct: [String: Int] = [:]
        var earned: [String: Int] = [:]
        var possible: [String: Int] = [:]

        for day in schedule.days where day.date >= from && day.date <= to {
            for block in day.blocks {
                // A bundled Ethics block covers two readings; both are credited
                // the sitting, or the plan would claim 32 readings of the 36 it
                // actually touches.
                let readings = block.readingIDs
                guard !readings.isEmpty else { continue }
                let row = resultsByKey[block.resultKey(on: day.date)]
                for readingID in readings {
                    planned[readingID, default: 0] += 1
                    if let source = block.questionSource, source != .other {
                        sources[readingID, default: []].append(source)
                    }
                    guard let row, row.hasScore else { continue }
                    recorded[readingID, default: 0] += 1
                    attempted[readingID, default: 0] += row.questionsAttempted
                    correct[readingID, default: 0] += row.questionsCorrect
                    earned[readingID, default: 0] += row.pointsEarned ?? 0
                    possible[readingID, default: 0] += row.pointsPossible ?? 0
                }
            }
        }

        let rows = planned.keys.compactMap { readingID -> BaselineRow? in
            guard let match = content.reading(id: readingID) else { return nil }
            return BaselineRow(
                readingID: readingID,
                name: StudyDisplay.readingShortTitle(match.reading, content: content),
                book: bookNumber(for: match.area.id),
                sources: Array(Set(sources[readingID] ?? [])).sorted { $0.rawValue < $1.rawValue },
                sessionsPlanned: planned[readingID] ?? 0,
                sessionsRecorded: recorded[readingID] ?? 0,
                attempted: attempted[readingID] ?? 0,
                correct: correct[readingID] ?? 0,
                pointsEarned: earned[readingID] ?? 0,
                pointsPossible: possible[readingID] ?? 0
            )
        }

        // Worst first, then anything still unrecorded, then by name so the
        // order is stable between renders.
        return rows.sorted { lhs, rhs in
            switch (lhs.rate, rhs.rate) {
            case let (l?, r?) where l != r: return l < r
            case (nil, .some): return false
            case (.some, nil): return true
            default: return lhs.name < rhs.name
            }
        }
    }

    /// `los_master` area id to the book number the plan labels use. Nothing in
    /// the app maps these, and `ScheduleBlock.book` cannot be used because the
    /// ranking is keyed on readings, not blocks.
    static func bookNumber(for areaID: String) -> Int {
        switch areaID {
        case "asset_allocation": return 1
        case "portfolio_construction": return 2
        case "performance_measurement": return 3
        case "derivatives_and_risk_management": return 4
        case "ethical_and_professional_standards": return 5
        case "portfolio_management_pathway": return 6
        default: return 0
        }
    }
}

struct BaselineReadoutView: View {
    let rows: [BaselineRow]

    @Environment(\.dismiss) private var dismiss

    private var measured: [BaselineRow] { rows.filter { $0.rate != nil } }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "Nothing recorded yet",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text(
                            "Record a sitting from any November block and it will rank here."
                        )
                    )
                    .accessibilityIdentifier("plan.baseline.empty")
                } else {
                    List {
                        Section {
                            Text("\(measured.count) of \(rows.count) readings measured. "
                                 + "These are the scores you typed in, not the app's own "
                                 + "accuracy figure, so they count Meldrum sittings too.")
                                .font(.footnote)
                                .foregroundStyle(Theme.dust)
                        }
                        Section("Weakest first") {
                            ForEach(rows) { row in
                                readingRow(row)
                            }
                        }
                    }
                }
            }
            .navigationTitle("November baseline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("plan.baseline")
    }

    private func readingRow(_ row: BaselineRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(subtitle(row))
                    .font(.caption2)
                    .foregroundStyle(Theme.dust)
            }
            Spacer(minLength: 8)
            if let rate = row.rate {
                Text(rate.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(rate < 0.6 ? Theme.copper : Theme.pine)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dust)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.baseline.row.\(row.readingID)")
        .accessibilityValue(
            row.rate == nil
                ? "Not recorded"
                : "\(Int((row.rate ?? 0) * 100)) percent, \(row.correct) of \(row.attempted)"
        )
    }

    /// Carries the counts next to the rate on purpose. The readings sent to
    /// Meldrum are the ones whose in-app bank is thinnest, so a bare
    /// percentage sorted ascending reads as a verdict on the candidate when it
    /// is sometimes a verdict on the sample size.
    private func subtitle(_ row: BaselineRow) -> String {
        var parts = ["B\(row.book)"]
        if row.sessionsRecorded < row.sessionsPlanned {
            parts.append("\(row.sessionsRecorded)/\(row.sessionsPlanned) sittings recorded")
        }
        if row.attempted > 0 {
            parts.append("\(row.correct)/\(row.attempted) MC")
        }
        if let essay = row.essayRate {
            parts.append("essays \(essay.formatted(.percent.precision(.fractionLength(0))))")
        }
        if row.isMeldrumOnly {
            parts.append("Meldrum only")
        }
        return parts.joined(separator: " · ")
    }
}
