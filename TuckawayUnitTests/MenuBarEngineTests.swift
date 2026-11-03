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
    // Set for the sandboxed-build tests, where the sections come from a list of
    // apps instead of the bar's geometry.
    var isDynamicInventory = false
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
    var partialSnapshots = 0
    func snapshot(of bundles: Set<String>, completion: @escaping ([MenuBarInventoryItem]) -> Void) {
        partialSnapshots += 1
        completion(items.filter { $0.bundleIdentifier.map(bundles.contains) ?? false })
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

        // Hidden items would report stale positions now: the always-hidden app
        // isn't re-read (only the shown ones are), and there's no full read.
        inventory.items = [item("com.always", x: 1450), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
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

// MARK: - Separate bar on macOS 27

final class HiddenSectionPeekTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
    }

    private func makeCollapsedEngine() -> NativeVisibilityEngine {
        let items = self.items!
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            captureActivity: FakeCaptureActivity(), clock: FakeClock(),
                                            ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                            itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                            displays: { [mainDisplay] },
                                            isLTR: { true })
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
        return engine
    }

    func testHiddenItemsAreTheHiddenSectionsIcons() {
        let engine = makeCollapsedEngine()
        XCTAssertEqual(engine.hiddenItems, [item("com.hidden", x: 1100)])
    }

    func testPeekShowsTheHiddenSectionAndStaysCollapsed() {
        let engine = makeCollapsedEngine()
        let snapshots = inventory.snapshots
        var results: [Bool] = []
        engine.peekHiddenSection { results.append($0) }

        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(results, [true])
        XCTAssertTrue(engine.isPeeking)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(inventory.snapshots, snapshots, "the cached layout is reused, not re-read")

        engine.endPeek()
        XCTAssertFalse(engine.isPeeking)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }

    func testCollapseWhilePeekingHidesAgain() {
        let engine = makeCollapsedEngine()
        engine.peekHiddenSection { _ in }
        visibility.succeed(visibility.requests.count - 1)

        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        XCTAssertEqual(results, [.collapsed])
        XCTAssertFalse(engine.isPeeking)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }

    func testExpandEndsThePeekWithoutHidingAgain() {
        let engine = makeCollapsedEngine()
        engine.peekHiddenSection { _ in }
        let peek = visibility.succeed(visibility.requests.count - 1)
        let requests = visibility.requests.count

        engine.expand()
        XCTAssertFalse(engine.isPeeking)
        XCTAssertTrue(peek.isInvalidated)
        engine.endPeek()
        XCTAssertEqual(visibility.requests.count, requests)
    }

    func testKeepingAnAppVisibleTakesItOutOfTheSeparateBar() {
        let engine = makeCollapsedEngine()
        engine.resolveNewApp("com.hidden", keepVisible: true)
        XCTAssertEqual(engine.hiddenItems, [])
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
    }

    func testPeekNeedsACollapsedBar() {
        let engine = makeCollapsedEngine()
        engine.expand()
        var results: [Bool] = []
        engine.peekHiddenSection { results.append($0) }
        XCTAssertEqual(results, [false])
        XCTAssertFalse(engine.isPeeking)
    }
}

final class MenuBarStripGeometryTests: XCTestCase {
    func testStripSpansTheIconsAtMenuBarHeight() {
        let frames = [CGRect(x: 1205, y: 7.5, width: 36, height: 24), CGRect(x: 1346, y: 7.5, width: 40, height: 24)]
        XCTAssertEqual(MenuBarStripGeometry.strip(covering: frames, menuBarHeight: 39, on: mainDisplay),
                       CGRect(x: 1205, y: 0, width: 181, height: 39))
        XCTAssertNil(MenuBarStripGeometry.strip(covering: [], menuBarHeight: 39, on: mainDisplay))
    }

    func testPixelRectIsLocalScaledAndClipped() {
        let strip = CGRect(x: 1205, y: 0, width: 181, height: 39)
        XCTAssertEqual(MenuBarStripGeometry.pixelRect(of: CGRect(x: 1285, y: 7.5, width: 24, height: 24), in: strip, scale: 2),
                       CGRect(x: 160, y: 15, width: 48, height: 48))
        XCTAssertEqual(MenuBarStripGeometry.pixelRect(of: CGRect(x: 1380, y: 0, width: 20, height: 39), in: strip, scale: 1),
                       CGRect(x: 175, y: 0, width: 6, height: 39), "kept inside the image")
        XCTAssertNil(MenuBarStripGeometry.pixelRect(of: CGRect(x: 10, y: 0, width: 20, height: 20), in: strip, scale: 2))
    }

    func testAccessibilityAndAppKitRectsRoundTrip() {
        // A second display above the main one: AX y grows downward from the desktop's top.
        let upper = MenuBarDisplay(identifier: "upper",
                                   appKitFrame: CGRect(x: 0, y: 1000, width: 1600, height: 900),
                                   accessibilityFrame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        let icon = CGRect(x: 1200, y: 4, width: 24, height: 24)
        XCTAssertEqual(upper.appKitRect(fromAccessibility: icon), CGRect(x: 1200, y: 1872, width: 24, height: 24))
        XCTAssertEqual(upper.accessibilityRect(fromAppKit: upper.appKitRect(fromAccessibility: icon)), icon)
    }
}

// MARK: - New menu bar apps

final class NewMenuBarAppTrackerTests: XCTestCase {
    func testFirstReadOnlyRecordsWhatIsThere() {
        var tracker = NewMenuBarAppTracker()
        XCTAssertEqual(tracker.observe(MenuBarLayout(sections: ["com.a": .hidden, "com.b": .visible])), [])
        XCTAssertEqual(tracker.known, ["com.a", "com.b"])
        XCTAssertEqual(tracker.pending, [])
    }

