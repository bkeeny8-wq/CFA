import SwiftUI

/// Five tabs, deliberately. iPhone collapses anything past the fifth into a
/// "More" list, which is where Practice — the most-used screen — used to live.
/// Plan is reached from Home, and case browsing is a mode inside Practice.
enum AppTab: Hashable {
    case home
    case study
    case practice
    case cards
    case progress
}

struct RootTabView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        RootTabContent(selectedTab: $selectedTab)
            .tint(Theme.accent)
    }
}

private struct RootTabContent: View {
    @Binding var selectedTab: AppTab
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            studyRoot
                .tabItem { Label("Study", systemImage: "checklist") }
                .tag(AppTab.study)

            PracticeRootView()
                .tabItem { Label("Practice", systemImage: "square.and.pencil") }
                .tag(AppTab.practice)

            NavigationStack {
                FlashcardsHomeView()
            }
            .tabItem { Label("Cards", systemImage: "rectangle.on.rectangle.angled") }
            .tag(AppTab.cards)

            NavigationStack {
                ProgressDashboardView()
            }
            .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
            .tag(AppTab.progress)
        }
    }

    @ViewBuilder
    private var studyRoot: some View {
        if horizontalSizeClass == .regular {
            StudyPlannerSplitView()
        } else {
            NavigationStack {
                StudyPlannerView()
            }
        }
    }
}
