//
//  MenuBarEngineTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import XCTest

// The engine sources are compiled straight into this bundle (no host app), so
// the tests never put items in the real menu bar, never need Accessibility, and
// never touch the private visibility API.

// MARK: - Fakes

private final class FakeItems: MenuBarItemProvider {
    private let bar: NSStatusBar
    let toggleItem: NSStatusItem
    let separatorItem: NSStatusItem
    var alwaysHiddenItem: NSStatusItem?

    init() {
        // This test bundle has no host app. Bootstrap AppKit before creating
        // status items so older macOS versions have a WindowServer connection.
        _ = NSApplication.shared
        bar = NSStatusBar()
        toggleItem = bar.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem = bar.statusItem(withLength: 1)
        alwaysHiddenItem = bar.statusItem(withLength: 20)
    }
}

private final class FakeInventory: MenuBarInventoryProviding {
    var isAuthorized = true
    var items: [MenuBarInventoryItem] = []
    var authorizationRequests = 0
    var snapshots = 0

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void) {
        snapshots += 1
        completion(items)
    }
}

private final class FakeAssertion: NativeVisibilityAssertion {
    let allowed: [String]
    private(set) var isInvalidated = false
    var onInvalidate: (() -> Void)?

    init(allowed: [String]) {
        self.allowed = allowed
    }

    func invalidate() {
        isInvalidated = true
        onInvalidate?()
    }
}

// Hands every activation to the test, which decides when and how it completes.
private final class FakeVisibility: NativeVisibilityProviding {
    struct Request {
        let systemItems: [Int]
        let bundles: [String]
        let completion: (Result<NativeVisibilityAssertion, Error>) -> Void
    }

    var isAvailable = true
    var requests: [Request] = []

    func activate(allowedSystemItems: [Int],
                  allowedBundleIdentifiers: [String],
                  completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void) {
        requests.append(Request(systemItems: allowedSystemItems, bundles: allowedBundleIdentifiers, completion: completion))
    }

    @discardableResult
    func succeed(_ index: Int) -> FakeAssertion {
        let assertion = FakeAssertion(allowed: requests[index].bundles)
        requests[index].completion(.success(assertion))
        return assertion
    }

    func fail(_ index: Int) {
        requests[index].completion(.failure(NSError(domain: "test", code: 1)))
    }
}

private final class FakeCaptureActivity: CaptureActivityMonitoring {
    var isActive = false
    var onChange: (() -> Void)?

    func set(_ active: Bool) {
        isActive = active
        onChange?()
    }
}

// Stands in for the menu-bar clock: the test clicks it and decides when a press
// has been handled.
private final class FakeClock: MenuBarClockProviding {
    var onClick: ((CGPoint) -> Void)?
    var presses: [(location: CGPoint, completion: () -> Void)] = []

    func press(at location: CGPoint, completion: @escaping () -> Void) {
        presses.append((location, completion))
    }

    func click(at location: CGPoint = CGPoint(x: 1900, y: 12)) {
        onClick?(location)
    }
}

private func item(_ bundle: String?, x: CGFloat, width: CGFloat = 24) -> MenuBarInventoryItem {
    return MenuBarInventoryItem(bundleIdentifier: bundle, frame: CGRect(x: x, y: 0, width: width, height: 24))
}

// LTR bar used throughout: always-hidden separator at 1000, the boundary at 1300
// (the separator for the resolver, the arrow for the native engine).
private let alwaysHiddenSeparator = CGRect(x: 1000, y: 0, width: 20, height: 24)
private let separator = CGRect(x: 1300, y: 0, width: 20, height: 24)
private let mainDisplay = MenuBarDisplay(identifier: "main",
                                         appKitFrame: CGRect(x: 0, y: 0, width: 2000, height: 1000),
                                         accessibilityFrame: CGRect(x: 0, y: 0, width: 2000, height: 1000))

// MARK: - Layout resolver

