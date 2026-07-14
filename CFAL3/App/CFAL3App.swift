import SwiftUI
import SwiftData

@main
struct CFAL3App: App {
    @State private var contentLoader = ContentLoader()
    @State private var grader = ClaudeGrader()
    @State private var sessionCoordinator = StudySessionCoordinator()
    @State private var practicePref = PracticeBuilderPreference()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Attempt.self, ReviewCard.self, Session.self, LOSStudyStatus.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(contentLoader)
                .environment(grader)
                .environment(sessionCoordinator)
                .environment(practicePref)
                .task {
                    if !contentLoader.isLoaded {
                        contentLoader.load()
                    }
                    contentLoader.bootstrapReviewCards(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