    func testNewAppOnTheHiddenSideStaysVisibleUntilDecided() {
        var tracker = NewMenuBarAppTracker(known: ["com.a"])
        let layout = MenuBarLayout(sections: ["com.a": .hidden, "com.new": .hidden, "com.right": .visible, "com.far": .alwaysHidden])
        XCTAssertEqual(tracker.observe(layout), ["com.far", "com.new"], "a new app already visible needs no question")
        XCTAssertEqual(tracker.applied(to: layout).sections,
                       ["com.a": .hidden, "com.new": .visible, "com.right": .visible, "com.far": .visible])

        XCTAssertEqual(tracker.observe(layout), [], "asked about once")
        tracker.resolve("com.new", keepVisible: false)
        XCTAssertEqual(tracker.applied(to: layout).sections["com.new"], .hidden)

        tracker.resolve("com.far", keepVisible: true)
        XCTAssertEqual(tracker.pending, [])
        XCTAssertEqual(tracker.applied(to: layout).sections["com.far"], .visible, "kept visible wherever its icon is")
        tracker.resolve("com.far", keepVisible: false)
        XCTAssertEqual(tracker.applied(to: layout).sections["com.far"], .alwaysHidden)
    }

    func testStoreRoundTripsThroughUserDefaults() {
        let suite = "NewMenuBarAppTrackerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsNewMenuBarAppStore(defaults: defaults)
        XCTAssertNil(store.tracker.known)

        store.tracker = NewMenuBarAppTracker(known: ["com.a", "com.b", "com.c"], pending: ["com.b"], kept: ["com.c"])
        XCTAssertEqual(UserDefaultsNewMenuBarAppStore(defaults: defaults).tracker,
                       NewMenuBarAppTracker(known: ["com.a", "com.b", "com.c"], pending: ["com.b"], kept: ["com.c"]))
    }
}

final class NativeVisibilityEngineNewAppTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var store: InMemoryNewMenuBarAppStore!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        store = InMemoryNewMenuBarAppStore()
        store.tracker = NewMenuBarAppTracker(known: ["com.hidden", "com.visible"])
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      captureActivity: FakeCaptureActivity(), clock: FakeClock(),
                                      newApps: store,
                                      ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                      itemFrame: { _ in separator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true })
    }

    func testNewAppIsKeptVisibleAndReported() {
        inventory.items.append(item("com.new", x: 1050))
        let engine = makeEngine()
        var reported: [[String]] = []
        engine.onNewApps = { reported.append($0) }

        engine.collapse { _ in }
        XCTAssertEqual(reported, [["com.new"]])
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.new", "com.visible"])
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(engine.hiddenItems, [item("com.hidden", x: 1100)], "not offered in the separate bar while undecided")

        engine.expand()
        engine.collapse { _ in }
        XCTAssertEqual(reported, [["com.new"], ["com.new"]], "still undecided, so asked about again")
    }

    func testHidingANewAppWhileCollapsedHidesItRightAway() {
        inventory.items.append(item("com.new", x: 1050))
        let engine = makeEngine()
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)

        engine.resolveNewApp("com.new", keepVisible: false)
        XCTAssertEqual(store.tracker.pending, [])
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }

    func testKeepingANewAppVisibleSurvivesTheNextRead() {
        inventory.items.append(item("com.new", x: 1050))
        let engine = makeEngine()
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
        engine.resolveNewApp("com.new", keepVisible: true)
        XCTAssertEqual(engine.keptVisibleApps, ["com.new"])

        var reported: [[String]] = []
        engine.onNewApps = { reported.append($0) }
        engine.expand()
        engine.collapse { _ in }
        XCTAssertEqual(reported, [], "decided, so not asked again")
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.new", "com.visible"])
    }
}

// MARK: - Presentation mode

