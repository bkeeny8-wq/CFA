import SwiftUI

/// Five tabs, deliberately. Seven sections have to fit, so two are folded:
/// - Cards joins Study, which already navigates book → reading the same way;
///   a bar along the bottom of that tab switches between notes and cards.
/// - Progress is reached by tapping Home's stats, which already show accuracy,
///   attempted, streak and days-to-exam. The dashboard is their drill-down.
///
/// Keeping the count at five also keeps every tab visible: past a handful, the
/// bar stops showing them all and buries the overflow.
enum AppTab: Hashable {
    case home
    case plan
    case study
    case practice
    case vignettes

    var title: String {
        switch self {
        case .home: return "Home"
        case .plan: return "Plan"
        case .study: return "Study"
        case .practice: return "Practice"
        case .vignettes: return "Vignettes"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .plan: return "calendar"
        case .study: return "checklist"
        case .practice: return "square.and.pencil"
        case .vignettes: return "doc.richtext"
        }
    }

    /// Tabs are addressed by identifier rather than by chrome type, because
    /// the chrome is not stable: on iPad this bar is a floating pill at the
    /// TOP of the window and exposes no `TabBar` element at all — the items
    /// are bare buttons in an untyped container, so `app.tabBars` finds
    /// nothing. Left unset, each item's identifier defaults to its SF Symbol
    /// name, which is an implementation detail, not a contract.
    var identifier: String { "tab.\(title.lowercased())" }
}

/// Lets a screen send the user to another TAB instead of pushing a second copy
/// of it. Home's plan card used to push its own PlanView while Plan also
/// existed elsewhere, so the same screen could be open twice with separate
/// scroll positions.
@Observable
final class TabRouter {
    var selected: AppTab = .home

    /// Bumped when an already-selected tab is tapped again, which pops that
    /// tab's stack. Without it, going deep into a case leaves no one-tap way
    /// back to the tab's own root.
    var popToRootToken = 0
}

struct RootTabView: View {
    @State private var router = TabRouter()

    var body: some View {
        RootTabContent()
            .environment(router)
            .tint(Theme.accent)
    }
}

private struct RootTabContent: View {
    @Environment(TabRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Re-tapping the current tab means "take me back to the top of it".
    private var selection: Binding<AppTab> {
        Binding(
            get: { router.selected },
            set: { tapped in
                if tapped == router.selected { router.popToRootToken &+= 1 }
                router.selected = tapped
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            NavigationStack {
                HomeView()
            }
            .id(router.selected == .home ? router.popToRootToken : -1)
            .tabItem { tabLabel(.home) }
            .tag(AppTab.home)

            NavigationStack {
                PlanView()
            }
            .tabItem { tabLabel(.plan) }
            .tag(AppTab.plan)

            StudyRootView()
                .id(router.selected == .study ? router.popToRootToken : -1)
                .tabItem { tabLabel(.study) }
                .tag(AppTab.study)

            NavigationStack {
                PracticeBuilderView()
            }
            .tabItem { tabLabel(.practice) }
            .tag(AppTab.practice)

            vignettesRoot
                .id(router.selected == .vignettes ? router.popToRootToken : -1)
                .tabItem { tabLabel(.vignettes) }
                .tag(AppTab.vignettes)
        }
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.symbol)
            .accessibilityIdentifier(tab.identifier)
    }

    /// Case studies and their AI-graded essays, lifted out of Practice into
    /// their own tab — inside Practice, pushing into a case hid the switcher
    /// and left no visible way back to the quiz builder.
    @ViewBuilder
    private var vignettesRoot: some View {
        if horizontalSizeClass == .regular {
            BrowseSplitView()
        } else {
            NavigationStack {
                TopicListView()
            }
        }
    }
}
