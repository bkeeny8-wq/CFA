import SwiftUI
import SwiftData

/// Two-pane case library. Nested `NavigationSplitView` inside the Daybook
/// sidebar ate the books column, so Ethics never appeared in the a11y tree.
struct BrowseSplitView: View {
    @Environment(ContentLoader.self) private var content
    @Query private var attempts: [Attempt]

    @State private var selectedTopicID: String?
    @State private var selectedCaseID: String?

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                booksColumn
                    .frame(width: 320)
                Rectangle()
                    .fill(Theme.pine.opacity(0.1))
                    .frame(width: 1)
                    .ignoresSafeArea()
                casesColumn
            }
            .background(Theme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: showCaseDetail) {
                if let selectedCaseID {
                    CaseDetailView(caseID: selectedCaseID)
                }
            }
        }
        .onAppear {
            seedTopicIfNeeded()
        }
        .onChange(of: selectedTopicID) { _, _ in
            selectedCaseID = nil
        }
    }

    private var showCaseDetail: Binding<Bool> {
        Binding(
            get: { selectedCaseID != nil },
            set: { if !$0 { selectedCaseID = nil } }
        )
    }

    @ViewBuilder
    private var booksColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cases")
                    .font(Theme.serif(.largeTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("cases.library")
                Text("Open a case to read its vignette, then sit its questions as one timed set.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dust)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if let error = content.loadError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Theme.copper)
                    .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(content.questionBank?.topics ?? []) { topic in
                            bookRow(topic)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Theme.paper)
    }

    private func bookRow(_ topic: BankTopic) -> some View {
        let progress = ProgressStats.caseProgress(topic: topic, attempts: attempts)
        let name = ProgressDisplay.shortName(topic.id, fallback: topic.shortName)
        let selected = selectedTopicID == topic.id

        return Button {
            selectedTopicID = topic.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(name)
                        .font(Theme.serif(.headline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if let weight = ProgressDisplay.examWeights[topic.id] {
                        CapsuleBadge(text: weight)
                    }
                }
                Text("\(progress.total) case questions · \(Formatting.percent(progress.correctRate)) correct")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dust)
                MasteryBar(value: progress.total == 0 ? 0 : Double(progress.attempted) / Double(progress.total))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Theme.sage : Theme.cardFill)
                    .shadow(color: Color.black.opacity(selected ? 0 : 0.04), radius: 8, y: 3)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cases.book.\(name)")
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var casesColumn: some View {
        if let topicID = selectedTopicID, content.topic(id: topicID) != nil {
            CaseListView(
                topicID: topicID,
                hidesNavigationChrome: true,
                selectionMode: true,
                selectedCaseID: $selectedCaseID,
                onCaseSelected: { selectedCaseID = $0 }
            )
        } else {
            ContentUnavailableView(
                "Select a book",
                systemImage: "folder",
                description: Text("Choose a book to browse its cases.")
            )
            .foregroundStyle(Theme.dust)
        }
    }

    private func seedTopicIfNeeded() {
        guard selectedTopicID == nil,
              let first = content.questionBank?.topics.first else { return }
        selectedTopicID = first.id
    }
}