final class PresentationModeTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var capture: FakeCaptureActivity!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        capture = FakeCaptureActivity()
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      captureActivity: capture, clock: FakeClock(),
                                      ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                      itemFrame: { _ in separator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true })
    }

    private func collapsed() -> NativeVisibilityEngine {
        let engine = makeEngine()
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
        return engine
    }

    func testPresentingShowsOnlyTuckaway() {
        let engine = collapsed()
        engine.setPresenting(true)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway"])
        XCTAssertEqual(visibility.requests.last?.systemItems, NativeVisibilityEngine.systemItemsToKeep, "the clock and other system items stay")
    }

    func testExpandingAndCollapsingWhilePresentingChangeNothingUntilItEnds() {
        let engine = collapsed()
        engine.setPresenting(true)
        visibility.succeed(visibility.requests.count - 1)
        let requests = visibility.requests.count

        engine.expand()
        engine.collapse { _ in }
        var peeked: [Bool] = []
        engine.peekHiddenSection { peeked.append($0) }
        XCTAssertEqual(visibility.requests.count, requests)
        XCTAssertEqual(peeked, [false])
        XCTAssertEqual(engine.state, .collapsed)

        engine.setPresenting(false)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }

    func testEndingWhileExpandedShowsEverything() {
        let engine = collapsed()
        engine.setPresenting(true)
        let presenting = visibility.succeed(visibility.requests.count - 1)
        engine.expand()

        engine.setPresenting(false)
        XCTAssertTrue(presenting.isInvalidated)
        XCTAssertEqual(engine.state, .expanded)
    }

    func testCaptureEndingWhilePresentingKeepsPresenting() {
        let engine = collapsed()
        engine.setPresenting(true)
        visibility.succeed(visibility.requests.count - 1)

        capture.set(true)
        capture.set(false)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway"])
    }
}

final class MenuBarItemNamingTests: XCTestCase {
    func testSystemExtrasAreNamedByTheirTitle() {
        XCTAssertEqual(MenuBarItemNaming.displayName(appName: "SystemUIServer", title: "Siri", isSystemExtra: true), "Siri")
        XCTAssertEqual(MenuBarItemNaming.displayName(appName: "SystemUIServer", title: "Item-0", isSystemExtra: true), "SystemUIServer")
        XCTAssertEqual(MenuBarItemNaming.displayName(appName: "LuLu", title: "Firewall", isSystemExtra: false), "LuLu",
                       "other apps keep their own name")
    }

    func testPlaceholderTitlesAreDropped() {
        XCTAssertNil(MenuBarItemNaming.cleanedTitle(" - "))
        XCTAssertNil(MenuBarItemNaming.cleanedTitle(""))
        XCTAssertNil(MenuBarItemNaming.cleanedTitle(nil))
        XCTAssertEqual(MenuBarItemNaming.cleanedTitle("  Siri "), "Siri")
    }
}

final class PresentationModeRobustnessTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var capture: FakeCaptureActivity!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        capture = FakeCaptureActivity()
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      captureActivity: capture, clock: FakeClock(),
                                      ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                      itemFrame: { _ in separator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true })
    }

    // An app launch, a wake or a display change used to drop presentation
    // mode's restriction while it still showed as on.
    func testLayoutChangesKeepPresenting() {
        let engine = makeEngine()
        engine.setPresenting(true)
        let presenting = visibility.succeed(visibility.requests.count - 1)

        engine.invalidateLayout()
        XCTAssertFalse(presenting.isInvalidated)
        XCTAssertTrue(engine.isPresenting)
    }

    func testPresentingDuringACollapseWaitsForIt() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        XCTAssertEqual(engine.state, .calibrating)

        engine.setPresenting(true)
        XCTAssertFalse(engine.isPresenting, "applied once the collapse is answered")
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertTrue(engine.isPresenting)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway"])
    }

    func testPresentingHoldsWhileACameraIsOn() {
        let engine = makeEngine()
        capture.set(true)
        engine.setPresenting(true)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway"], "restricted despite the camera")
        let presenting = visibility.succeed(visibility.requests.count - 1)
        capture.set(false)
        capture.set(true)
        XCTAssertFalse(presenting.isInvalidated)
    }
}

final class NewAppSeparateBarTests: XCTestCase {
    private var visibility: FakeVisibility!
    private var store: InMemoryNewMenuBarAppStore!
    private var items: FakeItems!
    private var inventory: FakeInventory!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.new", x: 1050), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        store = InMemoryNewMenuBarAppStore()
        store.tracker = NewMenuBarAppTracker(known: ["com.hidden", "com.visible"])
    }

    private func collapsedEngine() -> NativeVisibilityEngine {
        let items = self.items!
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            captureActivity: FakeCaptureActivity(), clock: FakeClock(),
                                            newApps: store,
                                            ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                            itemFrame: { _ in separator },
                                            displays: { [mainDisplay] },
                                            isLTR: { true })
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
        return engine
    }

    func testHidingANewAppPutsItInTheSeparateBar() {
        let engine = collapsedEngine()
        XCTAssertEqual(engine.hiddenItems.map(\.bundleIdentifier), ["com.hidden"])
        XCTAssertEqual(engine.keptVisibleApps, ["com.new"], "undecided apps show by name too")

        engine.resolveNewApp("com.new", keepVisible: false)
        XCTAssertEqual(engine.hiddenItems.map(\.bundleIdentifier), ["com.new", "com.hidden"])
        XCTAssertEqual(engine.keptVisibleApps, [])
    }
}

final class MenuBarDisplayInventoryTests: XCTestCase {
    // Accessibility measures from the top of the primary display. A monitor
    // arranged above it must not shift the primary display's frame.
    func testDisplayAboveThePrimaryOneHasNegativeAccessibilityY() {
        let displays = MenuBarDisplayInventory.displays([
            ("laptop", CGRect(x: 0, y: 0, width: 1800, height: 1169)),
            ("monitor", CGRect(x: -200, y: 1169, width: 2560, height: 1440)),
        ])
        XCTAssertEqual(displays[0].accessibilityFrame, CGRect(x: 0, y: 0, width: 1800, height: 1169))
        XCTAssertEqual(displays[1].accessibilityFrame, CGRect(x: -200, y: -1440, width: 2560, height: 1440))
    }

