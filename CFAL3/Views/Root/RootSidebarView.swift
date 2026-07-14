import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case study
    case browse
    case practice
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .study: return "Study"
        case .browse: return "Browse"
        case .practice: return "Practice"
        case .progress: return "Progress"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .study: return "checklist"
        case .browse: return "books.vertical.fill"
        case .practice: return "square.and.pencil"
        case .progress: return "chart.bar.fill"
        }
    }
}

/// iPad root navigation: sidebar sections with split-view detail where it helps.
struct RootSidebarView: View {
    @State private var selection: AppSection? = .study

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("CFA L3")
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            if let selection {
                sectionRoot(selection)
            } else {
                ContentUnavailableView(
                    "Welcome",
                    systemImage: "graduationcap",
                    description: Text("Select a section from the sidebar.")
                )
            }
        }
    }

    @ViewBuilder
    private func sectionRoot(_ section: AppSection) -> some View {
        switch section {
        case .home:
            NavigationStack { HomeView() }
        case .study:
            StudyPlannerSplitView()
        case .browse:
            BrowseSplitView()
        case .practice:
            NavigationStack { PracticeBuilderView() }
        case .progress:
            NavigationStack { ProgressDashboardView() }
        }
    }
}