final class MenuBarLayoutResolverTests: XCTestCase {
    func testLTRSectionsFollowSeparators() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: alwaysHiddenSeparator, displays: [mainDisplay],
            isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout?.sections, ["com.always": .alwaysHidden, "com.hidden": .hidden, "com.visible": .visible])
    }

    func testRTLSectionsAreMirrored() {
        // RTL: arrow on the left, separator just right of it, hidden further right.
        let rtlSeparator = CGRect(x: 300, y: 0, width: 20, height: 24)
        let rtlAlwaysHidden = CGRect(x: 600, y: 0, width: 20, height: 24)
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.visible", x: 200), item("com.hidden", x: 450), item("com.always", x: 700)],
            separatorFrame: rtlSeparator, alwaysHiddenSeparatorFrame: rtlAlwaysHidden, displays: [mainDisplay],
            isLTR: false, excludingBundle: nil)
        XCTAssertEqual(layout?.sections, ["com.always": .alwaysHidden, "com.hidden": .hidden, "com.visible": .visible])
    }

    func testWithoutAlwaysHiddenSeparatorEverythingLeftIsHidden() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.far", x: 100), item("com.near", x: 1200)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: nil, displays: [mainDisplay],
            isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout?.sections, ["com.far": .hidden, "com.near": .hidden])
    }

    func testMostVisibleItemWinsForABundle() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.split", x: 1100), item("com.split", x: 1400),
                        item("com.pair", x: 900), item("com.pair", x: 1100)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: alwaysHiddenSeparator, displays: [mainDisplay],
            isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout?.sections["com.split"], .visible)
        XCTAssertEqual(layout?.sections["com.pair"], .hidden)
    }

    func testSkipsOwnSystemAndUnidentifiedItems() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.brunoalumn.tuckaway", x: 1100), item("com.apple.MenuBarAgent", x: 1100),
                        item(nil, x: 1100), item("com.app", x: 1100)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: nil, displays: [mainDisplay],
            isLTR: true, excludingBundle: "com.brunoalumn.tuckaway")
        XCTAssertEqual(layout?.sections, ["com.app": .hidden])
    }

    func testBundlesAreFilteredAndSorted() {
        let layout = MenuBarLayout(sections: ["b": .visible, "a": .visible, "c": .hidden, "d": .alwaysHidden])
        XCTAssertEqual(layout.bundles(in: [.visible]), ["a", "b"])
        XCTAssertEqual(layout.bundles(in: [.visible, .hidden]), ["a", "b", "c"])
    }

    func testVisibleOnEitherDisplayWinsForABundle() {
        let builtIn = MenuBarDisplay(identifier: "built-in",
                                     appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     accessibilityFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let external = MenuBarDisplay(identifier: "external",
                                     appKitFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                                     accessibilityFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
        // The arrow is 200 points from the right edge of the built-in display.
        // It therefore projects to x=3872 on the external display, not x=1310.
        let boundary = CGRect(x: 1300, y: 950, width: 20, height: 24)
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.visible.somewhere", x: 1400),
                        MenuBarInventoryItem(bundleIdentifier: "com.visible.somewhere", frame: CGRect(x: 3900, y: 12, width: 24, height: 24)),
                        MenuBarInventoryItem(bundleIdentifier: "com.hidden.everywhere", frame: CGRect(x: 3700, y: 12, width: 24, height: 24))],
            separatorFrame: boundary, alwaysHiddenSeparatorFrame: nil,
            displays: [builtIn, external], isLTR: true, excludingBundle: nil)

        XCTAssertEqual(layout?.sections["com.visible.somewhere"], .visible)
        XCTAssertEqual(layout?.sections["com.hidden.everywhere"], .hidden)
    }

    func testUnassignedThirdPartyItemMakesLayoutUnavailable() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [MenuBarInventoryItem(bundleIdentifier: "com.unknown", frame: CGRect(x: 5000, y: 0, width: 24, height: 24))],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: nil,
            displays: [mainDisplay], isLTR: true, excludingBundle: nil)
        XCTAssertNil(layout)
    }

    func testUnreadableAppFailsOpenToVisible() {
        let unreadable = MenuBarInventoryItem(bundleIdentifier: "com.busy.app", frame: .zero, isUnreadable: true)
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [unreadable, item("com.hidden", x: 1100)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: nil,
            displays: [mainDisplay], isLTR: true, excludingBundle: nil)

        XCTAssertEqual(layout?.sections["com.busy.app"], .visible)
        XCTAssertEqual(layout?.sections["com.hidden"], .hidden)
    }

    func testUnreadableAppWinsOverAReadableHiddenItem() {
        let unreadable = MenuBarInventoryItem(bundleIdentifier: "com.busy.app", frame: .zero, isUnreadable: true)
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.busy.app", x: 1100), unreadable],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: nil,
            displays: [mainDisplay], isLTR: true, excludingBundle: nil)

        XCTAssertEqual(layout?.sections["com.busy.app"], .visible)
    }
}