    func testDisplayBesideThePrimaryOneSharesItsTop() {
        let displays = MenuBarDisplayInventory.displays([
            ("laptop", CGRect(x: 0, y: 0, width: 1800, height: 1169)),
            ("monitor", CGRect(x: 1800, y: -271, width: 2560, height: 1440)),
        ])
        XCTAssertEqual(displays[1].accessibilityFrame.minY, 0)
    }
}

final class FreshHiddenFramesTests: XCTestCase {
    func testPeekingRereadsWhereHiddenIconsAreNow() {
        let items = FakeItems()
        let inventory = FakeInventory()
        inventory.items = [item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        let visibility = FakeVisibility()
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            captureActivity: FakeCaptureActivity(), clock: FakeClock(),
                                            ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                            itemFrame: { _ in separator },
                                            displays: { [mainDisplay] },
                                            isLTR: { true })
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)

        var refreshed: [MenuBarInventoryItem] = []
        engine.refreshHiddenItemFrames { refreshed = $0 }
        XCTAssertEqual(inventory.partialSnapshots, 0, "only while peeking")
        XCTAssertEqual(refreshed, [item("com.hidden", x: 1100)])

        engine.peekHiddenSection { _ in }
        visibility.succeed(visibility.requests.count - 1)
        inventory.items = [item("com.hidden", x: 1130), item("com.visible", x: 1400)]
        engine.refreshHiddenItemFrames { refreshed = $0 }
        XCTAssertEqual(inventory.partialSnapshots, 1)
        XCTAssertEqual(refreshed, [item("com.hidden", x: 1130)])
        XCTAssertEqual(engine.hiddenItems, [item("com.hidden", x: 1130)])
    }

    func testCounterpartFollowsAnAppsIconsInOrder() {
        let previous = [item("com.a", x: 100), item("com.a", x: 130), item("com.b", x: 160)]
        let shifted = [item("com.a", x: 120), item("com.a", x: 150), item("com.b", x: 180)]
        XCTAssertEqual(MenuBarStripGeometry.counterpart(of: previous[1], among: shifted, in: previous), shifted[1])
        XCTAssertEqual(MenuBarStripGeometry.counterpart(of: previous[2], among: shifted, in: previous), shifted[2])
        XCTAssertNil(MenuBarStripGeometry.counterpart(of: previous[1], among: [item("com.a", x: 120)], in: previous))
    }
}

final class HiddenIconSearchTests: XCTestCase {
    private let names = ["Dropbox", "LuLu", "Kimi Code", "Tailscale", "Bartender Café"]

    func testEmptyQueryKeepsEveryIconInOrder() {
        XCTAssertEqual(HiddenIconSearch.matches(names, query: " ", name: { $0 }), names)
    }

    func testNamesStartingWithTheQueryComeFirst() {
        XCTAssertEqual(HiddenIconSearch.matches(names, query: "l", name: { $0 }), ["LuLu", "Tailscale"])
        XCTAssertEqual(HiddenIconSearch.matches(names, query: "code", name: { $0 }), ["Kimi Code"])
    }

    func testCaseAndAccentsDontMatter() {
        XCTAssertEqual(HiddenIconSearch.matches(names, query: "CAFE", name: { $0 }), ["Bartender Café"])
        XCTAssertEqual(HiddenIconSearch.matches(names, query: "zzz", name: { $0 }), [])
    }
}

final class ActiveAppIconTests: XCTestCase {
    private var visibility: FakeVisibility!
    private var engine: NativeVisibilityEngine!
    // The engine holds its items weakly.
    private var items: FakeItems!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        let inventory = FakeInventory()
        inventory.items = [item("com.hidden", x: 1100), item("com.other", x: 1150), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                        captureActivity: FakeCaptureActivity(), clock: FakeClock(),
                                        ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                        itemFrame: { _ in separator },
                                        displays: { [mainDisplay] },
                                        isLTR: { true })
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
    }

    func testTheFrontmostHiddenAppIsShownUntilAnotherComesForward() {
        engine.setActiveApp("com.hidden")
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
        XCTAssertEqual(engine.hiddenItems.map(\.bundleIdentifier), ["com.other"], "not offered in the separate bar meanwhile")

        engine.setActiveApp("com.other")
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.other", "com.visible"])

        engine.setActiveApp(nil)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }

    func testAppsThatChangeNothingDontRedoTheRestriction() {
        let requests = visibility.requests.count
        engine.setActiveApp("com.visible")
        engine.setActiveApp("com.not.in.bar")
        XCTAssertEqual(visibility.requests.count, requests)
    }

    func testPresentationModeWins() {
        engine.setPresenting(true)
        visibility.succeed(visibility.requests.count - 1)
        let requests = visibility.requests.count
        engine.setActiveApp("com.hidden")
        XCTAssertEqual(visibility.requests.count, requests)
    }
}

