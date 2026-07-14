import SwiftUI

struct RootTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                RootSidebarView()
            } else {
                RootPhoneTabView()
            }
        }
        .tint(Theme.accent)
    }
}

private struct RootPhoneTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                StudyPlannerView()
            }
            .tabItem { Label("Study", systemImage: "checklist") }

            NavigationStack {
                TopicListView()
            }
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
}
