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

    /// No `.id()` on any tab, deliberately.
    ///
    /// Re-tapping the selected tab used to bump a token that each tab's root
    /// carried as its `.id()`, the intention being "take me back to the top of
    /// this tab". But changing a view's id does not POP it, it DESTROYS it, and
    /// a destroyed tab takes everything inside it along:
    ///
    /// - Study: measured on an iPad, one re-tap during a card session at 2/20
    ///   threw the deck away and returned to the Cards root. Today's allowance
    ///   had already been spent on the rated card, so the same session could
    ///   not even be restarted. This is precisely the loss `StudyRootView`
    ///   mounts both halves to prevent — the token defeated it by another route.
    /// - Vignettes: one re-tap while reading an Ethics case reset the sidebar
    ///   to the FIRST book and the detail pane to "Select a case", silently
    ///   moving the user to a different book.
    ///
    /// The affordance is not worth that. Every pushed screen has a back button,
    /// and since vignettes became their own tab the tab bar is itself always
    /// the way back — which was the complaint the token was added for.
    ///
    /// (An ordinary switch between tabs was never affected: `TabView` does not
    /// re-evaluate a hidden tab's id, so the sentinel never materialised and
    /// state survived. Verified on device before removing this — the damage was
    /// always and only on re-tap.)
    var body: some View {
        @Bindable var router = router

        return TabView(selection: $router.selected) {
            NavigationStack {
                HomeView()
            }
            .tabItem { tabLabel(.home) }
            .tag(AppTab.home)

            NavigationStack {
                PlanView()
            }
            .tabItem { tabLabel(.plan) }
            .tag(AppTab.plan)

            StudyRootView()
                .tabItem { tabLabel(.study) }
                .tag(AppTab.study)

            NavigationStack {
                PracticeBuilderView()
            }
            .tabItem { tabLabel(.practice) }
            .tag(AppTab.practice)

            vignettesRoot
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
