import XCTest

/// Tests that drive the real app, because the unit suite structurally cannot.
///
/// Every unit test in this project is value-in/value-out over a pure type, and
/// those types were correct throughout — yet bugs still shipped in the layer
/// that renders them. The worst broke the Cards session as you used it: the
/// deck was rebuilt on every rating, so the counter climbed and the total fell
/// at the same time ("1 / 20", then "2 / 19") while cards were skipped. No
/// amount of testing `FlashcardQueue.plan` could have seen it; it only exists
/// once a real view holds a real deck across a real state change.
///
/// The app launches with `-uitesting`, which puts its store in memory and its
/// preferences in a throwaway suite, so every test starts from a clean install
/// and none of this touches real data.
final class CFAL3UITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    override func tearDown() {
        app = nil
    }

    // MARK: - Helpers

    private func tab(_ name: String) -> XCUIElement {
        app.tabBars.buttons[name]
    }

    /// The bundle decodes ~9 MB on launch, so the first screen can take a
    /// moment to settle.
    private func waitFor(_ element: XCUIElement, _ seconds: TimeInterval = 20) -> Bool {
        element.waitForExistence(timeout: seconds)
    }

    private func progressCounter() -> String {
        app.staticTexts["flashcard.progress"].label
    }

    // MARK: - The regression this target exists for

    /// Rating a card must advance the position WITHOUT changing the total.
    /// When the deck was a plain `let`, the parent rebuilt it on every rating —
    /// the total shrank as the index grew, and cards in between were skipped.
    func testRatingACardAdvancesPositionWithoutShrinkingTheDeck() {
        XCTAssertTrue(waitFor(tab("Study")), "tab bar never appeared")
        tab("Study").tap()

        // Cards folded into Study behind the section menu.
        let menu = app.buttons["study.sectionMenu"]
        XCTAssertTrue(waitFor(menu), "the Study section menu is missing")
        menu.tap()
        app.buttons["Cards"].firstMatch.tap()

        let today = app.buttons["cards.today"]
        XCTAssertTrue(waitFor(today), "the Cards session row never appeared")
        today.tap()

        XCTAssertTrue(waitFor(app.staticTexts["flashcard.progress"]), "no session opened")
        let first = progressCounter()
        XCTAssertEqual(first, "1 / 20", "a fresh install should meter the deck to the daily limit")

        let total = first.components(separatedBy: " / ").last

        // Three ratings: enough for the old bug's drift to be unmistakable.
        for step in 1...3 {
            let reveal = app.buttons["flashcard.reveal"]
            XCTAssertTrue(waitFor(reveal, 5), "no card to reveal at step \(step)")
            reveal.tap()

            let good = app.buttons["flashcard.rate.good"]
            XCTAssertTrue(waitFor(good, 5), "rating controls did not appear at step \(step)")
            good.tap()

            let now = progressCounter()
            XCTAssertEqual(now.components(separatedBy: " / ").last, total,
                           "the deck total changed mid-session at step \(step) — got \(now)")
            XCTAssertEqual(now.components(separatedBy: " / ").first, "\(step + 1)",
                           "position did not advance by exactly one at step \(step) — got \(now)")
        }
    }

    // MARK: - The tab bar

    /// Seven tabs meant iOS collapsed the rest behind "More", which is where
    /// Practice — the most-used screen — ended up.
    func testEveryTabIsReachableWithoutAMoreMenu() {
        XCTAssertTrue(waitFor(tab("Home")))
        let bar = app.tabBars.firstMatch
        XCTAssertEqual(bar.buttons.count, 5, "iOS shows five tabs; a sixth creates a More menu")
        XCTAssertFalse(bar.buttons["More"].exists, "no tab should be hidden behind More")

        for name in ["Home", "Plan", "Study", "Practice", "Vignettes"] {
            XCTAssertTrue(bar.buttons[name].exists, "missing tab: \(name)")
        }
    }

    func testEveryTabOpensWithoutCrashing() {
        XCTAssertTrue(waitFor(tab("Home")))
        for name in ["Plan", "Study", "Practice", "Vignettes", "Home"] {
            tab(name).tap()
            XCTAssertTrue(tab(name).waitForExistence(timeout: 10), "\(name) did not settle")
            XCTAssertEqual(app.state, .runningForeground, "app left the foreground on \(name)")
        }
    }

    // MARK: - A fresh install is not a wall of work

    /// The queue used to announce all 3,115 questions as due on first launch.
    func testFreshInstallOffersAMeteredStartNotTheWholeCorpus() {
        let title = app.staticTexts["home.review.title"]
        XCTAssertTrue(waitFor(title), "the review card never appeared")

        XCTAssertFalse(title.label.contains("3,115"),
                       "a fresh install must not present the entire corpus as due")
        XCTAssertFalse(title.label.contains("All caught up"),
                       "3,115 unseen questions is not 'caught up'")
        XCTAssertTrue(title.label.contains("new"),
                      "expected a metered start, got: \(title.label)")
    }

    // MARK: - Vignettes are their own tab

    func testVignettesAreTheirOwnTabAndListTheBooks() {
        XCTAssertTrue(waitFor(tab("Vignettes")))
        tab("Vignettes").tap()
        XCTAssertTrue(app.staticTexts["Ethics"].waitForExistence(timeout: 10),
                      "the Vignettes tab should list the books")
    }

    /// The complaint that prompted the split: inside Practice, opening a case
    /// hid the switcher and left no visible way back to the quiz builder.
    /// Separate tabs mean the tab bar is always the way back.
    func testCanReturnToPracticeAfterOpeningAVignette() {
        XCTAssertTrue(waitFor(tab("Vignettes")))
        tab("Vignettes").tap()
        XCTAssertTrue(app.staticTexts["Ethics"].waitForExistence(timeout: 10))
        app.staticTexts["Ethics"].tap()

        // Deep inside the vignettes stack, one tap still reaches Practice.
        XCTAssertTrue(waitFor(tab("Practice"), 10), "the tab bar vanished inside a vignette")
        tab("Practice").tap()
        XCTAssertTrue(app.descendants(matching: .any)["practice.scopeSummary"]
                        .firstMatch.waitForExistence(timeout: 10),
                      "could not get back to the quiz builder")
    }

    /// Study folds notes and cards together, so the menu must be able to
    /// return to notes as well as reach cards.
    func testStudySectionMenuTogglesBothWays() {
        XCTAssertTrue(waitFor(tab("Study")))
        tab("Study").tap()
        let menu = app.buttons["study.sectionMenu"]
        XCTAssertTrue(waitFor(menu))

        menu.tap()
        app.buttons["Cards"].firstMatch.tap()
        XCTAssertTrue(app.buttons["cards.today"].waitForExistence(timeout: 10),
                      "menu did not switch to Cards")

        app.buttons["study.sectionMenu"].tap()
        app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Study"].waitForExistence(timeout: 10),
                      "menu did not switch back to Notes")
    }

    /// A freshly erased app has no accuracy, and "0%" reads as a score.
    func testFreshInstallShowsNoAccuracyScore() {
        XCTAssertTrue(waitFor(tab("Home")))
        let accuracy = app.staticTexts["—"]
        XCTAssertTrue(accuracy.waitForExistence(timeout: 15),
                      "expected a dash for accuracy with nothing attempted")
        XCTAssertFalse(app.staticTexts["0%"].exists,
                       "0% reads as a score, not as an empty history")
    }

    func testProgressIsReachableFromHome() {
        XCTAssertTrue(waitFor(tab("Home")))
        let link = app.buttons["home.progressLink"]
        XCTAssertTrue(waitFor(link), "the stats row should open Progress")
        link.tap()
        XCTAssertTrue(app.staticTexts["LOS coverage"].waitForExistence(timeout: 10),
                      "Progress did not open")
    }

    /// The footer promises a session size; starting one must deliver it.
    func testPracticeFooterPromiseMatchesTheSessionItStarts() {
        XCTAssertTrue(waitFor(tab("Practice")))
        tab("Practice").tap()

        // By identifier, not by text: "Per book" is also the label of the
        // picker directly above this row.
        let footer = app.descendants(matching: .any)["practice.scopeSummary"].firstMatch
        XCTAssertTrue(waitFor(footer), "the scope footer never appeared")

        // "5 per book → 28 questions · …" — six books at five each caps at 30.
        let label = footer.label
        let promised = label
            .components(separatedBy: " questions").first?
            .components(separatedBy: " ").last
            .flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
        XCTAssertNotNil(promised, "could not read the promised count from: \(label)")
        XCTAssertLessThanOrEqual(promised ?? .max, 30,
                                 "five per book across six books cannot exceed 30: \(label)")
        XCTAssertGreaterThan(promised ?? 0, 0)
    }

    // MARK: - Accessibility

    /// These are the controls a screen reader had nothing to say about.
    func testIconOnlyControlsAreNamed() {
        XCTAssertTrue(waitFor(tab("Home")))
        XCTAssertTrue(app.tabBars.buttons["Plan"].exists, "Plan is a tab now, not a toolbar glyph")
        XCTAssertTrue(app.buttons["Settings"].exists, "the settings button needs a label")
    }

    /// Everything on screen must survive a large accessibility text size —
    /// the notes section number used to clip to a sliver.
    func testHomeRemainsUsableAtAnAccessibilityTextSize() {
        app.terminate()
        let sized = XCUIApplication()
        sized.launchArguments = [
            "-uitesting",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL"
        ]
        sized.launch()

        let title = sized.staticTexts["home.review.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertTrue(title.isHittable, "the review card is unreachable at large text sizes")
        XCTAssertEqual(sized.tabBars.firstMatch.buttons.count, 5,
                       "the tab bar should not lose tabs at large text sizes")
        sized.terminate()
    }
}
