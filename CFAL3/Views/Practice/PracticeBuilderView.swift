import SwiftUI
import SwiftData

struct PracticeBuilderView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(PracticeBuilderPreference.self) private var pref
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]

    @State private var showSession = false
    @State private var showTopics = false
    @State private var showReadings = false
    @State private var showLOS = false
    @State private var previewedIDs: [String] = []

    var body: some View {
        List {
            Section {
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
                .pickerStyle(.segmented)

                Picker("How many", selection: Bindable(pref).count) {
                    ForEach(PracticeCount.allCases) { count in
                        Text(count.displayName).tag(count)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Weight toward weaker questions", isOn: Bindable(pref).weaknessWeighted)
            }

            Section("Scope") {
                Button {
                    showTopics = true
                } label: {
                    HStack {
                        Text("Topics")
                        Spacer()
                        Text(pref.selectedTopics.isEmpty ? "All" : "\(pref.selectedTopics.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    showReadings = true
                } label: {
                    HStack {
                        Text("Readings")
                        Spacer()
                        Text(pref.selectedReadings.isEmpty ? "All" : "\(pref.selectedReadings.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    showLOS = true
                } label: {
                    HStack {
                        Text("LOS")
                        Spacer()
                        Text(pref.selectedLOS.isEmpty ? "All" : "\(pref.selectedLOS.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("\(previewedIDs.count) matching question\(previewedIDs.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)

                Button {
                    startQuiz()
                } label: {
                    Text("Start quiz").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(previewedIDs.isEmpty)

                Button("Reset filters", role: .destructive) {
                    pref.reset()
                    refreshPreview()
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
        .frame(maxWidth: .infinity)
        .navigationTitle("Practice")
        .onAppear { refreshPreview() }
        .onChange(of: pref.typeFilter) { _, _ in refreshPreview() }
        .onChange(of: pref.sourceFilter) { _, _ in refreshPreview() }
        .onChange(of: pref.count) { _, _ in refreshPreview() }
        .onChange(of: pref.weaknessWeighted) { _, _ in refreshPreview() }
        .onChange(of: pref.selectedTopics) { _, _ in refreshPreview() }
        .onChange(of: pref.selectedReadings) { _, _ in refreshPreview() }
        .onChange(of: pref.selectedLOS) { _, _ in refreshPreview() }
        .sheet(isPresented: $showTopics, onDismiss: refreshPreview) {
            TopicMultiSelectSheet(selection: Bindable(pref).selectedTopics)
        }
        .sheet(isPresented: $showReadings, onDismiss: refreshPreview) {
            ReadingMultiSelectSheet(selection: Bindable(pref).selectedReadings)
        }
        .sheet(isPresented: $showLOS, onDismiss: refreshPreview) {
            LOSFilterSheet(selectedLOS: Bindable(pref).selectedLOS)
        }
        .navigationDestination(isPresented: $showSession) {
            SessionRunnerView()
        }
    }

    private func refreshPreview() {
        previewedIDs = QuizAssembler.assemble(pref: pref, content: content, attempts: attempts)
    }

    private func startQuiz() {
        let ids = QuizAssembler.assemble(pref: pref, content: content, attempts: attempts)
        guard !ids.isEmpty else { return }
        sessionCoordinator.start(
            questionIDs: ids,
            mode: .random,
            filterDescription: filterLabel()
        )
        showSession = true
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
            .navigationTitle("Topics")
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

    private var readingIDs: [String] {
        var ids = Set<String>()
        if let bank = content.questionBank {
            for topic in bank.topics {
                for caseStudy in topic.cases {
                    for question in caseStudy.questions {
                        ids.formUnion(question.primaryReadingIDs)
                    }
                }
            }
        }
        // LOS drill bundles cover readings the case bank may not touch.
        ids.formUnion(content.losDrillBundles.keys)
        return ids.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Select all") { selection = Set(readingIDs) }
                    Button("Clear") { selection.removeAll() }
                }
                Section {
                    ForEach(readingIDs, id: \.self) { readingID in
                        toggleRow(id: readingID, label: readingLabel(readingID))
                    }
                }
            }
            .navigationTitle("Readings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func readingLabel(_ readingID: String) -> String {
        content.readingNotes(id: readingID)?.title ?? readingID
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
