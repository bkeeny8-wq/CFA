import SwiftUI

/// Five tabs, deliberately. iPhone collapses anything past the fifth into a
/// "More" list, which is where Practice — the most-used screen — once ended up.
///
/// Seven sections have to fit five slots, so two are folded:
/// - Cards joins Study, which already navigates book → reading the same way;
///   a menu in that tab's bar switches between notes and cards.
/// - Progress is reached by tapping Home's stats, which already show accuracy,
///   attempted, streak and days-to-exam. The dashboard is their drill-down.
enum AppTab: Hashable {
    case home
    case plan
    case study
    case practice
    case vignettes
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
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                PlanView()
            }
            .tabItem { Label("Plan", systemImage: "calendar") }
            .tag(AppTab.plan)

            StudyRootView()
                .id(router.selected == .study ? router.popToRootToken : -1)
                .tabItem { Label("Study", systemImage: "checklist") }
                .tag(AppTab.study)

            NavigationStack {
                PracticeBuilderView()
            }
            .tabItem { Label("Practice", systemImage: "square.and.pencil") }
            .tag(AppTab.practice)

            vignettesRoot
                .id(router.selected == .vignettes ? router.popToRootToken : -1)
                .tabItem { Label("Vignettes", systemImage: "doc.richtext") }
                .tag(AppTab.vignettes)
        }
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