final class MenuBarProfilesTests: XCTestCase {
    func testSavingSwitchingAndDeleting() {
        var profiles = MenuBarProfiles()
        profiles.save("Work", apps: ["com.slack", "com.calendar"])
        profiles.active = "Work"
        XCTAssertEqual(profiles.activeApps, ["com.slack", "com.calendar"])
        profiles.addToActive("com.zoom")
        XCTAssertEqual(profiles.profiles["Work"], ["com.calendar", "com.slack", "com.zoom"])
        profiles.removeFromActive("com.slack")
        XCTAssertEqual(profiles.profiles["Work"], ["com.calendar", "com.zoom"])
        profiles.delete("Work")
        XCTAssertNil(profiles.active)
        XCTAssertNil(profiles.activeApps)
    }

    func testRenamingMovesEveryReferenceToTheProfile() {
        var profiles = MenuBarProfiles(profiles: ["Work": ["com.a"], "Home": ["com.b"]], active: "Work",
                                       displayProfile: "Work", beforeDisplay: .from("Work"))
        XCTAssertTrue(profiles.rename("Work", to: "Office"))
        XCTAssertEqual(profiles, MenuBarProfiles(profiles: ["Office": ["com.a"], "Home": ["com.b"]], active: "Office",
                                                 displayProfile: "Office", beforeDisplay: .from("Office")))
    }

    func testRenamingRefusesATakenOrEmptyName() {
        var profiles = MenuBarProfiles(profiles: ["Work": ["com.a"], "Home": ["com.b"]], active: "Home")
        let before = profiles
        XCTAssertFalse(profiles.rename("Work", to: "Home"))
        XCTAssertFalse(profiles.rename("Work", to: ""))
        XCTAssertFalse(profiles.rename("Missing", to: "New"))
        XCTAssertEqual(profiles, before)
        XCTAssertTrue(profiles.rename("Work", to: "Work"))
        XCTAssertEqual(profiles, before)
    }

    func testSettingAppsOnlyChangesAnExistingProfile() {
        var profiles = MenuBarProfiles(profiles: ["Work": ["com.a"]])
        profiles.setApps(["com.c", "com.b"], for: "Work")
        profiles.setApps(["com.d"], for: "Missing")
        XCTAssertEqual(profiles.profiles, ["Work": ["com.b", "com.c"]])
    }

    func testAScheduleWindowCanRunPastMidnight() {
        let day = ProfileSchedule(start: 9 * 60, end: 17 * 60)
        XCTAssertTrue(day.contains(9 * 60))
        XCTAssertFalse(day.contains(17 * 60))
        XCTAssertFalse(day.contains(8 * 60 + 59))
        let night = ProfileSchedule(start: 22 * 60, end: 7 * 60)
        XCTAssertTrue(night.contains(23 * 60))
        XCTAssertTrue(night.contains(0))
        XCTAssertFalse(night.contains(12 * 60))
        XCTAssertFalse(ProfileSchedule(start: 600, end: 600).contains(600))
    }

    func testTheScheduleSwitchesInAndBackOut() {
        var profiles = MenuBarProfiles(profiles: ["Work": ["com.a"], "Home": ["com.b"]], active: "Home",
                                       schedules: ["Work": ProfileSchedule(start: 540, end: 1020)])
        profiles.timeChanged(minute: 500)
        XCTAssertEqual(profiles.active, "Home")
        profiles.timeChanged(minute: 540)
        XCTAssertEqual(profiles.active, "Work")
        XCTAssertEqual(profiles.scheduled, "Work")
        profiles.timeChanged(minute: 600)
        XCTAssertEqual(profiles.active, "Work")
        profiles.timeChanged(minute: 1020)
        XCTAssertEqual(profiles.active, "Home")
        XCTAssertNil(profiles.scheduled)
        XCTAssertNil(profiles.beforeSchedule)
    }

    func testAChoiceMadeInsideTheWindowStays() {
        var profiles = MenuBarProfiles(profiles: ["Work": ["com.a"], "Home": ["com.b"]],
                                       schedules: ["Work": ProfileSchedule(start: 540, end: 1020)])
        profiles.timeChanged(minute: 540)
        XCTAssertEqual(profiles.active, "Work")
        profiles.active = "Home"
        // Not re-applied every minute, and not undone when the window ends.
        profiles.timeChanged(minute: 541)
        XCTAssertEqual(profiles.active, "Home")
        profiles.timeChanged(minute: 1020)
        XCTAssertEqual(profiles.active, "Home")
    }

    func testRenamingAndDeletingCarryTheSchedule() {
        var profiles = MenuBarProfiles(profiles: ["Work": ["com.a"], "Home": ["com.b"]], active: "Home",
                                       schedules: ["Work": ProfileSchedule(start: 540, end: 1020)])
        profiles.timeChanged(minute: 600)
        XCTAssertTrue(profiles.rename("Work", to: "Office"))
        XCTAssertEqual(profiles.schedules, ["Office": ProfileSchedule(start: 540, end: 1020)])
        XCTAssertEqual(profiles.scheduled, "Office")
        XCTAssertTrue(profiles.rename("Home", to: "House"))
        XCTAssertEqual(profiles.beforeSchedule, .from("House"))
        profiles.timeChanged(minute: 1020)
        XCTAssertEqual(profiles.active, "House")

        profiles.timeChanged(minute: 600)
        profiles.delete("Office")
        XCTAssertNil(profiles.active)
        XCTAssertTrue(profiles.schedules.isEmpty)
        XCTAssertNil(profiles.scheduled)
    }