// MARK: - Native engine

final class NativeVisibilityEngineTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var capture: FakeCaptureActivity!
    private var clock: FakeClock!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        capture = FakeCaptureActivity()
        clock = FakeClock()
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      captureActivity: capture, clock: clock,
                                      ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                      itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true })
    }

    func testCollapseKeepsOnlyVisibleAppsAndSystemItems() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        XCTAssertEqual(engine.state, .calibrating)
        XCTAssertEqual(visibility.requests.first?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
        XCTAssertEqual(visibility.requests.first?.systemItems, NativeVisibilityEngine.systemItemsToKeep)
        XCTAssertFalse(items.separatorItem.isVisible, "the arrow is the boundary; no separator needed")

        visibility.succeed(0)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(results, [.collapsed])

        engine.expand()
        XCTAssertFalse(items.separatorItem.isVisible)
    }

    func testAlwaysHiddenSeparatorFollowsTheSectionSetting() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: false, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)

        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)

        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)

        engine.expand()
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
    }

    // Hiding the always-hidden section takes its separator with it, as it did
    // before macOS 27; it only goes once the icons are actually hidden.
    func testAlwaysHiddenSeparatorHidesWithItsSection() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)

        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20, "read where it is before hiding anything")
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)
        XCTAssertEqual(items.alwaysHiddenItem?.isVisible, false, "out of the bar, not just zero width")

        engine.collapse { _ in }
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0, "does not flash while collapsing")
        visibility.succeed(visibility.requests.count - 1)

        engine.expand()
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0, "does not flash while expanding")
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)

        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
        XCTAssertEqual(items.alwaysHiddenItem?.isVisible, true)
    }

    // Enabling the section while collapsed creates a fresh, visible separator;
    // it must leave the bar like the rest of the collapsed section.
    func testAlwaysHiddenSeparatorEnabledWhileCollapsedStaysOutOfTheBar() {
        let engine = makeEngine()
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)

        items.alwaysHiddenItem?.isVisible = true
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)
        XCTAssertEqual(items.alwaysHiddenItem?.isVisible, false)

        engine.expand()
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
        XCTAssertEqual(items.alwaysHiddenItem?.isVisible, true)
    }

    func testAlwaysHiddenSeparatorStaysWhenItsSectionCannotBeHidden() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.fail(visibility.requests.count - 1)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
    }

    func testUnavailableAPIFailsOpen() {
        visibility.isAvailable = false
        let engine = makeEngine()
        var result: CollapseResult?
        engine.collapse { result = $0 }

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .unavailable)
        XCTAssertTrue(visibility.requests.isEmpty)
    }

    func testMissingAccessibilityAsksAndRetriesLater() {
        inventory.isAuthorized = false
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        XCTAssertEqual(results, [.unavailable])
        XCTAssertEqual(inventory.authorizationRequests, 1)
        XCTAssertTrue(visibility.requests.isEmpty, "never guess which icons to hide")

        inventory.isAuthorized = true
        engine.collapse { results.append($0) }
        XCTAssertEqual(visibility.requests.count, 1, "works once the permission is granted")
    }

    func testActivationFailureReportsUnavailable() {
        let engine = makeEngine()
        var result: CollapseResult?
        engine.collapse { result = $0 }
        visibility.fail(0)

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0, "the always-hidden separator only shows when enabled")
    }

    // Timeouts are fired by hand: spinning the run loop here lets AppKit tear
    // down earlier tests' status items mid-test.
    private func makeEngine(timeouts: @escaping (@escaping () -> Void) -> Void) -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      captureActivity: capture, clock: clock,
                                      ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                      itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true },
                                      afterActivationTimeout: timeouts)
    }

    func testUnansweredActivationTimesOutSoTheNextCollapseWorks() {
        var timeouts: [() -> Void] = []
        let engine = makeEngine { timeouts.append($0) }
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        XCTAssertEqual(engine.state, .calibrating)

        timeouts[0]()
        XCTAssertEqual(results, [.unavailable])
        XCTAssertEqual(engine.state, .expanded)

        // The next collapse is no longer swallowed, and a late answer to the
        // first one is thrown away.
        engine.collapse { results.append($0) }
        XCTAssertEqual(visibility.requests.count, 2)
        let late = visibility.succeed(0)
        XCTAssertTrue(late.isInvalidated)
        visibility.succeed(1)
        XCTAssertEqual(results, [.unavailable, .collapsed])
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testAnsweredActivationDoesNotTimeOut() {
        var timeouts: [() -> Void] = []
        let engine = makeEngine { timeouts.append($0) }
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        visibility.succeed(0)

        timeouts[0]()
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testExpandDropsTheRestriction() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        engine.expand()
        XCTAssertTrue(collapsed.isInvalidated)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(visibility.requests.count, 1)
    }

    func testExpandKeepsAlwaysHiddenSectionHiddenAndSwapsWithoutFlashing() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        // Expanded with separators hidden: everything but always-hidden is shown.
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
        visibility.succeed(visibility.requests.count - 1)

        engine.collapse { _ in }
        let collapseIndex = visibility.requests.count - 1
        XCTAssertEqual(visibility.requests[collapseIndex].bundles, ["com.brunoalumn.tuckaway", "com.visible"])
        let collapsed = visibility.succeed(collapseIndex)

        var newIsActiveWhenOldDropped = false
        collapsed.onInvalidate = { newIsActiveWhenOldDropped = true }
        engine.expand()
        let expandIndex = visibility.requests.count - 1
        XCTAssertEqual(visibility.requests[expandIndex].bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
        XCTAssertFalse(collapsed.isInvalidated, "the old restriction stays until the new one is active")
        visibility.succeed(expandIndex)
        XCTAssertTrue(newIsActiveWhenOldDropped)
    }

    func testSectionsAreNotReadWhileSomethingIsHidden() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)
        let snapshotsBefore = inventory.snapshots

        // Hidden items would report stale positions now; the cached layout is used.
        inventory.items = [item("com.visible", x: 100)]
        engine.collapse { _ in }
        XCTAssertEqual(inventory.snapshots, snapshotsBefore)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }

    func testExpandDuringActivationDropsTheLateResult() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        engine.expand()
        let late = visibility.succeed(0)

        XCTAssertTrue(late.isInvalidated, "a restriction nobody wants any more is released")
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(results, [])
    }

    func testDisplayChangeFailsOpenUntilTheNextFreshSnapshot() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        engine.invalidateLayout()
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertTrue(collapsed.isInvalidated)
    }

    // MARK: Microphone and camera (#437)

    func testCollapseWhileCapturingHoldsNoRestriction() {
        capture.isActive = true
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        XCTAssertEqual(results, [.collapsed], "the bar keeps the state the user asked for")
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertTrue(visibility.requests.isEmpty, "assessment mode would hide the recording indicators")
    }

    func testCaptureStartingWhileCollapsedDropsTheRestriction() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        capture.set(true)
        XCTAssertTrue(collapsed.isInvalidated)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(visibility.requests.count, 1)
    }

    func testCaptureStoppingHidesAgainFromAFreshRead() {
        let engine = makeEngine()
        engine.collapse { _ in }
        visibility.succeed(0)
        capture.set(true)
        let snapshotsBefore = inventory.snapshots

        // The bar is unrestricted while capturing, so the sections are re-read.
        inventory.items = [item("com.hidden", x: 1100), item("com.moved", x: 1400)]
        capture.set(false)
        XCTAssertEqual(inventory.snapshots, snapshotsBefore + 1)
        XCTAssertEqual(visibility.requests.count, 2)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.moved"])
        let restored = visibility.succeed(1)
        XCTAssertFalse(restored.isInvalidated)
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testExpandWhileCapturingThenStoppingRestoresTheExpandedPresentation() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)
        engine.collapse { _ in }
        let collapsed = visibility.succeed(visibility.requests.count - 1)

        capture.set(true)
        XCTAssertTrue(collapsed.isInvalidated)
        let requestsWhileCapturing = visibility.requests.count
        engine.expand()
        XCTAssertEqual(visibility.requests.count, requestsWhileCapturing, "nothing is hidden while capturing, not even always-hidden")

        capture.set(false)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
    }

    func testCaptureStartingDuringActivationDropsTheResultButStillCollapses() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        capture.set(true)
        let late = visibility.succeed(0)

        XCTAssertTrue(late.isInvalidated)
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testUnchangedCaptureStateLeavesTheRestrictionAlone() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        capture.set(false)
        XCTAssertFalse(collapsed.isInvalidated)
        XCTAssertEqual(visibility.requests.count, 1)
    }

    // MARK: Clock → Notification Center (#410)

    func testClockIsWatchedOnlyWhileARestrictionIsHeld() {
        let engine = makeEngine()
        XCTAssertNil(clock.onClick)

        engine.collapse { _ in }
        XCTAssertNil(clock.onClick, "nothing is restricted until the activation lands")
        visibility.succeed(0)
        XCTAssertNotNil(clock.onClick)

        engine.expand()
        XCTAssertNil(clock.onClick, "an unrestricted clock opens Notification Center by itself")
    }

    func testClockClickLiftsTheRestrictionAroundAPress() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        let location = CGPoint(x: 1950, y: 12)
        clock.click(at: location)
        XCTAssertTrue(collapsed.isInvalidated, "macOS ignores the clock while restricted")
        XCTAssertEqual(clock.presses.count, 1)
        XCTAssertEqual(clock.presses.first?.location, location)
        XCTAssertEqual(visibility.requests.count, 1, "the restriction comes back only after the press")

        clock.presses[0].completion()
        XCTAssertEqual(visibility.requests.count, 2)
        XCTAssertEqual(visibility.requests[1].bundles, visibility.requests[0].bundles, "the same apps stay visible")
        visibility.succeed(1)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertNotNil(clock.onClick, "the next click is handled the same way")
    }

    func testClockClickWhileExpandedKeepsTheAlwaysHiddenSectionHidden() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        let expanded = visibility.succeed(visibility.requests.count - 1)

        clock.click()
        XCTAssertTrue(expanded.isInvalidated)
        clock.presses[0].completion()
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
    }

    func testExpandDuringAClockPressIsNotUndone() {
        let engine = makeEngine()
        engine.collapse { _ in }
        visibility.succeed(0)

        clock.click()
        engine.expand()
        clock.presses[0].completion()

        XCTAssertEqual(visibility.requests.count, 1, "no restriction comes back after the user expanded")
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertNil(clock.onClick)
    }

    func testClockClickDuringAnActivationLeavesItAlone() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        let expanded = visibility.succeed(visibility.requests.count - 1)
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        // Lifting the held assertion now would cancel the collapse in flight, and
        // a cancelled collapse never reports back.
        clock.click()
        XCTAssertTrue(clock.presses.isEmpty)
        XCTAssertFalse(expanded.isInvalidated)

        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)
    }
}

