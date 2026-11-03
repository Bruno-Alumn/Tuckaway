//
//  ChosenAppsLayoutTests.swift
//  TuckawayUnitTests
//

import XCTest

// The App Store build can't read where the icons are, so the user names the apps
// to keep visible and a section becomes a name rather than a position.
final class ChosenAppsLayoutTests: XCTestCase {
    private func item(_ bundle: String?, x: CGFloat = 100) -> MenuBarInventoryItem {
        MenuBarInventoryItem(bundleIdentifier: bundle, frame: CGRect(x: x, y: 0, width: 24, height: 24))
    }

    func testNamedAppsAreVisibleAndTheRestHidden() {
        let layout = MenuBarLayoutResolver.fromChosenApps(
            [item("com.keep"), item("com.hide"), item("com.other")],
            visible: ["com.keep"], excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.keep": .visible, "com.hide": .hidden, "com.other": .hidden])
    }

    // Positions say nothing here; the list is the only thing that decides.
    func testPositionsAreIgnored() {
        let layout = MenuBarLayoutResolver.fromChosenApps(
            [item("com.keep", x: 1500), item("com.hide", x: 100)],
            visible: ["com.keep"], excludingBundle: nil)
        XCTAssertEqual(layout.bundles(in: [.visible]), ["com.keep"])
        XCTAssertEqual(layout.bundles(in: [.hidden]), ["com.hide"])
    }

    func testTuckawayAndMacOSOwnItemsAreLeftOut() {
        let layout = MenuBarLayoutResolver.fromChosenApps(
            [item("com.keep"), item("com.brunoalumn.tuckaway"), item("com.apple.MenuBarAgent"), item(nil)],
            visible: ["com.keep"], excludingBundle: "com.brunoalumn.tuckaway")
        XCTAssertEqual(layout.sections, ["com.keep": .visible])
    }

    func testAnEmptyListHidesEverythingThatIsThere() {
        let layout = MenuBarLayoutResolver.fromChosenApps([item("com.a"), item("com.b")], visible: [], excludingBundle: nil)
        XCTAssertEqual(layout.bundles(in: [.visible]), [])
        XCTAssertEqual(layout.bundles(in: [.hidden]), ["com.a", "com.b"])
    }
}