    func testStoreRoundTripsSchedules() {
        let suite = "MenuBarProfilesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsMenuBarProfilesStore(defaults: defaults)
        let profiles = MenuBarProfiles(profiles: ["Work": ["com.a"]], active: "Work",
                                       schedules: ["Work": ProfileSchedule(start: 1320, end: 420)],
                                       scheduled: "Work", beforeSchedule: .from(nil))
        store.profiles = profiles
        XCTAssertEqual(UserDefaultsMenuBarProfilesStore(defaults: defaults).profiles, profiles)
    }

    func testAnOpenAppSwitchesAndQuittingItSwitchesBack() {
        var profiles = MenuBarProfiles(profiles: ["Meetings": ["us.zoom"], "Home": ["com.b"]], active: "Home",
                                       appTriggers: ["Meetings": "us.zoom.xos"])
        profiles.appsChanged(running: ["com.apple.finder"])
        XCTAssertEqual(profiles.active, "Home")
        profiles.appsChanged(running: ["com.apple.finder", "us.zoom.xos"])
        XCTAssertEqual(profiles.active, "Meetings")
        XCTAssertEqual(profiles.appSwitched, "Meetings")
        profiles.appsChanged(running: ["com.apple.finder"])
        XCTAssertEqual(profiles.active, "Home")
        XCTAssertNil(profiles.appSwitched)
    }

    func testAChoiceMadeWhileTheAppIsOpenStays() {
        var profiles = MenuBarProfiles(profiles: ["Meetings": ["us.zoom"], "Home": ["com.b"]],
                                       appTriggers: ["Meetings": "us.zoom.xos"])
        profiles.appsChanged(running: ["us.zoom.xos"])
        profiles.active = "Home"
        profiles.appsChanged(running: ["us.zoom.xos", "com.other"])
        XCTAssertEqual(profiles.active, "Home")
        profiles.appsChanged(running: [])
        XCTAssertEqual(profiles.active, "Home")
    }

    func testRenamingAndDeletingCarryTheAppTrigger() {
        var profiles = MenuBarProfiles(profiles: ["Meetings": ["us.zoom"]], appTriggers: ["Meetings": "us.zoom.xos"])
        profiles.appsChanged(running: ["us.zoom.xos"])
        XCTAssertTrue(profiles.rename("Meetings", to: "Calls"))
        XCTAssertEqual(profiles.appTriggers, ["Calls": "us.zoom.xos"])
        XCTAssertEqual(profiles.appSwitched, "Calls")
        profiles.delete("Calls")
        XCTAssertTrue(profiles.appTriggers.isEmpty)
        XCTAssertNil(profiles.appSwitched)
        XCTAssertNil(profiles.active)
    }

    func testStoreRoundTripsAppTriggers() {
        let suite = "MenuBarProfilesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsMenuBarProfilesStore(defaults: defaults)
        let profiles = MenuBarProfiles(profiles: ["Meetings": ["us.zoom"]], active: "Meetings",
                                       appTriggers: ["Meetings": "us.zoom.xos"], appSwitched: "Meetings",
                                       beforeApp: .from(nil))
        store.profiles = profiles
        XCTAssertEqual(UserDefaultsMenuBarProfilesStore(defaults: defaults).profiles, profiles)
    }

    func testAProfileDecidesWhatShowsButKeepsAlwaysHidden() {
        let layout = MenuBarLayout(sections: ["com.a": .visible, "com.b": .hidden, "com.c": .alwaysHidden, "com.new": .hidden])
        // com.c is in the profile, but moving it to Always Hidden wins.
        let applied = MenuBarProfiles.applied(["com.b", "com.c"], alsoVisible: ["com.new"], to: layout)
        XCTAssertEqual(applied.sections, ["com.a": .hidden, "com.b": .visible, "com.c": .alwaysHidden, "com.new": .visible])
    }

    func testStoreRoundTrips() {
        let suite = "MenuBarProfilesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsMenuBarProfilesStore(defaults: defaults)
        store.profiles = MenuBarProfiles(profiles: ["Quiet": ["com.a"]], active: "Quiet")
        XCTAssertEqual(UserDefaultsMenuBarProfilesStore(defaults: defaults).profiles,
                       MenuBarProfiles(profiles: ["Quiet": ["com.a"]], active: "Quiet"))
    }

    func testEngineShowsTheProfilesAppsWhileCollapsed() {
        let items = FakeItems()
        let inventory = FakeInventory()
        inventory.items = [item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        let visibility = FakeVisibility()
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            captureActivity: FakeCaptureActivity(), clock: FakeClock(),
                                            ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                            itemFrame: { _ in separator },
                                            displays: { [mainDisplay] },
                                            isLTR: { true })
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)

        engine.setProfile(["com.hidden"])
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden"])
        XCTAssertEqual(engine.hiddenItems.map(\.bundleIdentifier), ["com.visible"], "what the profile hides is offered in the separate bar")
        var saved: [String]?
        engine.readVisibleApps { saved = $0 }
        XCTAssertEqual(saved, ["com.hidden"])

