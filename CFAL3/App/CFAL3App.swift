import SwiftUI
import SwiftData

@main
struct CFAL3App: App {
    @State private var contentLoader = ContentLoader()
    @State private var grader = ClaudeGrader()
    @State private var sessionCoordinator = StudySessionCoordinator()
    @State private var practicePref = PracticeBuilderPreference()

    /// True when the on-disk store could not be opened and the app is running
    /// against a temporary one, so the UI can say so instead of looking as if
    /// the user's progress vanished.
    @State private var storeUnavailable = false

    let sharedModelContainer: ModelContainer
    let storeFailure: Error?

    init() {
        let schema = Schema([
            Attempt.self, ReviewCard.self, Session.self,
            LOSStudyStatus.self, DayCompletion.self, FlashcardProgress.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [config])
            storeFailure = nil
        } catch {
            // A migration the runtime declines to infer used to be a crash on
            // every launch, with the user's history locked inside a store they
            // could no longer even export. Fall back to an in-memory container
            // so the app opens and can explain itself — the file on disk is
            // left untouched and stays recoverable.
            storeFailure = error
            sharedModelContainer = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(contentLoader)
                .environment(grader)
                .environment(sessionCoordinator)
                .environment(practicePref)
                .task {
                    GraderConfig.purgeLegacyAPIKey()
                    if !contentLoader.isLoaded {
                        contentLoader.load()
                    }
                    contentLoader.bootstrapReviewCards(context: sharedModelContainer.mainContext)
                    storeUnavailable = storeFailure != nil
                }
                .alert("Saved progress couldn't be opened", isPresented: $storeUnavailable) {
                    Button("Continue", role: .cancel) {}
                } message: {
                    Text("This session won't be saved. Your existing data is "
                         + "still on the device — reinstalling an earlier "
                         + "version, or updating again, may recover it.\n\n"
                         + (storeFailure?.localizedDescription ?? ""))
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
