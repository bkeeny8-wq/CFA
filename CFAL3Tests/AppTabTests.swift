import XCTest
@testable import CFAL3

/// The phone's tab bar is built from a hand-written order, not from
/// `allCases`, so the two can drift apart silently.
final class AppTabTests: XCTestCase {

    /// Every destination reaches the phone.
    ///
    /// `compactOrder` is written out by hand because the tab bar's first four
    /// slots are chosen for commute work rather than for the sidebar's reading
    /// order. That means a tenth `AppTab` added later is not picked up here:
    /// it would keep its sidebar row on iPad and simply not exist on the
    /// phone, with nothing to notice it — no crash, no blank screen, just a
    /// destination you cannot reach.
    func testEveryTabAppearsInTheCompactOrder() {
        XCTAssertEqual(
            Set(AppTab.compactOrder), Set(AppTab.allCases),
            "compactOrder and allCases have drifted: "
            + "\(Set(AppTab.allCases).symmetricDifference(Set(AppTab.compactOrder)))"
        )
        XCTAssertEqual(
            AppTab.compactOrder.count, AppTab.allCases.count,
            "compactOrder lists a destination twice"
        )
    }

    /// The four visible slots are the ones a commute leg needs.
    ///
    /// iOS shows four tabs and folds the rest into More. The plan puts 128
    /// commute legs on a phone, all of them drills from this app's own bank,
    /// so Practice and Cards have to be reachable without opening More.
    func testTheVisibleTabsAreTheOnesAPhoneIsFor() {
        let visible = AppTab.compactOrder.prefix(4)
        XCTAssertTrue(visible.contains(.today), "Today should not be behind More")
        XCTAssertTrue(visible.contains(.practice), "Practice is the commute leg")
        XCTAssertTrue(visible.contains(.cards), "Cards is the other phone-sized sitting")
        XCTAssertFalse(
            visible.contains(.mmReview),
            "MM Review is desk work — it reads PDFs — and should be in More"
        )
    }

    /// Identifiers are the contract UI tests address tabs by, and a space in a
    /// title would produce "tab.mm review".
    func testIdentifiersAreStableAndSpaceFree() {
        for tab in AppTab.allCases {
            XCTAssertFalse(
                tab.identifier.contains(" "),
                "\(tab.identifier) has a space in it"
            )
            XCTAssertTrue(tab.identifier.hasPrefix("tab."), tab.identifier)
        }
        XCTAssertEqual(AppTab.mmReview.identifier, "tab.mmreview")
        XCTAssertEqual(
            Set(AppTab.allCases.map(\.identifier)).count,
            AppTab.allCases.count,
            "two tabs share an identifier"
        )
    }
}