        engine.setProfile(nil)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }
}

final class FreshReadKeepsChoicesTests: XCTestCase {
    private var visibility: FakeVisibility!
    private var engine: NativeVisibilityEngine!
    // The engine holds its items weakly.
    private var items: FakeItems!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        let inventory = FakeInventory()
        inventory.items = [item("com.hidden", x: 1100), item("com.other", x: 1150), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                        captureActivity: FakeCaptureActivity(), clock: FakeClock(),
                                        ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                        itemFrame: { _ in separator },
                                        displays: { [mainDisplay] },
                                        isLTR: { true })
    }

    // A collapse re-reads the bar; it used to build its list without the
    // frontmost app or the active profile, undoing both.
    func testCollapsingKeepsTheFrontmostAppAndTheProfile() {
        engine.setActiveApp("com.hidden")
        engine.collapse { _ in }
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
        visibility.succeed(visibility.requests.count - 1)

        engine.expand()
        engine.setActiveApp(nil)
        engine.setProfile(["com.other"])
        engine.collapse { _ in }
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.other"])
    }

    func testASwitchDuringACollapseIsAppliedOnceItLands() {
        engine.collapse { _ in }
        let collapse = visibility.requests.count - 1
        engine.setActiveApp("com.hidden")
        XCTAssertEqual(visibility.requests.count, collapse + 1, "nothing new while the collapse is in flight")
        visibility.succeed(collapse)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
    }
}

final class SavingProfilesTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var engine: NativeVisibilityEngine!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                        captureActivity: FakeCaptureActivity(), clock: FakeClock(),
                                        ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                        itemFrame: { _ in separator },
                                        displays: { [mainDisplay] },
                                        isLTR: { true })
    }

    // Before any read there used to be nothing to save, which made a profile
    // that hid every icon; and an expanded bar may have changed since.
    func testSavingReadsTheBarAsItIsNow() {
        var saved: [String]?
        engine.readVisibleApps { saved = $0 }
        XCTAssertEqual(saved, ["com.visible"])

        inventory.items = [item("com.hidden", x: 1350), item("com.visible", x: 1400)]
        engine.readVisibleApps { saved = $0 }
        XCTAssertEqual(saved, ["com.hidden", "com.visible"], "moved right of the arrow since the last read")
    }

    func testTheAppInFrontIsntSaved() {
        engine.setActiveApp("com.hidden")
        var saved: [String]?
        engine.readVisibleApps { saved = $0 }
        XCTAssertEqual(saved, ["com.visible"])
    }

    func testNothingVisibleSavesNothing() {
        inventory.items = [item("com.hidden", x: 1100)]
        var saved: [String]? = ["placeholder"]
        engine.readVisibleApps { saved = $0 }
        XCTAssertNil(saved)
    }
}

final class DisplayProfileTests: XCTestCase {
    private func profiles(active: String?) -> MenuBarProfiles {
        MenuBarProfiles(profiles: ["Laptop": ["com.a"], "Desk": ["com.a", "com.b"]], active: active, displayProfile: "Desk")
    }

    func testSwitchesWhileDockedAndBackAfter() {
        var p = profiles(active: "Laptop")
        p.displaysChanged(external: true)
        XCTAssertEqual(p.active, "Desk")
        p.displaysChanged(external: true)
        XCTAssertEqual(p.active, "Desk", "repeated display changes don't stack")
        p.displaysChanged(external: false)
        XCTAssertEqual(p.active, "Laptop")
        XCTAssertNil(p.beforeDisplay)
    }

    func testRestoresTheArrowToo() {
        var p = profiles(active: nil)
        p.displaysChanged(external: true)
        XCTAssertEqual(p.active, "Desk")
        p.displaysChanged(external: false)
        XCTAssertNil(p.active)
    }

    func testAManualChoiceWhileDockedSticks() {
        var p = profiles(active: "Laptop")
        p.displaysChanged(external: true)
        p.active = "Laptop"
        p.displaysChanged(external: false)
        XCTAssertEqual(p.active, "Laptop")
    }

    func testChangingTheDisplayProfileWhileSwitchedUndoesTheSwitch() {
        var p = profiles(active: "Laptop")
        p.profiles["Work"] = ["com.c"]
        p.displaysChanged(external: true)
        p.setDisplayProfile("Work")
        XCTAssertEqual(p.active, "Laptop")
        p.displaysChanged(external: true)
        XCTAssertEqual(p.active, "Work", "the new choice applies right away while docked")
        p.displaysChanged(external: false)
        XCTAssertEqual(p.active, "Laptop")

        p.displaysChanged(external: true)
        p.delete("Work")
        XCTAssertEqual(p.active, "Laptop", "deleting the display profile while switched goes back")
        XCTAssertNil(p.beforeDisplay)
    }

    func testNoDisplayProfileChangesNothing() {
        var p = MenuBarProfiles(profiles: ["Laptop": []], active: "Laptop")
        p.displaysChanged(external: true)
        XCTAssertEqual(p.active, "Laptop")
    }

