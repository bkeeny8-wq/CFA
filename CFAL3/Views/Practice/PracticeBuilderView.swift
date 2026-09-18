import SwiftUI
import SwiftData

struct PracticeBuilderView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(PracticeBuilderPreference.self) private var pref
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(TabRouter.self) private var router
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]

    @State private var showTopics = false
    @State private var showReadings = false
    @State private var showLOS = false
    @State private var previewedIDs: [String] = []

    private var matching: Int { previewedIDs.count }

    private var unseen: Int {
        let attemptedIDs = Set(attempts.map(\.questionId))
        return previewedIDs.filter { !attemptedIDs.contains($0) }.count
    }

    private var estimatedMinutes: Int {
        let essays = previewedIDs.filter { questionType(for: $0) == .essay }.count
        let mc = matching - essays
        return Formatting.estimatedMinutes(mc: mc, essays: essays)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Practice")
                            .font(Theme.serif(.largeTitle, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("Custom sitting builder. Daily mix lives on Today.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.dust)
                    }
                    Spacer()
                    Button("Reset", role: .destructive) {
                        pref.reset()
                        refreshPreview()
                    }
                    .font(.subheadline.weight(.medium))
                }

                VStack(alignment: .leading, spacing: 16) {
                    Picker("Question type", selection: Bindable(pref).typeFilter) {
                        ForEach(QuestionTypeFilter.allCases) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Source", selection: Bindable(pref).sourceFilter) {
                        ForEach(QuestionSourceFilter.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(perUnitLabel, selection: Bindable(pref).count) {
                        ForEach(PracticeCount.allCases) { count in
                            Text(count.displayName).tag(count)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Weight toward weaker questions", isOn: Bindable(pref).weaknessWeighted)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.cardFill)
                        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scope")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Button {
                        showTopics = true
                    } label: {
                        HStack {
                            Text("Books")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(topicsSummary)
                                .foregroundStyle(Theme.dust)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        showReadings = true
                    } label: {
                        HStack {
                            Text("Readings")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(readingsSummary)
                                .foregroundStyle(Theme.dust)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        showLOS = true
                    } label: {
                        HStack {
                            Text("LOS")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(losSummary)
                                .foregroundStyle(Theme.dust)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Label(
                        scopeSummary,
                        systemImage: "line.3.horizontal.decrease"
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
                    // Combine, or this reads as two elements and the symbol's own
                    // name ("Filter") is what a screen reader announces instead of
                    // the summary.
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(scopeSummary)
                    .accessibilityIdentifier("practice.scopeSummary")
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.cardFill)
                        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
                )
            }
            .padding(24)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if matching == 0 {
                    Text("Widen the book, reading, or LOS filters to find matching items.")
                        .font(.footnote)
                        .foregroundStyle(Theme.dust)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel(
                            "Nothing matches this scope. Widen the book, reading, or LOS filters."
                        )
                }
                Button {
                    startQuiz()
                } label: {
                    Text(matching == 0 ? "Nothing matches this scope" : "Start sitting")
                }
                .buttonStyle(PrimaryCTA())
                .disabled(matching == 0)
            }
            .padding(.horizontal)
            // Match the form above it. The bar stays full width — it is a bar
            // — but a 1000pt-wide button under a 640pt-wide list looked like
            // it belonged to a different screen.
            .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
            .background(Theme.paper)
        }
        .onAppear { refreshPreview() }
        .onChange(of: pref.typeFilter) { _, _ in refreshPreview() }
        .onChange(of: pref.sourceFilter) { _, _ in refreshPreview() }
        .onChange(of: pref.count) { _, _ in refreshPreview() }
        .onChange(of: pref.weaknessWeighted) { _, _ in refreshPreview() }
        .onChange(of: pref.selectedTopics) { _, _ in
            // Narrowing the books narrows what readings/LOS can mean; drop any
            // now-out-of-scope picks so the cascade stays coherent.
            pruneReadingsAndLOS()
            refreshPreview()
        }
        .onChange(of: pref.selectedReadings) { _, _ in
            pruneLOS()
            refreshPreview()
        }
        .onChange(of: pref.selectedLOS) { _, _ in refreshPreview() }
        .sheet(isPresented: $showTopics, onDismiss: refreshPreview) {
            TopicMultiSelectSheet(selection: Bindable(pref).selectedTopics)
        }
        .sheet(isPresented: $showReadings, onDismiss: refreshPreview) {
            ReadingMultiSelectSheet(
                selection: Bindable(pref).selectedReadings,
                scopeTopics: pref.selectedTopics
            )
        }
        .sheet(isPresented: $showLOS, onDismiss: refreshPreview) {
            LOSFilterSheet(
                selectedLOS: Bindable(pref).selectedLOS,
                readingScope: pref.selectedReadings,
                topicScope: pref.selectedTopics
            )
        }
    }

    /// The unit the per-question quota is spread across, tracking the finest
    /// active scope so the "How many" picker reads as e.g. "Per reading".
    private var perUnitNoun: String {
        if !pref.selectedLOS.isEmpty { return "LOS" }
        if !pref.selectedReadings.isEmpty { return "reading" }
        return "book"
    }

    private var perUnitLabel: String { "Questions per \(perUnitNoun)" }

    /// Footer that spells out the scaling: how many per unit, and how many
    /// questions that works out to for the current scope.
    private var scopeSummary: String {
        let tail = "\(matching) questions · \(unseen) unseen · est. \(estimatedMinutes) min"
        guard pref.count != .all else { return "All in scope → " + tail }
        return "\(pref.count.displayName) per \(perUnitNoun) in scope → \(tail)"
    }

    private var topicsSummary: String {
        if pref.selectedTopics.isEmpty { return "All" }
        let n = pref.selectedTopics.count
        return "\(n) book\(n == 1 ? "" : "s")"
    }

    private var readingsSummary: String {
        if pref.selectedReadings.isEmpty { return "All" }
        return "\(pref.selectedReadings.count) readings"
    }

    private var losSummary: String {
        if pref.selectedLOS.isEmpty { return "All" }
        return "\(pref.selectedLOS.count) LOS"
    }

    private func questionType(for id: String) -> QuestionType {
        if let q = content.question(id: id) { return q.type }
        if let d = content.drillQuestion(id: id) { return d.type }
        return .mc
    }

    private func refreshPreview() {
        previewedIDs = QuizAssembler.assemble(pref: pref, content: content, attempts: attempts)
    }

    // MARK: - Cascade pruning

    /// Readings that belong to the selected books (empty selection ⇒ all books).
    private func readingsInScope(topics: Set<String>) -> Set<String> {
        PracticeScope.readings(in: content.losMaster?.areas ?? [], topics: topics)
    }

    /// LOS that belong to the selected readings, or — when no readings are
    /// picked — to the selected books.
    private func losInScope(readings: Set<String>, topics: Set<String>) -> Set<String> {
        PracticeScope.los(
            in: content.losMaster?.areas ?? [],
            readings: readings,
            topics: topics
        )
    }

    /// After the book selection changes, drop readings (and then LOS) that no
    /// longer fall inside the chosen books.
    private func pruneReadingsAndLOS() {
        let kept = PracticeScope.pruned(
            areas: content.losMaster?.areas ?? [],
            topics: pref.selectedTopics,
            readings: pref.selectedReadings,
            los: pref.selectedLOS
        )
        if kept.readings != pref.selectedReadings { pref.selectedReadings = kept.readings }
        if kept.los != pref.selectedLOS { pref.selectedLOS = kept.los }
    }

    /// Drop LOS picks that fall outside the current reading/book scope.
    private func pruneLOS() {
        guard !pref.selectedReadings.isEmpty || !pref.selectedTopics.isEmpty else { return }
        let allowed = losInScope(readings: pref.selectedReadings, topics: pref.selectedTopics)
        let kept = pref.selectedLOS.intersection(allowed)
        if kept != pref.selectedLOS { pref.selectedLOS = kept }
    }

    private func startQuiz() {
        // Start the set the footer counted. `assemble` shuffles, so calling it
        // again here produced a different selection than the one previewed —
        // the builder promised N questions and ran a different N.
        let ids = previewedIDs
        guard !ids.isEmpty else { return }
        sessionCoordinator.start(
            questionIDs: ids,
            mode: .random,
            filterDescription: filterLabel()
        )
        router.presentQuestionSitting()
    }

    private func filterLabel() -> String {
        var parts: [String] = [pref.typeFilter.displayName]
        if pref.sourceFilter != .both { parts.append(pref.sourceFilter.displayName) }
        if !pref.selectedTopics.isEmpty { parts.append("\(pref.selectedTopics.count) topics") }
        if !pref.selectedReadings.isEmpty { parts.append("\(pref.selectedReadings.count) readings") }
        if !pref.selectedLOS.isEmpty { parts.append("\(pref.selectedLOS.count) LOS") }
        if pref.weaknessWeighted { parts.append("weak-weighted") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Topic multi-select

private struct TopicMultiSelectSheet: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<String>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Select all") {
                        selection = Set(content.questionBank?.topics.map(\.id) ?? [])
                    }
                    Button("Clear") { selection.removeAll() }
                }
                Section {
                    ForEach(content.questionBank?.topics ?? [], id: \.id) { topic in
                        toggleRow(id: topic.id, label: topic.shortName)
                    }
                }
            }
            .navigationTitle("Books")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func toggleRow(id: String, label: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if selection.contains(id) {
                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        }
    }
}

// MARK: - Reading multi-select

private struct ReadingMultiSelectSheet: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<String>
    /// When non-empty, only readings from these books are offered.
    var scopeTopics: Set<String> = []

    /// Books (and their readings) in curriculum order, filtered to the chosen
    /// books. Sourced from los_master so every reading has a real title and
    /// sits under the book it belongs to — no raw IDs, no drill/case mixing.
    private var areas: [CurriculumArea] {
        let all = content.losMaster?.areas ?? []
        return scopeTopics.isEmpty ? all : all.filter { scopeTopics.contains($0.id) }
    }

    private var visibleReadingIDs: [String] {
        areas.flatMap { $0.readings.map(\.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Select all") { selection.formUnion(visibleReadingIDs) }
                    Button("Clear") { selection.subtract(visibleReadingIDs) }
                        .disabled(selection.isDisjoint(with: visibleReadingIDs))
                }
                ForEach(areas) { area in
                    Section(area.name) {
                        ForEach(area.readings) { reading in
                            toggleRow(id: reading.id, label: reading.name)
                        }
                    }
                }
            }
            .navigationTitle("Readings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func toggleRow(id: String, label: String) -> some View {
        HStack {
            Text(label).lineLimit(2)
            Spacer()
            if selection.contains(id) {
                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        }
    }
}
