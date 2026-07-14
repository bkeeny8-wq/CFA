import SwiftUI

struct RootTabView: View {
    var body: some View {
        RootTabContent()
            .tint(Theme.accent)
    }
}

private struct RootTabContent: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            studyRoot
            .tabItem { Label("Study", systemImage: "checklist") }

            browseRoot
            .tabItem { Label("Browse", systemImage: "books.vertical.fill") }

            NavigationStack {
                PracticeBuilderView()
            }
            .tabItem { Label("Practice", systemImage: "square.and.pencil") }

            NavigationStack {
                ProgressDashboardView()
            }
            .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
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