    func testSwitchSurvivesARelaunch() {
        let suite = "DisplayProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsMenuBarProfilesStore(defaults: defaults)
        var p = profiles(active: nil)
        p.displaysChanged(external: true)
        store.profiles = p
        var reloaded = UserDefaultsMenuBarProfilesStore(defaults: defaults).profiles
        XCTAssertEqual(reloaded.beforeDisplay, .from(nil))
        reloaded.displaysChanged(external: false)
        XCTAssertNil(reloaded.active)
    }
}

final class EngineInteractionTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var clock: FakeClock!
    private var store: InMemoryNewMenuBarAppStore!
    private var timeouts: [() -> Void] = []

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.new", x: 1050), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        clock = FakeClock()
        store = InMemoryNewMenuBarAppStore()
        store.tracker = NewMenuBarAppTracker(known: ["com.hidden", "com.visible"])
        timeouts = []
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      captureActivity: FakeCaptureActivity(), clock: clock,
                                      newApps: store,
                                      ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                      itemFrame: { _ in separator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true },
                                      afterActivationTimeout: { [weak self] in self?.timeouts.append($0) })
    }

    func testPresentationAskedDuringACollapseSurvivesAnExpand() {
        let engine = makeEngine()
        engine.collapse { _ in }
        engine.setPresenting(true)
        engine.expand()
        XCTAssertTrue(engine.isPresenting)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway"])
    }

    func testHidingANewAppDuringACollapseLandsAfterIt() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapse = visibility.requests.count - 1
        XCTAssertEqual(visibility.requests[collapse].bundles, ["com.brunoalumn.tuckaway", "com.new", "com.visible"])
        engine.resolveNewApp("com.new", keepVisible: false)
        visibility.succeed(collapse)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }

    func testALayoutChangeMidCollapseDropsIt() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        engine.invalidateLayout()
        XCTAssertEqual(engine.state, .expanded)
        let late = visibility.succeed(0)
        XCTAssertTrue(late.isInvalidated, "the old layout's restriction isn't kept")
        XCTAssertEqual(engine.state, .expanded)
    }

    func testATimedOutRestoreFailsOpen() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(visibility.requests.count - 1)
        engine.setPresenting(true)
        visibility.succeed(visibility.requests.count - 1)

        engine.setPresenting(false)
        timeouts.last?()
        XCTAssertTrue(collapsed.isInvalidated)
        XCTAssertEqual(engine.state, .expanded, "nothing held, so not collapsed")
        XCTAssertFalse(engine.isPresenting)

        engine.collapse { _ in }
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.new", "com.visible"], "the next collapse hides again")
    }

    func testAFailedPeekFailsOpen() {
        let engine = makeEngine()
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
        engine.peekHiddenSection { _ in }
        visibility.fail(visibility.requests.count - 1)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertFalse(engine.isPeeking)
    }

    func testSavingDoesntCancelAnActivationInFlight() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        let expanding = visibility.requests.count - 1
        var saved: [String]?
        engine.readVisibleApps { saved = $0 }
        XCTAssertNotNil(saved)
        let assertion = visibility.succeed(expanding)
        XCTAssertFalse(assertion.isInvalidated, "the expanded restriction still lands")
    }
}

final class HiddenSeparatorsRereadTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var engine: NativeVisibilityEngine!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        let items = self.items!
        engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                        captureActivity: FakeCaptureActivity(), clock: FakeClock(),
                                        ownBundleIdentifier: "com.brunoalumn.tuckaway",
                                        itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                        displays: { [mainDisplay] },
                                        isLTR: { true })
        // Expanded with "hide separators": a restriction is held from the start.
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)
    }

    func testCollapseUsesWhereTheShownIconsAreNow() {
        // ⌘-dragged right of the arrow while expanded.
        inventory.items = [item("com.always", x: 900), item("com.hidden", x: 1350), item("com.visible", x: 1400)]
        engine.collapse { _ in }
        XCTAssertEqual(inventory.partialSnapshots, 1)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.hidden", "com.visible"])
    }

    func testAlwaysHiddenAppsKeepTheirSection() {
        // Hidden by the held restriction, so its frame is stale; it isn't re-read.
        inventory.items = [item("com.always", x: 1450), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        engine.collapse { _ in }
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }

    func testAnUnresolvableReadKeepsTheCachedLayout() {
        inventory.items = [item("com.hidden", x: 5000), item("com.visible", x: 1400)]
        engine.collapse { _ in }
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.brunoalumn.tuckaway", "com.visible"])
    }
}

final class ProfileShortcutToggleTests: XCTestCase {
    private var profiles = MenuBarProfiles(profiles: ["Work": ["a"], "Home": ["b"]])

    func testShortcutSwitchesToItsProfileAndBackToTheArrow() {
        profiles.toggle("Work")
        XCTAssertEqual(profiles.active, "Work")
        profiles.toggle("Work")
        XCTAssertNil(profiles.active)
    }

    func testAnotherProfilesShortcutSwitchesStraightToIt() {
        profiles.active = "Work"
        profiles.toggle("Home")
        XCTAssertEqual(profiles.active, "Home")
    }

    func testShortcutForADeletedProfileDoesNothing() {
        profiles.active = "Work"
        profiles.toggle("Gone")
        XCTAssertEqual(profiles.active, "Work")
    }
}