// MARK: - Legacy engine

final class LegacyLengthEngineTests: XCTestCase {
    func testUsesWidestScreenRegardlessOfDisplayOrder() {
        // Synthetic logical widths, independent of any developer's hardware.
        let configurations: [([CGFloat], CGFloat)] = [
            ([1200], 2400),
            ([800, 1600, 1200], 3200),
            ([2560, 1440, 3840, 1920], 7680)
        ]
        for (configuration, expected) in configurations {
            for widths in [configuration, Array(configuration.reversed())] {
                let items = FakeItems()
                let engine = LegacyLengthEngine(items: items, screenWidths: { widths })
                engine.collapse { _ in }
                XCTAssertEqual(items.separatorItem.length, expected)
            }
        }
    }

    func testDisplayChangesRefreshHiddenSectionsIndependently() {
        // Ordinary expansion must not prevent the always-hidden section from
        // adapting to a newly connected wider display, or to its removal.
        for collapsed in [false, true] {
            for alwaysHiddenEnabled in [false, true] {
                for separatorHidden in [false, true] {
                    let items = FakeItems()
                    var widths: [CGFloat] = [900]
                    let engine = LegacyLengthEngine(items: items, screenWidths: { widths })
                    engine.expand()
                    if collapsed { engine.collapse { _ in } }
                    engine.updateAlwaysHiddenSection(enabled: alwaysHiddenEnabled, separatorHidden: separatorHidden)

                    let transitions: [([CGFloat], CGFloat)] = [
                        ([900, 1800, 1200], 3600), // attach wider screens
                        ([900], 1800),             // detach them
                        ([], 3456),                // temporary empty inventory
                        ([6000], 10000)            // very wide logical display
                    ]
                    for (nextWidths, hiddenLength) in transitions {
                        widths = nextWidths
                        engine.invalidateLayout()
                        let context = "collapsed=\(collapsed), alwaysHidden=\(alwaysHiddenEnabled), separatorHidden=\(separatorHidden), screens=\(widths)"
                        XCTAssertEqual(items.separatorItem.length, collapsed ? hiddenLength : 20, context)
                        XCTAssertEqual(items.alwaysHiddenItem?.length,
                                       alwaysHiddenEnabled ? (separatorHidden ? hiddenLength : 20) : 0, context)
                        XCTAssertEqual(engine.state, collapsed ? .collapsed : .expanded, context)
                    }
                }
            }
        }
    }

