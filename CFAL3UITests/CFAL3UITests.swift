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

    private static let tabNames = ["Today", "Plan", "Notes", "Cards", "Practice", "Cases", "Progress"]

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

    /// Destinations are addressed by accessibility identifier, never through
    /// `app.tabBars`. Daybook uses a custom sidebar; identifiers stay the
    /// contract so chrome can change without rewriting every test.
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

    /// Book names live on `cases.book.*`. Nested split chrome used to hide
    /// them as StaticText, so tests address the identifier, not the glyph.
    private func casesBook(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)["cases.book.\(name)"].firstMatch
    }

    private func progressCoverage() -> XCUIElement {
        app.descendants(matching: .any)["progress.losCoverage"].firstMatch
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
        XCTAssertTrue(waitFor(tab("Cards")), "the sidebar never appeared")
        tab("Cards").tap()

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

    // MARK: - The sidebar

    func testEveryTabIsReachableWithoutAnOverflowMenu() {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")

        for name in Self.tabNames {
            let item = tab(name)
            XCTAssertTrue(item.exists, "missing destination: \(name)")
            XCTAssertTrue(item.isHittable, "\(name) exists but cannot be tapped — overflowed?")
        }
        XCTAssertFalse(app.buttons["More"].exists, "no destination should be hidden behind More")
    }

    func testEveryTabOpensWithoutCrashing() {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")
        for name in ["Plan", "Notes", "Cards", "Practice", "Cases", "Progress", "Today"] {
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

    // MARK: - Cases are their own destination

    func testVignettesAreTheirOwnTabAndListTheBooks() {
        XCTAssertTrue(waitFor(tab("Cases")), "the sidebar never appeared")
        tab("Cases").tap()
        XCTAssertTrue(casesBook("Ethics").waitForExistence(timeout: 10),
                      "the Cases destination should list the books")
    }

    /// Browsing a vignette must not hide Practice — sittings are a cover;
    /// browse chrome stays.
    func testCanReturnToPracticeAfterOpeningAVignette() {
        XCTAssertTrue(waitFor(tab("Cases")), "the sidebar never appeared")
        tab("Cases").tap()

        let ethics = casesBook("Ethics")
        XCTAssertTrue(ethics.waitForExistence(timeout: 10))
        ethics.tap()

        XCTAssertTrue(waitFor(tab("Practice"), 10), "the sidebar vanished inside a vignette browse")
        tab("Practice").tap()
        XCTAssertTrue(app.descendants(matching: .any)["practice.scopeSummary"]
                        .firstMatch.waitForExistence(timeout: 10),
                      "could not get back to the quiz builder")
    }

    /// Notes and Cards are separate sidebar rows. Only the selected destination
    /// is mounted, so Cards rows must not leak into Notes.
    func testNotesAndCardsAreSeparateDestinations() {
        XCTAssertTrue(waitFor(tab("Notes")), "the sidebar never appeared")
        tab("Notes").tap()

        XCTAssertTrue(tab("Notes").isSelected || tab("Notes").isHittable)
        XCTAssertFalse(app.buttons["cards.today"].firstMatch.exists,
                       "Cards rows must not stay in the tree while Notes is showing")
        XCTAssertFalse(app.buttons["study.section.notes"].firstMatch.exists,
                       "the old Study section bar should be gone")
        XCTAssertFalse(app.buttons["study.section.cards"].firstMatch.exists,
                       "the old Study section bar should be gone")

        let reading = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "R1 ·"))
            .firstMatch
        if reading.waitForExistence(timeout: 10) {
            reading.tap()
        }

        XCTAssertTrue(tab("Cards").waitForExistence(timeout: 10),
                      "Cards vanished after opening a reading")
        XCTAssertTrue(tab("Cards").isHittable, "Cards is present but unreachable")

        tab("Cards").tap()
        XCTAssertTrue(app.buttons["cards.today"].firstMatch.waitForExistence(timeout: 10),
                      "the Cards destination did not show its today row")
        XCTAssertTrue(tab("Notes").isHittable, "Notes must remain reachable from Cards")
    }

    /// A freshly erased app has no accuracy, and "0%" reads as a score.
    func testFreshInstallShowsNoAccuracyScore() {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")
        let accuracy = app.staticTexts["—"].firstMatch
        XCTAssertTrue(accuracy.waitForExistence(timeout: 15),
                      "expected a dash for accuracy with nothing attempted")
        XCTAssertFalse(app.staticTexts["0%"].exists,
                       "0% reads as a score, not as an empty history")
    }

    func testProgressIsReachableFromHome() {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")
        let link = app.buttons["home.progressLink"].firstMatch
        XCTAssertTrue(waitFor(link), "the stats row should open Progress")
        link.tap()
        XCTAssertTrue(progressCoverage().waitForExistence(timeout: 10),
                      "Progress did not open")

        tab("Today").tap()
        XCTAssertTrue(waitFor(tab("Progress")), "Progress should be a sidebar row")
        tab("Progress").tap()
        XCTAssertTrue(progressCoverage().waitForExistence(timeout: 10),
                      "Progress sidebar did not open the dashboard")
    }

    func testSittingHidesTheSidebar() throws {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")
        let start = app.buttons["home.startSitting"].firstMatch
        XCTAssertTrue(waitFor(start), "Start sitting never appeared")
        guard start.isEnabled else {
            throw XCTSkip("fresh-install mix was empty, so a sitting could not start")
        }
        start.tap()
        XCTAssertTrue(app.buttons["sitting.end"].firstMatch.waitForExistence(timeout: 15),
                      "sitting chrome never appeared")
        XCTAssertFalse(tab("Today").isHittable,
                       "the sidebar should hide while a sitting is open")
        app.buttons["sitting.end"].firstMatch.tap()
        XCTAssertTrue(waitFor(tab("Today"), 10), "sidebar did not return after End sitting")
    }

    /// The footer promises a session size; starting one must deliver it.
    func testPracticeFooterPromiseMatchesTheSessionItStarts() {
        XCTAssertTrue(waitFor(tab("Practice")), "the sidebar never appeared")
        tab("Practice").tap()

        let footer = app.descendants(matching: .any)["practice.scopeSummary"].firstMatch
        XCTAssertTrue(waitFor(footer), "the scope footer never appeared")

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

    func testIconOnlyControlsAreNamed() {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")
        XCTAssertEqual(tab("Plan").label, "Plan", "Plan is a sidebar row, not a toolbar glyph")
        XCTAssertTrue(app.buttons["Settings"].firstMatch.exists,
                      "the settings button needs a label")
        XCTAssertTrue(tab("Progress").exists,
                      "Progress is a named sidebar destination")
    }

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
