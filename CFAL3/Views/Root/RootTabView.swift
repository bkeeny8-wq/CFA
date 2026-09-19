import SwiftUI
import SwiftData

/// Browse destinations. A sitting is a full-window cover, not a tab.
enum AppTab: Hashable, CaseIterable, Identifiable {
    case today
    case plan
    case notes
    case practice
    case cases
    case progress

    var id: String { identifier }

    var title: String {
        switch self {
        case .today: return "Today"
        case .plan: return "Plan"
        case .notes: return "Notes"
        case .practice: return "Practice"
        case .cases: return "Cases"
        case .progress: return "Progress"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "calendar"
        case .plan: return "calendar.badge.clock"
        case .notes: return "checklist"
        case .practice: return "target"
        case .cases: return "briefcase"
        case .progress: return "chart.bar"
        }
    }

    /// Sidebar rows are addressed by identifier. UITests used to hunt a
    /// floating iPad tab pill; the chrome changed, the contract did not.
    var identifier: String { "tab.\(title.lowercased())" }
}

struct FlashcardSittingPayload: Identifiable {
    let id = UUID()
    let title: String
    let cards: [Flashcard]
    var dueCount: Int = 0
}

@Observable
final class TabRouter {
    var selected: AppTab = .today
    var showSettings = false
    var questionSitting = false
    var flashcardSitting: FlashcardSittingPayload?

    func presentQuestionSitting() {
        questionSitting = true
    }

    func startQuestions(
        _ coordinator: StudySessionCoordinator,
        ids: [String],
        mode: SessionMode,
        description: String
    ) {
        guard !ids.isEmpty else { return }
        coordinator.start(questionIDs: ids, mode: mode, filterDescription: description)
        presentQuestionSitting()
    }

    func presentFlashcards(title: String, cards: [Flashcard], dueCount: Int = 0) {
        guard !cards.isEmpty else { return }
        flashcardSitting = FlashcardSittingPayload(title: title, cards: cards, dueCount: dueCount)
    }
}

struct RootTabView: View {
    @State private var router = TabRouter()

    var body: some View {
        RootTabContent()
            .environment(router)
            .tint(Theme.pine)
            .preferredColorScheme(.light)
    }
}

private struct RootTabContent: View {
    @Environment(TabRouter.self) private var router
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.storeUnavailable) private var storeUnavailable

    var body: some View {
        @Bindable var router = router

        return HStack(spacing: 0) {
            if horizontalSizeClass == .regular {
                DaybookSidebar()
                    .frame(width: 228)
            }
            destination
        }
        .daybookPaper()
        .safeAreaInset(edge: .top, spacing: 0) {
            if storeUnavailable {
                storeBanner
            }
        }
        .sheet(isPresented: $router.showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { router.showSettings = false }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $router.questionSitting, onDismiss: endQuestionSitting) {
            NavigationStack {
                SessionRunnerView()
            }
            .tint(Theme.pine)
            .preferredColorScheme(.light)
            .daybookPaper()
        }
        .fullScreenCover(item: $router.flashcardSitting) { payload in
            NavigationStack {
                FlashcardSessionView(title: payload.title, cards: payload.cards, dueCount: payload.dueCount)
            }
            .tint(Theme.pine)
            .preferredColorScheme(.light)
            .daybookPaper()
        }
    }

    private var storeBanner: some View {
        Text("This session isn’t saving. Export is disabled until the on-disk store can be opened.")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.copper.opacity(0.22))
            .accessibilityIdentifier("store.unavailable")
    }

    @ViewBuilder
    private var destination: some View {
        switch router.selected {
        case .today:
            NavigationStack { HomeView() }
        case .plan:
            NavigationStack { PlanView() }
        case .notes:
            notesRoot
        case .practice:
            NavigationStack { PracticeBuilderView() }
        case .cases:
            casesRoot
        case .progress:
            NavigationStack { ProgressDashboardView() }
        }
    }

    @ViewBuilder
    private var notesRoot: some View {
        if horizontalSizeClass == .regular {
            StudyPlannerSplitView()
        } else {
            NavigationStack { StudyPlannerView() }
        }
    }

    @ViewBuilder
    private var casesRoot: some View {
        if horizontalSizeClass == .regular {
            BrowseSplitView()
        } else {
            NavigationStack { TopicListView() }
        }
    }

    private func endQuestionSitting() {
        sessionCoordinator.persist(into: modelContext)
        sessionCoordinator.finish()
    }
}

private struct DaybookSidebar: View {
    @Environment(TabRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daybook")
                    .font(Theme.serif(.title2, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Level III workbook")
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                ForEach(AppTab.allCases) { tab in
                    sidebarRow(tab, selected: router.selected == tab) {
                        router.selected = tab
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.sage)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text("B")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.pine)
                    )
                    .accessibilityHidden(true)
                Button {
                    router.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("tab.settings")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.paper)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daybook sidebar")
    }

    private func sidebarRow(_ tab: AppTab, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(tab.title, systemImage: tab.symbol)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selected ? Theme.sage : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab.identifier)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
