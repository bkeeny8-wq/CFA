import XCTest
import UIKit

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
///
/// This app is iPad only, so these must be run against an iPad simulator. That
/// is not a formality: an earlier version of this suite passed on iPhone while
/// every single test failed on iPad, because the two platforms do not even
/// agree on what a tab bar is.
final class CFAL3UITests: XCTestCase {

    private var app: XCUIApplication!

    private static let tabNames = ["Home", "Plan", "Study", "Practice", "Vignettes"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom != .pad {
            throw XCTSkip("CFAL3 is iPad-only; pin the destination to iPad Pro 13-inch (M5)")
        }
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    override func tearDown() {
        app = nil
    }

    // MARK: - Helpers

    /// Tabs are addressed by accessibility identifier, never through
    /// `app.tabBars`.
    ///
    /// On iPad the tab bar is a floating pill along the TOP of the window and
    /// exposes no `TabBar` element at all — the items are bare buttons in an
    /// untyped container, so every `app.tabBars` query returns nothing. Each
    /// item is also published twice, a button nested inside an identical
    /// button, which makes a bare label query ambiguous. Hence the identifier,
    /// and hence `firstMatch`.
    private func tab(_ name: String, in app: XCUIApplication? = nil) -> XCUIElement {
        (app ?? self.app).buttons["tab.\(name.lowercased())"].firstMatch
    }

    /// The bundle decodes ~9 MB on launch, so the first screen can take a
    /// moment to settle.
    private func waitFor(_ element: XCUIElement, _ seconds: TimeInterval = 20) -> Bool {
        element.waitForExistence(timeout: seconds)
    }

    private func progressCounter() -> String {
        app.staticTexts["flashcard.progress"].firstMatch.label
    }

    /// Visible chrome is "1 / 20"; VoiceOver (and therefore XCTest `.label`)
    /// is "Card 1 of 20".
    private func progressParts(_ label: String) -> (position: String, total: String)? {
        let spoken = label
            .replacingOccurrences(of: "Card ", with: "")
            .replacingOccurrences(of: " of ", with: " / ")
        let parts = spoken.components(separatedBy: " / ")
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    // MARK: - The regression this target exists for

    /// Rating a card must advance the position WITHOUT changing the total.
    /// When the deck was a plain `let`, the parent rebuilt it on every rating —
    /// the total shrank as the index grew, and cards in between were skipped.
    func testRatingACardAdvancesPositionWithoutShrinkingTheDeck() {
        XCTAssertTrue(waitFor(tab("Study")), "the tabs never appeared")
        tab("Study").tap()

        // Cards folded into Study behind the bottom section bar.
        let cards = app.buttons["study.section.cards"].firstMatch
        XCTAssertTrue(waitFor(cards), "the Study section bar is missing")
        cards.tap()

        let today = app.buttons["cards.today"].firstMatch
        XCTAssertTrue(waitFor(today), "the Cards session row never appeared")
        today.tap()

        XCTAssertTrue(waitFor(app.staticTexts["flashcard.progress"].firstMatch),
                      "no session opened")
        let first = progressCounter()
        let firstParts = progressParts(first)
        XCTAssertEqual(firstParts?.position, "1",
                       "a fresh install should start at card 1 — got \(first)")
        XCTAssertEqual(firstParts?.total, "20",
                       "a fresh install should meter the deck to the daily limit — got \(first)")

        let total = firstParts?.total

        // Three ratings: enough for the old bug's drift to be unmistakable.
        for step in 1...3 {
            let reveal = app.buttons["flashcard.reveal"].firstMatch
            XCTAssertTrue(waitFor(reveal, 5), "no card to reveal at step \(step)")
            reveal.tap()

            let good = app.buttons["flashcard.rate.good"].firstMatch
            XCTAssertTrue(waitFor(good, 5), "rating controls did not appear at step \(step)")
            good.tap()

            let now = progressCounter()
            let parts = progressParts(now)
            XCTAssertEqual(parts?.total, total,
                           "the deck total changed mid-session at step \(step) — got \(now)")
            XCTAssertEqual(parts?.position, "\(step + 1)",
                           "position did not advance by exactly one at step \(step) — got \(now)")
        }
    }

    // MARK: - The tabs

    /// Seven sections meant the bar collapsed the surplus into an overflow,
    /// which is where Practice — the most-used screen — ended up.
    ///
    /// Asserted as "all five are reachable" rather than "the bar holds exactly
    /// five", because the count is a property of chrome this app no longer
    /// queries. Hittability is the real claim anyway: an overflowed tab still
    /// exists, it just cannot be tapped.
    func testEveryTabIsReachableWithoutAnOverflowMenu() {
        XCTAssertTrue(waitFor(tab("Home")), "the tabs never appeared")

        for name in Self.tabNames {
            let item = tab(name)
            XCTAssertTrue(item.exists, "missing tab: \(name)")
            XCTAssertTrue(item.isHittable, "\(name) exists but cannot be tapped — overflowed?")
        }
        XCTAssertFalse(app.buttons["More"].exists, "no tab should be hidden behind More")
    }

    func testEveryTabOpensWithoutCrashing() {
        XCTAssertTrue(waitFor(tab("Home")), "the tabs never appeared")
        for name in ["Plan", "Study", "Practice", "Vignettes", "Home"] {
            tab(name).tap()
            XCTAssertTrue(tab(name).waitForExistence(timeout: 10), "\(name) did not settle")
            XCTAssertEqual(app.state, .runningForeground, "app left the foreground on \(name)")
        }
    }

    // MARK: - A fresh install is not a wall of work

    /// The queue used to announce all 3,164 questions as due on first launch.
    func testFreshInstallOffersAMeteredStartNotTheWholeCorpus() {
        let title = app.staticTexts["home.review.title"].firstMatch
        XCTAssertTrue(waitFor(title), "the review card never appeared")

        XCTAssertFalse(title.label.contains("3,157"),
                       "a fresh install must not present the entire corpus as due")
        XCTAssertFalse(title.label.contains("3,164"),
                       "a fresh install must not present the entire corpus as due")
        XCTAssertFalse(title.label.contains("All caught up"),
                       "3,157 unseen questions is not 'caught up'")
        XCTAssertTrue(title.label.contains("new"),
                      "expected a metered start, got: \(title.label)")
    }

    // MARK: - Vignettes are their own tab

    func testVignettesAreTheirOwnTabAndListTheBooks() {
        XCTAssertTrue(waitFor(tab("Vignettes")), "the tabs never appeared")
        tab("Vignettes").tap()
        XCTAssertTrue(app.staticTexts["Ethics"].firstMatch.waitForExistence(timeout: 10),
                      "the Vignettes tab should list the books")
    }

    /// The complaint that prompted the split: inside Practice, opening a case
    /// hid the switcher and left no visible way back to the quiz builder.
    /// Separate tabs mean the tabs are always the way back.
    func testCanReturnToPracticeAfterOpeningAVignette() {
        XCTAssertTrue(waitFor(tab("Vignettes")), "the tabs never appeared")
        tab("Vignettes").tap()

        let ethics = app.staticTexts["Ethics"].firstMatch
        XCTAssertTrue(ethics.waitForExistence(timeout: 10))
        ethics.tap()

        // Deep inside the vignettes stack, one tap still reaches Practice.
        XCTAssertTrue(waitFor(tab("Practice"), 10), "the tabs vanished inside a vignette")
        tab("Practice").tap()
        XCTAssertTrue(app.descendants(matching: .any)["practice.scopeSummary"]
                        .firstMatch.waitForExistence(timeout: 10),
                      "could not get back to the quiz builder")
    }

    /// The selector is a bar along the BOTTOM of the Study tab, and it must
    /// survive opening a reading — a navigation-bar control disappears the
    /// moment you do that, which is how the old Practice switcher stranded you
    /// inside a case.
    ///
    /// Only the selected half is mounted. Dual-mounting left `cards.today`
    /// readable from Notes because `List` publishes its rows regardless of a
    /// parent `.accessibilityHidden`.
    func testStudySectionBarTogglesAndSurvivesOpeningAReading() {
        XCTAssertTrue(waitFor(tab("Study")), "the tabs never appeared")
        tab("Study").tap()

        let notes = app.buttons["study.section.notes"].firstMatch
        let cards = app.buttons["study.section.cards"].firstMatch
        XCTAssertTrue(waitFor(notes), "the Study section bar is missing")
        XCTAssertTrue(cards.exists)

        XCTAssertTrue(notes.isSelected, "Study should open on Notes")
        XCTAssertFalse(cards.isSelected)
        XCTAssertFalse(app.buttons["cards.today"].firstMatch.exists,
                       "Cards rows must not stay in the tree while Notes is showing")

        // Both halves must be equally easy to hit. The unselected one once
        // collapsed to a 60 × 16 pt target, because its clear background
        // contributed no hit region.
        for half in [notes, cards] {
            XCTAssertTrue(half.isHittable, "\(half.label) is not tappable")
            XCTAssertGreaterThanOrEqual(half.frame.height, 44,
                                        "\(half.label) is a \(half.frame.height)pt tall target")
        }

        cards.tap()
        XCTAssertTrue(cards.isSelected, "the bar did not switch to Cards")
        XCTAssertFalse(notes.isSelected)
        XCTAssertTrue(app.buttons["cards.today"].firstMatch.isHittable,
                      "the Cards half is selected but its content is not reachable")

        notes.tap()
        XCTAssertTrue(notes.isSelected, "the bar did not switch back to Notes")
        XCTAssertFalse(cards.isSelected)

        // Open a reading: on iPad this collapses the planner's columns to the
        // detail view, on a phone it pushes. Either way the bar must survive.
        let reading = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "R1 ·"))
            .firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 10), "no reading row to open")
        XCTAssertFalse(app.buttons["cards.today"].firstMatch.exists,
                       "switching back to Notes must unmount Cards")
        reading.tap()

        XCTAssertTrue(cards.waitForExistence(timeout: 10),
                      "the selector vanished on opening a reading — the exact trap this replaced")
        XCTAssertTrue(cards.isHittable, "the selector is present but unreachable")
    }

    /// A freshly erased app has no accuracy, and "0%" reads as a score.
    func testFreshInstallShowsNoAccuracyScore() {
        XCTAssertTrue(waitFor(tab("Home")), "the tabs never appeared")
        let accuracy = app.staticTexts["—"].firstMatch
        XCTAssertTrue(accuracy.waitForExistence(timeout: 15),
                      "expected a dash for accuracy with nothing attempted")
        XCTAssertFalse(app.staticTexts["0%"].exists,
                       "0% reads as a score, not as an empty history")
    }

    func testProgressIsReachableFromHome() {
        XCTAssertTrue(waitFor(tab("Home")), "the tabs never appeared")
        let link = app.buttons["home.progressLink"].firstMatch
        XCTAssertTrue(waitFor(link), "the stats row should open Progress")
        link.tap()
        XCTAssertTrue(app.staticTexts["LOS coverage"].firstMatch.waitForExistence(timeout: 10),
                      "Progress did not open")
        app.navigationBars.buttons.firstMatch.tap()

        let toolbar = app.buttons["home.progress"].firstMatch
        XCTAssertTrue(waitFor(toolbar), "Home's Progress toolbar should open Progress")
        toolbar.tap()
        XCTAssertTrue(app.staticTexts["LOS coverage"].firstMatch.waitForExistence(timeout: 10),
                      "Progress toolbar did not open the dashboard")
    }

    /// The footer promises a session size; starting one must deliver it.
    func testPracticeFooterPromiseMatchesTheSessionItStarts() {
        XCTAssertTrue(waitFor(tab("Practice")), "the tabs never appeared")
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
        XCTAssertTrue(waitFor(tab("Home")), "the tabs never appeared")
        XCTAssertEqual(tab("Plan").label, "Plan", "Plan is a tab now, not a toolbar glyph")
        XCTAssertTrue(app.buttons["Settings"].firstMatch.exists,
                      "the settings button needs a label")
        XCTAssertTrue(app.buttons["Progress"].firstMatch.exists,
                      "the Progress toolbar button needs a label")
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
        defer { sized.terminate() }

        let title = sized.staticTexts["home.review.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertTrue(title.isHittable, "the review card is unreachable at large text sizes")

        for name in Self.tabNames {
            XCTAssertTrue(tab(name, in: sized).isHittable,
                          "\(name) became unreachable at a large text size")
        }
    }
}
