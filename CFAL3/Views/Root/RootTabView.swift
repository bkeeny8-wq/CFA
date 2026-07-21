import SwiftUI

enum AppTab: Hashable {
    case home
    case plan
    case study
    case browse
    case practice
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
                HomeView(selectedTab: $selectedTab)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                PlanView()
            }
            .tabItem { Label("Plan", systemImage: "calendar") }
            .tag(AppTab.plan)

            studyRoot
                .tabItem { Label("Study", systemImage: "checklist") }
                .tag(AppTab.study)

            browseRoot
                .tabItem { Label("Cases", systemImage: "books.vertical.fill") }
                .tag(AppTab.browse)

            NavigationStack {
                PracticeBuilderView()
            }
            .tabItem { Label("Practice", systemImage: "square.and.pencil") }
            .tag(AppTab.practice)

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

    @ViewBuilder
    private var browseRoot: some View {
        if horizontalSizeClass == .regular {
            BrowseSplitView()
        } else {
            NavigationStack {
                TopicListView()
            }
        }
    }
}
