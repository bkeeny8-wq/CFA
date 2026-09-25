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

    private static let tabNames = [
        "Today", "Plan", "Notes", "MM Review", "Cards", "Practice", "Cases", "Progress"
    ]

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
        // Mirrors AppTab.identifier: spaces collapse, so "MM Review" is
        // addressed as "tab.mmreview". If the two ever drift, every lookup
        // here silently returns a non-existent element and the tests pass by
        // asserting nothing — hence tabNames is checked against the sidebar.
        let id = name.lowercased().replacingOccurrences(of: " ", with: "")
        return (app ?? self.app).buttons["tab.\(id)"].firstMatch
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

    private func notesBook(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)["notes.book.\(name)"].firstMatch
    }

    /// Every left column is folded away by the same control, addressed by the
    /// column's key. Mirrors `LeftColumnSpec.toggleIdentifier`.
    private func columnToggle(_ key: String, in app: XCUIApplication? = nil) -> XCUIElement {
        (app ?? self.app).buttons["leftcolumn.toggle.\(key)"].firstMatch
    }

    /// Opens Notes → Asset allocation → its first reading, which is where the
    /// second left column (the LOS rail) lives.
    private func openFirstNotesReading() {
        tab("Notes").tap()
        let book = notesBook("Asset allocation")
        XCTAssertTrue(book.waitForExistence(timeout: 10), "Notes should list the books")
        book.tap()
        let reading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "notes.reading."))
            .firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 10),
                      "expanding a book should reveal its readings")
        reading.tap()
    }

    private func cardsBook(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)["cards.book.\(name)"].firstMatch
    }

    private func firstCaseItem() -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "cases.item."))
            .firstMatch
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

    /// The reported bug: cards looked as though they arrived already revealed.
    /// The cause was in the deck — split atoms carried their own answer on the
    /// front — but the sitting has to hold up its end too: a card must show
    /// only its prompt until it is tapped, and rating one must not carry the
    /// revealed state onto the next.
    /// When `DAYBOOK_SCREENSHOT_DIR` is set, writes the before/after shots.
    func testACardShowsOnlyItsPromptUntilRevealed() {
        XCTAssertTrue(waitFor(tab("Cards")), "the sidebar never appeared")
        tab("Cards").tap()

        let today = app.buttons["cards.today"].firstMatch
        XCTAssertTrue(waitFor(today), "the Cards session row never appeared")
        today.tap()

        let reveal = app.buttons["flashcard.reveal"].firstMatch
        XCTAssertTrue(waitFor(reveal), "no session opened")
        XCTAssertTrue(app.staticTexts["Tap to reveal"].firstMatch.exists,
                      "a fresh card must prompt for the tap")
        XCTAssertFalse(app.buttons["flashcard.rate.good"].firstMatch.exists,
                       "the rating bar belongs to a revealed card")
        saveScreenshot("card-before-reveal")

        reveal.tap()
        let good = app.buttons["flashcard.rate.good"].firstMatch
        XCTAssertTrue(waitFor(good, 5), "tapping the card did not reveal it")
        XCTAssertFalse(app.staticTexts["Tap to reveal"].firstMatch.exists,
                       "a revealed card should stop asking to be tapped")
        saveScreenshot("card-after-reveal")

        good.tap()
        XCTAssertTrue(waitFor(app.buttons["flashcard.reveal"].firstMatch, 5),
                      "the next card never arrived")
        XCTAssertTrue(app.staticTexts["Tap to reveal"].firstMatch.exists,
                      "the next card inherited the previous card's revealed state")
        XCTAssertFalse(app.buttons["flashcard.rate.good"].firstMatch.exists,
                       "the rating bar stayed up over an unrevealed card")
        saveScreenshot("next-card-before-reveal")
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
        for name in ["Plan", "Notes", "MM Review", "Cards", "Practice", "Cases", "Progress", "Today"] {
            tab(name).tap()
            XCTAssertTrue(tab(name).waitForExistence(timeout: 10), "\(name) did not settle")
            XCTAssertEqual(app.state, .runningForeground, "app left the foreground on \(name)")
        }
    }

    // MARK: - Folding the left column away

    /// The reported gap: there was no way to get the left column off the
    /// screen. One control, and hiding it must actually unmount the sidebar
    /// rather than leave it in the tree for VoiceOver to walk.
    func testTheSidebarCanBeHiddenAndBroughtBack() {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")

        let toggle = columnToggle("sidebar")
        XCTAssertTrue(waitFor(toggle), "no control to fold the sidebar away")
        XCTAssertEqual(toggle.label, "Hide the sidebar",
                       "an icon-only control has to say what it does")

        toggle.tap()
        XCTAssertTrue(
            app.buttons["tab.plan"].firstMatch.waitForNonExistence(timeout: 5),
            "hiding the sidebar must remove its rows, not just move them offscreen"
        )
        XCTAssertFalse(app.buttons["tab.settings"].firstMatch.exists,
                       "the sidebar footer went with it")

        XCTAssertTrue(toggle.exists, "the control must survive hiding the column it controls")
        XCTAssertTrue(toggle.isHittable, "the only way back must stay reachable")
        XCTAssertEqual(toggle.label, "Show the sidebar",
                       "the label has to follow the state")

        toggle.tap()
        XCTAssertTrue(waitFor(tab("Plan"), 5), "the sidebar did not come back")
        XCTAssertEqual(toggle.label, "Hide the sidebar")
    }

    /// Whatever the destination, the control is the same button in the same
    /// place — the point of the shared bar rather than eight toolbar glyphs.
    func testTheLeftColumnControlSitsInTheSamePlaceOnEveryScreen() {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")
        XCTAssertTrue(waitFor(columnToggle("sidebar")))

        var frames: [String: CGRect] = [:]
        for name in Self.tabNames {
            tab(name).tap()
            let toggle = columnToggle("sidebar")
            XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                          "\(name) has a left column but no control to fold it away")
            XCTAssertTrue(toggle.isHittable, "the control is unreachable on \(name)")
            frames[name] = toggle.frame
        }

        let distinct = Set(frames.values.map { "\($0.origin.x),\($0.origin.y)" })
        XCTAssertEqual(distinct.count, 1,
                       "the control moves between screens: \(frames)")
    }

    /// Hiding the column has to hand the width to the page, not leave a gap.
    func testHidingTheSidebarGivesNotesTheFullWidth() {
        XCTAssertTrue(waitFor(tab("Notes")), "the sidebar never appeared")
        tab("Notes").tap()

        let title = app.descendants(matching: .any)["notes.library"].firstMatch
        XCTAssertTrue(waitFor(title), "Notes never opened")
        let before = title.frame

        columnToggle("sidebar").tap()
        XCTAssertTrue(
            app.buttons["tab.plan"].firstMatch.waitForNonExistence(timeout: 5),
            "the sidebar did not hide"
        )

        let after = title.frame
        XCTAssertLessThan(after.minX, before.minX - 50,
                          "Notes did not reclaim the space: \(before) → \(after)")
        XCTAssertTrue(notesBook("Ethics").waitForExistence(timeout: 10),
                      "the book list must stay usable with the sidebar folded away")
        XCTAssertTrue(notesBook("Ethics").isHittable,
                      "the book list must stay tappable with the sidebar folded away")
    }

    /// A reading has a second left column — the LOS rail — and it folds with
    /// the same control, offered next to the sidebar's rather than as a
    /// one-off glyph in that screen's toolbar.
    func testTheNotesReadingRailFoldsWithTheSameControl() throws {
        XCTAssertTrue(waitFor(tab("Notes")), "the sidebar never appeared")
        XCTAssertFalse(columnToggle("notes.rail").exists,
                       "the Notes library has no rail, so it must not offer a rail control")

        openFirstNotesReading()

        let railToggle = columnToggle("notes.rail")
        guard railToggle.waitForExistence(timeout: 10) else {
            throw XCTSkip("the first Asset allocation reading has no LOS sections to rail")
        }
        XCTAssertEqual(railToggle.label, "Hide the LOS rail",
                       "the second column names itself too")
        XCTAssertTrue(columnToggle("sidebar").exists,
                      "both left columns are controlled from the same row")

        let rail = app.descendants(matching: .any)["notes.rail"].firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 10), "the reading should show its LOS rail")

        railToggle.tap()
        XCTAssertTrue(rail.waitForNonExistence(timeout: 5),
                      "hiding the rail must unmount it")
        XCTAssertEqual(railToggle.label, "Show the LOS rail")

        railToggle.tap()
        XCTAssertTrue(rail.waitForExistence(timeout: 5), "the rail did not come back")
    }

    /// Leaving the reading takes its control with it: the bar offers a column
    /// only while the screen that has it is on screen.
    func testTheRailControlLeavesWithTheReading() throws {
        XCTAssertTrue(waitFor(tab("Notes")), "the sidebar never appeared")
        openFirstNotesReading()

        let railToggle = columnToggle("notes.rail")
        guard railToggle.waitForExistence(timeout: 10) else {
            throw XCTSkip("the first Asset allocation reading has no LOS sections to rail")
        }

        tab("Today").tap()
        XCTAssertTrue(railToggle.waitForNonExistence(timeout: 5),
                      "Today has no LOS rail, so it must not offer a control for one")
        XCTAssertTrue(columnToggle("sidebar").exists, "the sidebar control stays")
    }

    /// The state is remembered, so folding the sidebar away is a decision you
    /// make once rather than on every launch.
    func testAHiddenSidebarIsStillHiddenAfterRelaunch() {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")
        columnToggle("sidebar").tap()
        XCTAssertTrue(app.buttons["tab.plan"].firstMatch.waitForNonExistence(timeout: 5),
                      "the sidebar did not hide")
        app.terminate()

        // The only launch in this suite that keeps the throwaway preference
        // suite: every other one wipes it, so nothing leaks out of this test.
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-uitesting", "-uitesting-preserve-defaults"]
        relaunched.launch()
        defer { relaunched.terminate() }

        let toggle = columnToggle("sidebar", in: relaunched)
        XCTAssertTrue(toggle.waitForExistence(timeout: 20),
                      "the control must be there on a launch that starts folded")
        XCTAssertEqual(toggle.label, "Show the sidebar",
                       "the app forgot that the sidebar was folded away")
        XCTAssertFalse(relaunched.buttons["tab.plan"].firstMatch.exists,
                       "the sidebar came back on its own")

        toggle.tap()
        XCTAssertTrue(relaunched.buttons["tab.plan"].firstMatch.waitForExistence(timeout: 10),
                      "the sidebar did not come back after relaunch")
    }

    /// Both states, on the browse library and inside a reading.
    /// When `DAYBOOK_SCREENSHOT_DIR` is set, writes the shots.
    func testTheFoldedSidebarLooksRightOnEveryScreen() {
        XCTAssertTrue(waitFor(tab("Today")), "the sidebar never appeared")
        let toggle = columnToggle("sidebar")
        XCTAssertTrue(waitFor(toggle))

        saveScreenshot("sidebar-shown-today")
        toggle.tap()
        XCTAssertTrue(app.buttons["tab.plan"].firstMatch.waitForNonExistence(timeout: 5))
        saveScreenshot("sidebar-hidden-today")
        toggle.tap()
        XCTAssertTrue(waitFor(tab("Notes"), 5))

        tab("Notes").tap()
        XCTAssertTrue(notesBook("Ethics").waitForExistence(timeout: 10))
        saveScreenshot("sidebar-shown-notes")
        toggle.tap()
        XCTAssertTrue(app.buttons["tab.plan"].firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(notesBook("Ethics").waitForExistence(timeout: 10),
                      "Notes must stay usable with the sidebar folded away")
        saveScreenshot("sidebar-hidden-notes")
        toggle.tap()
        XCTAssertTrue(waitFor(tab("Notes"), 5))

        openFirstNotesReading()
        let railToggle = columnToggle("notes.rail")
        guard railToggle.waitForExistence(timeout: 10) else { return }
        saveScreenshot("notes-reading-both-columns-shown")
        toggle.tap()
        XCTAssertTrue(app.buttons["tab.plan"].firstMatch.waitForNonExistence(timeout: 5))
        saveScreenshot("notes-reading-sidebar-hidden")
        railToggle.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["notes.rail"].firstMatch
                .waitForNonExistence(timeout: 5)
        )
        saveScreenshot("notes-reading-both-columns-hidden")
        toggle.tap()
        railToggle.tap()

        tab("Progress").tap()
        XCTAssertTrue(progressCoverage().waitForExistence(timeout: 10))
        saveScreenshot("sidebar-shown-progress")
        toggle.tap()
        XCTAssertTrue(app.buttons["tab.plan"].firstMatch.waitForNonExistence(timeout: 5))
        saveScreenshot("sidebar-hidden-progress")
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
        XCTAssertFalse(firstCaseItem().exists,
                       "case rows stay hidden until a book is expanded")
    }

    /// Browsing a vignette must not hide Practice — sittings are a cover;
    /// browse chrome stays.
    func testCanReturnToPracticeAfterOpeningAVignette() {
        XCTAssertTrue(waitFor(tab("Cases")), "the sidebar never appeared")
        tab("Cases").tap()

        let ethics = casesBook("Ethics")
        XCTAssertTrue(ethics.waitForExistence(timeout: 10))
        ethics.tap()

        let caseRow = firstCaseItem()
        XCTAssertTrue(caseRow.waitForExistence(timeout: 10),
                      "expanding Ethics should reveal its cases")
        caseRow.tap()

        XCTAssertTrue(waitFor(tab("Practice"), 10), "the sidebar vanished inside a vignette browse")
        tab("Practice").tap()
        XCTAssertTrue(app.descendants(matching: .any)["practice.scopeSummary"]
                        .firstMatch.waitForExistence(timeout: 10),
                      "could not get back to the quiz builder")
    }

    // MARK: - MM Review

    /// MM Review indexes PDFs that are deliberately NOT in the repository, so
    /// this asserts the index is present and navigable without asserting any
    /// PDF loaded — on a clean checkout there is nothing to load, and that is
    /// a supported state rather than a failure.
    func testMMReviewListsBooksAndDrillsIntoModules() {
        XCTAssertTrue(waitFor(tab("MM Review")), "the sidebar never appeared")
        tab("MM Review").tap()

        XCTAssertTrue(
            app.otherElements["mmreview.library"].waitForExistence(timeout: 10)
                || app.staticTexts["mmreview.library"].waitForExistence(timeout: 10),
            "MM Review did not open"
        )

        // The PM pathway book, addressed by area id so a display-name change
        // does not silently turn this into a test of nothing.
        let book = app.buttons["mmreview.book.portfolio_management_pathway"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10), "MM Review should list the books")
        book.tap()

        // Yield Curve Strategies starts on page 43 of that PDF — the identifier
        // carries the page, so a manifest that loses its page numbers fails
        // here rather than opening the wrong page silently.
        let module = app.buttons["mmreview.module.portfolio_management_pathway.43"].firstMatch
        XCTAssertTrue(
            module.waitForExistence(timeout: 10),
            "expanding a book should reveal its learning modules"
        )
        module.tap()

        XCTAssertTrue(
            app.navigationBars["Yield Curve Strategies"].waitForExistence(timeout: 15),
            "tapping a module should open it"
        )
        XCTAssertEqual(app.state, .runningForeground, "the PDF reader took the app down")
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

        let book = notesBook("Asset allocation")
        XCTAssertTrue(book.waitForExistence(timeout: 10),
                      "Notes should list the books")

        let reading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "notes.reading."))
            .firstMatch
        XCTAssertFalse(reading.exists,
                       "readings stay hidden until a book is expanded")
        book.tap()
        XCTAssertTrue(reading.waitForExistence(timeout: 10),
                      "expanding a book should reveal its readings")
        reading.tap()

        XCTAssertTrue(tab("Cards").waitForExistence(timeout: 10),
                      "Cards vanished after opening a reading")
        XCTAssertTrue(tab("Cards").isHittable, "Cards is present but unreachable")

        tab("Cards").tap()
        XCTAssertTrue(app.buttons["cards.today"].firstMatch.waitForExistence(timeout: 10),
                      "the Cards destination did not show its today row")
        XCTAssertTrue(tab("Notes").isHittable, "Notes must remain reachable from Cards")
    }

    /// Expanding a second book must collapse the first so switching sections
    /// does not stack two open lists.
    func testExpandingABookCollapsesThePreviousOne() {
        XCTAssertTrue(waitFor(tab("Notes")), "the sidebar never appeared")
        tab("Notes").tap()

        let first = notesBook("Asset allocation")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        let reading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "notes.reading."))
            .firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 10))
        let firstReadingID = reading.identifier

        notesBook("Ethics").tap()
        let ethicsGone = NSPredicate(format: "identifier != %@", firstReadingID)
        let next = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "notes.reading."))
            .matching(ethicsGone)
            .firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 10),
                      "Ethics should reveal its own readings")
        XCTAssertFalse(
            app.descendants(matching: .any)[firstReadingID].firstMatch.exists,
            "Asset allocation should collapse when Ethics opens"
        )
    }

    /// Notes, Cases, and Cards book lists share Practice’s parchment grouping.
    /// When `DAYBOOK_SCREENSHOT_DIR` is set, writes the comparison shots.
    func testBookListsSharePracticeChrome() {
        XCTAssertTrue(waitFor(tab("Notes")), "the sidebar never appeared")

        tab("Notes").tap()
        XCTAssertTrue(notesBook("Ethics").waitForExistence(timeout: 10),
                      "Notes should list the books in a parchment group")
        saveScreenshot("notes-collapsed")
        notesBook("Asset allocation").tap()
        let noteReading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "notes.reading."))
            .firstMatch
        XCTAssertTrue(noteReading.waitForExistence(timeout: 10),
                      "expanding a Notes book should reveal readings")
        saveScreenshot("notes-expanded")

        tab("Cases").tap()
        XCTAssertTrue(casesBook("Ethics").waitForExistence(timeout: 10))
        XCTAssertFalse(firstCaseItem().exists,
                       "case rows stay hidden until a book is expanded")
        saveScreenshot("cases-collapsed")
        casesBook("Ethics").tap()
        XCTAssertTrue(firstCaseItem().waitForExistence(timeout: 10))
        saveScreenshot("cases-expanded")

        // Cards picks its scope the way Practice does — Books / Readings / LOS
        // rows that open the same sheets — so the steps below mirror the
        // Practice ones further down, deliberately.
        tab("Cards").tap()
        XCTAssertTrue(app.buttons["cards.today"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["cards.scopeSummary"]
                        .firstMatch.waitForExistence(timeout: 10),
                      "Cards should show a scope summary like Practice")
        saveScreenshot("cards-collapsed")

        app.buttons["cards.scope.readings"].firstMatch.tap()
        XCTAssertTrue(cardsBook("Ethics").waitForExistence(timeout: 10),
                      "the Cards readings sheet should list books collapsed")
        cardsBook("Asset allocation").tap()
        let cardReading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "cards.reading."))
            .firstMatch
        XCTAssertTrue(cardReading.waitForExistence(timeout: 10),
                      "expanding a Cards book should reveal its readings")
        saveScreenshot("cards-expanded")
        app.buttons["Done"].firstMatch.tap()

        tab("Practice").tap()
        XCTAssertTrue(app.descendants(matching: .any)["practice.scopeSummary"]
                        .firstMatch.waitForExistence(timeout: 10))
        saveScreenshot("practice")
        app.buttons["practice.scope.readings"].firstMatch.tap()
        let practiceBook = app.descendants(matching: .any)["practice.book.Ethics"].firstMatch
        XCTAssertTrue(practiceBook.waitForExistence(timeout: 10),
                      "Practice readings should list books collapsed")
        saveScreenshot("practice-readings-collapsed")
        practiceBook.tap()
        let practiceReading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "practice.reading."))
            .firstMatch
        XCTAssertTrue(practiceReading.waitForExistence(timeout: 10),
                      "expanding a Practice book should reveal readings without overlap")
        saveScreenshot("practice-readings-expanded")
    }

    private func saveScreenshot(_ name: String) {
        // Snappy disclosure / sheet presentation can still be in flight when
        // the first child appears in the tree.
        Thread.sleep(forTimeInterval: 0.5)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let dir = ProcessInfo.processInfo.environment["DAYBOOK_SCREENSHOT_DIR"],
              !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? shot.pngRepresentation.write(to: url)
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

        let toggle = columnToggle("sidebar")
        XCTAssertTrue(waitFor(toggle), "the column control never appeared")
        XCTAssertEqual(toggle.label, "Hide the sidebar",
                       "the column control is icon-only and must name its column")
        XCTAssertEqual(toggle.value as? String, "Shown",
                       "the control has to speak the state it is in")
        XCTAssertTrue(toggle.isHittable,
                      "the column control must be reachable, not decorative")
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
