import SwiftUI
import SwiftData

/// Browse destinations. A sitting is a full-window cover, not a tab.
enum AppTab: Hashable, CaseIterable, Identifiable {
    case today
    case plan
    case notes
    case mmReview
    case cards
    case practice
    case commandWords
    case cases
    case progress

    var id: String { identifier }

    var title: String {
        switch self {
        case .today: return "Today"
        case .plan: return "Plan"
        case .notes: return "Notes"
        case .mmReview: return "MM Review"
        case .cards: return "Cards"
        case .practice: return "Practice"
        case .commandWords: return "Command words"
        case .cases: return "Cases"
        case .progress: return "Progress"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "calendar"
        case .plan: return "calendar.badge.clock"
        case .notes: return "checklist"
        case .mmReview: return "doc.richtext"
        case .cards: return "rectangle.on.rectangle.angled"
        case .practice: return "target"
        case .commandWords: return "character.book.closed"
        case .cases: return "briefcase"
        case .progress: return "chart.bar"
        }
    }

    /// Tab order on a phone, which is not the sidebar's order.
    ///
    /// A phone tab bar shows four before folding the rest into More, and the
    /// phone exists in this plan to do commute legs: 128 of them, all drills
    /// from this app's own bank. So Practice and Cards come forward and the
    /// desk-bound destinations — Notes, MM Review, Cases, Command words — go
    /// to More, where reaching them costs a tap you would only pay sitting
    /// down. The sidebar keeps `allCases` order, which is the reading order.
    static let compactOrder: [AppTab] = [
        .today, .practice, .cards, .plan,
        .notes, .progress, .cases, .commandWords, .mmReview,
    ]

    /// Sidebar rows are addressed by identifier. UITests used to hunt a
    /// floating iPad tab pill; the chrome changed, the contract did not.
    ///
    /// Derived from the title, but a title with a space in it would produce
    /// "tab.mm review" — an identifier no sane test wants to type. Spaces
    /// collapse, so MM Review is addressed as "tab.mmreview".
    var identifier: String {
        "tab.\(title.lowercased().replacingOccurrences(of: " ", with: ""))"
    }
}

struct FlashcardSittingPayload: Identifiable {
    let id = UUID()
    let title: String
    let cards: [Flashcard]
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

    func presentFlashcards(title: String, cards: [Flashcard]) {
        guard !cards.isEmpty else { return }
        flashcardSitting = FlashcardSittingPayload(title: title, cards: cards)
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
    @Environment(LeftColumnPreference.self) private var leftColumns
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.storeUnavailable) private var storeUnavailable

    /// The sidebar only exists at regular width, so at compact width there is
    /// nothing to offer a control for.
    private var sidebarApplies: Bool { horizontalSizeClass == .regular }

    /// Outermost column first: the sidebar, then whatever inner column the
    /// destination on screen registered.
    private var barColumns: [LeftColumnSpec] {
        (sidebarApplies ? [.sidebar] : []) + leftColumns.innerColumns
    }

    /// 228pt at the default text size, growing with it.
    ///
    /// A fixed 228 truncated six of the nine destinations at accessibility
    /// sizes - "Pra...", "Ca...", "Pro..." - and "Cards" and "Cases" became
    /// indistinguishable from each other. Capped so the sidebar cannot eat the
    /// page it is navigating.
    @ScaledMetric(relativeTo: .subheadline) private var scaledSidebarWidth: CGFloat = 228
    private var sidebarWidth: CGFloat { min(scaledSidebarWidth, 360) }

    var body: some View {
        @Bindable var router = router

        return Group {
            if sidebarApplies {
                shell
            } else {
                compactShell
            }
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
                FlashcardSessionView(title: payload.title, cards: payload.cards)
            }
            .tint(Theme.pine)
            .preferredColorScheme(.light)
            .daybookPaper()
        }
    }

    /// Regular width: the Daybook sidebar beside the page, as before.
    private var shell: some View {
        VStack(spacing: 0) {
            if !barColumns.isEmpty {
                LeftColumnBar(columns: barColumns)
            }
            HStack(spacing: 0) {
                if !leftColumns.isHidden(.sidebar) {
                    DaybookSidebar()
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                destination
            }
        }
    }

    /// Compact width: a tab bar, because there is no room for the sidebar and
    /// without it the nine destinations had no control at all — the phone
    /// build opened on Today with no way to leave it.
    ///
    /// Nine is more than a phone tab bar shows, so iOS folds the overflow into
    /// a More list. That is the conventional behaviour and keeps every
    /// destination reachable; the first four are the ones a commute leg needs.
    ///
    /// Every tab builds its own page rather than only the selected one.
    ///
    /// Building lazily — `if router.selected == tab` with a placeholder
    /// otherwise — looks like an easy win and breaks the More list: iOS pushes
    /// an overflow tab's content inside the More navigation controller without
    /// the selection binding arriving first, so every destination behind More
    /// opened as the placeholder, a blank page with a back chevron. TabView
    /// does not render the tabs you cannot see; let it do that itself.
    private var compactShell: some View {
        @Bindable var router = router

        return TabView(selection: $router.selected) {
            ForEach(AppTab.compactOrder) { tab in
                VStack(spacing: 0) {
                    if !leftColumns.innerColumns.isEmpty {
                        LeftColumnBar(columns: leftColumns.innerColumns)
                    }
                    stack(for: tab)
                }
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .tag(tab)
            }
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

    private var destination: some View {
        stack(for: router.selected)
    }

    /// The page itself, with no navigation chrome around it.
    @ViewBuilder
    private func page(for tab: AppTab) -> some View {
        switch tab {
        case .today: HomeView()
        case .plan: PlanView()
        case .notes: StudyPlannerView()
        case .mmReview: MMReviewView()
        case .cards: FlashcardsHomeView()
        case .practice: PracticeBuilderView()
        case .commandWords: CommandWordsView()
        case .cases: TopicListView()
        case .progress: ProgressDashboardView()
        }
    }

    /// A page in its NavigationStack.
    ///
    /// At compact width this also carries Settings. The sidebar owns that
    /// button at regular width, and the sidebar does not exist on a phone, so
    /// without this Settings is unreachable there.
    private func stack(for tab: AppTab) -> some View {
        NavigationStack {
            page(for: tab)
                .toolbar {
                    if horizontalSizeClass == .compact {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                router.showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("Settings")
                            .accessibilityIdentifier("tab.settings")
                        }
                    }
                }
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
            // The column-control row sits above this now, so the wordmark
            // keeps roughly the height off the top edge that it had before.
            .padding(.top, 8)
            .padding(.bottom, 22)

            // Scrolls rather than squeezing. Nine rows at an accessibility
            // text size are taller than an iPad in portrait, and without this
            // the Spacer collapsed first and then the rows compressed until
            // their labels truncated, with Settings cut off at the bottom
            // edge.
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(AppTab.allCases) { tab in
                        sidebarRow(tab, selected: router.selected == tab) {
                            router.selected = tab
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

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
                // Wrap, never truncate. "Cards" and "Cases" both truncated to
                // "Ca..." at accessibility sizes, which is worse than a second
                // line: two destinations you cannot tell apart.
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
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