    func testRotationAndScalingChangesUseLatestWidths() {
        let items = FakeItems()
        var widths: [CGFloat] = [2400, 1200]
        let engine = LegacyLengthEngine(items: items, screenWidths: { widths })
        engine.collapse { _ in }
        widths = [1350, 2000]
        engine.invalidateLayout()
        XCTAssertEqual(items.separatorItem.length, 4000)
        widths = [1600, 1000]
        engine.invalidateLayout()
        XCTAssertEqual(items.separatorItem.length, 3200)
    }

    func testMissingScreensAndExtremeWidthsStayBounded() {
        for (widths, expected): ([CGFloat], CGFloat) in [([], 3456), ([100], 500), ([8000], 10000)] {
            let items = FakeItems()
            let engine = LegacyLengthEngine(items: items, screenWidths: { widths })
            engine.collapse { _ in }
            XCTAssertEqual(items.separatorItem.length, expected)
        }
    }

    func testCollapseAndExpandFlipSeparatorLength() {
        let items = FakeItems()
        let engine = LegacyLengthEngine(items: items)
        XCTAssertEqual(engine.state, .expanded)

        var result: CollapseResult?
        engine.collapse { result = $0 }
        XCTAssertEqual(result, .collapsed)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20, "collapse leaves the always-hidden item alone")

