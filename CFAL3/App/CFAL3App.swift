import SwiftUI
import SwiftData

/// UI tests need a known starting state on every run. Under this flag the app
/// keeps its store in memory and reads preferences from a throwaway suite, so
/// a test never inherits a previous run's answers or settings — and never
/// touches the real device's data.
enum UITestMode {
    static let launchArgument = "-uitesting"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    private static let suiteName = "com.brandonkeeny.CFAL3.uitests"

    /// `let`, not `var`, and the distinction is load-bearing: as a computed
    /// property this wiped the suite on EVERY access, so anything written
    /// between two reads was silently thrown away.
    ///
    /// A `static let` is initialised once per process, which is exactly the
    /// lifetime wanted — every launch starts clean, and nothing is lost while
    /// the app is running.
    ///
    /// Everything that persists anything must read it from here rather than
    /// reach for `.standard` directly, or it survives across launches and one
    /// test inherits the last one's state. That is not hypothetical: the Study
    /// tab's section was a plain `@AppStorage`, so a test that opened Cards
    /// left the next test opening on Cards too.
    static let defaults: UserDefaults = {
        guard isActive, let suite = UserDefaults(suiteName: suiteName) else { return .standard }
        suite.removePersistentDomain(forName: suiteName)
        return suite
    }()
}

@main
struct CFAL3App: App {
    @State private var contentLoader = ContentLoader()
    @State private var grader = ClaudeGrader()
    @State private var sessionCoordinator = StudySessionCoordinator()
    @State private var practicePref = PracticeBuilderPreference(defaults: UITestMode.defaults)

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
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: UITestMode.isActive
        )
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