        engine.expand()
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(items.separatorItem.length, 20)
    }
}

final class ExpandIconStyleTests: XCTestCase {
    func testStylesCoverStandardTransparentAndEllipsis() {
        XCTAssertEqual(ExpandIconStyle.allCases, [.standard, .transparent, .ellipsis])
        XCTAssertEqual(ExpandIconStyle.standard.assetName, "ic_expand")
        XCTAssertEqual(ExpandIconStyle.transparent.assetName, "ic_expand_hidden")
        XCTAssertNil(ExpandIconStyle.ellipsis.assetName)
    }
}

final class CaptureActivityMonitorTests: XCTestCase {
    func testAlwaysOnCoreSpeechListenerIsIgnored() {
        XCTAssertTrue(CaptureActivityMonitor.isAlwaysOnSpeechListener(
            path: "/System/Library/PrivateFrameworks/CoreSpeech.framework/corespeechd"))
    }

    func testOrdinaryAudioProcessesAreNotIgnored() {
        XCTAssertFalse(CaptureActivityMonitor.isAlwaysOnSpeechListener(path: "/Applications/Music.app/Contents/MacOS/Music"))
        XCTAssertFalse(CaptureActivityMonitor.isAlwaysOnSpeechListener(path: "/usr/local/bin/corespeechd"))
    }
}
