//
//  MenuBarItemMovePlanTests.swift
//  TuckawayUnitTests
//

import CoreGraphics
import XCTest

final class MenuBarItemMovePlanTests: XCTestCase {
    func testInsertsIntoAnotherListAtTheDropRow() {
        XCTAssertEqual(MenuBarItemMovePlan.inserting("x", into: ["a", "b", "c"], aboveRow: 0), ["x", "a", "b", "c"])
        XCTAssertEqual(MenuBarItemMovePlan.inserting("x", into: ["a", "b", "c"], aboveRow: 2), ["a", "b", "x", "c"])
        XCTAssertEqual(MenuBarItemMovePlan.inserting("x", into: ["a", "b", "c"], aboveRow: 3), ["a", "b", "c", "x"])
        XCTAssertEqual(MenuBarItemMovePlan.inserting("x", into: [], aboveRow: 0), ["x"])
    }

    func testReordersWithinOneList() {
        // Moving down: NSTableView counts the row with the item still in place.
        XCTAssertEqual(MenuBarItemMovePlan.inserting("a", into: ["a", "b", "c", "d"], aboveRow: 3), ["b", "c", "a", "d"])
        XCTAssertEqual(MenuBarItemMovePlan.inserting("a", into: ["a", "b", "c", "d"], aboveRow: 4), ["b", "c", "d", "a"])
        // Moving up.
        XCTAssertEqual(MenuBarItemMovePlan.inserting("d", into: ["a", "b", "c", "d"], aboveRow: 1), ["a", "d", "b", "c"])
        // Dropping where it already is.
        XCTAssertEqual(MenuBarItemMovePlan.inserting("b", into: ["a", "b", "c"], aboveRow: 1), ["a", "b", "c"])
        XCTAssertEqual(MenuBarItemMovePlan.inserting("b", into: ["a", "b", "c"], aboveRow: 2), ["a", "b", "c"])
    }

    func testSortsItemsIntoSectionsByBoundary() {
        XCTAssertEqual(MenuBarSection.of(centerX: 100, hiddenBoundaryX: 500, alwaysHiddenBoundaryX: 300), .alwaysHidden)
        XCTAssertEqual(MenuBarSection.of(centerX: 400, hiddenBoundaryX: 500, alwaysHiddenBoundaryX: 300), .hidden)
        XCTAssertEqual(MenuBarSection.of(centerX: 600, hiddenBoundaryX: 500, alwaysHiddenBoundaryX: 300), .visible)
        // Without the always-hidden section everything left of the boundary is hidden.
        XCTAssertEqual(MenuBarSection.of(centerX: 100, hiddenBoundaryX: 500, alwaysHiddenBoundaryX: nil), .hidden)
    }

    func testEmptyListsLandBesideTheirBoundary() {
        XCTAssertEqual(MenuBarSection.alwaysHidden.emptyListSide, .before)
        XCTAssertEqual(MenuBarSection.hidden.emptyListSide, .before)
        XCTAssertEqual(MenuBarSection.visible.emptyListSide, .after)
    }

    func testClampsOutOfRangeRows() {
        XCTAssertEqual(MenuBarItemMovePlan.inserting("x", into: ["a"], aboveRow: 9), ["a", "x"])
        XCTAssertEqual(MenuBarItemMovePlan.inserting("x", into: ["a"], aboveRow: -3), ["x", "a"])
    }

    func testAnchorsToTheNextItemThenThePreviousOne() {
        XCTAssertEqual(MenuBarItemMovePlan.anchor(for: "x", in: ["a", "x", "b"]), .before("b"))
        XCTAssertEqual(MenuBarItemMovePlan.anchor(for: "x", in: ["x", "a"]), .before("a"))
        XCTAssertEqual(MenuBarItemMovePlan.anchor(for: "x", in: ["a", "b", "x"]), .after("b"))
        XCTAssertEqual(MenuBarItemMovePlan.anchor(for: "x", in: ["x"]), .emptyList)
    }

    func testFirstReleaseIsJustInsideTheAnchorsNearEdge() {
        let item = CGRect(x: 0, y: 0, width: 30, height: 22)
        let anchor = CGRect(x: 100, y: 0, width: 24, height: 22)
        XCTAssertEqual(MenuBarItemMovePlan.releaseX(placing: item, .before, of: anchor), 104)
        XCTAssertEqual(MenuBarItemMovePlan.releaseX(placing: item, .after, of: anchor), 120)
        XCTAssertEqual(MenuBarItemMovePlan.releaseX(placing: item, .before, of: CGRect(x: 100, y: 0, width: 8, height: 22)), 102)
    }

    func testNextStepIsNilOnceTheItemIsInPlace() {
        XCTAssertNil(MenuBarItemMovePlan.nextStep(in: ["a", "x", "b"], item: "x", .before, of: "b"))
        XCTAssertNil(MenuBarItemMovePlan.nextStep(in: ["a", "x", "b"], item: "x", .after, of: "a"))
        XCTAssertNil(MenuBarItemMovePlan.nextStep(in: ["a", "b"], item: "x", .before, of: "b"))
    }

    func testNextStepIsNilWhenItemIsItsOwnAnchor() {
        XCTAssertNil(MenuBarItemMovePlan.nextStep(in: ["x", "a"], item: "x", .before, of: "x"))
        XCTAssertNil(MenuBarItemMovePlan.nextStep(in: ["a", "x"], item: "x", .after, of: "x"))
    }

    func testNextStepPassesOneNeighbourTowardsTheGoal() {
        // Before c from the far left: pass a, then b.
        let first = MenuBarItemMovePlan.nextStep(in: ["x", "a", "b", "c", "d"], item: "x", .before, of: "c")
        XCTAssertEqual(first?.pass, "a")
        XCTAssertEqual(first?.direction, .right)
        XCTAssertEqual(MenuBarItemMovePlan.nextStep(in: ["a", "x", "b", "c", "d"], item: "x", .before, of: "c")?.pass, "b")
        // After c from the left: passes c itself last.
        XCTAssertEqual(MenuBarItemMovePlan.nextStep(in: ["a", "b", "x", "c", "d"], item: "x", .after, of: "c")?.pass, "c")
        // Before b from the far right: pass d, c, then b.
        let left = MenuBarItemMovePlan.nextStep(in: ["a", "b", "c", "d", "x"], item: "x", .before, of: "b")
        XCTAssertEqual(left?.pass, "d")
        XCTAssertEqual(left?.direction, .left)
        XCTAssertEqual(MenuBarItemMovePlan.nextStep(in: ["a", "b", "x", "c", "d"], item: "x", .before, of: "b")?.pass, "b")
        // After b from the right stops short of b.
        XCTAssertEqual(MenuBarItemMovePlan.nextStep(in: ["a", "b", "c", "x"], item: "x", .after, of: "b")?.pass, "c")
        XCTAssertNil(MenuBarItemMovePlan.nextStep(in: ["a", "b", "x", "c"], item: "x", .after, of: "b"))
    }

    func testNextStepAlwaysReachesTheGoal() {
        let others = ["a", "b", "c", "d"]
        for start in 0...others.count {
            for anchor in others {
                for side in [MenuBarDropSide.before, .after] {
                    var bar = others
                    bar.insert("x", at: start)
                    var steps = 0
                    while steps < 10, let step = MenuBarItemMovePlan.nextStep(in: bar, item: "x", side, of: anchor) {
                        bar.swapAt(bar.firstIndex(of: "x")!, bar.firstIndex(of: step.pass)!)
                        steps += 1
                    }
                    let item = bar.firstIndex(of: "x")!, target = bar.firstIndex(of: anchor)!
                    XCTAssertEqual(item, side == .before ? target - 1 : target + 1, "start \(start), \(side) \(anchor)")
                    XCTAssertLessThanOrEqual(steps, others.count)
                }
            }
        }
    }

    func testMovesIntoVisibleMarkTheAppOnMacOS27() {
        XCTAssertEqual(MenuBarItemMovePlan.action(from: .hidden, to: .visible, isKept: false, marksVisibleApps: true), .keepVisible)
        XCTAssertEqual(MenuBarItemMovePlan.action(from: .alwaysHidden, to: .visible, isKept: false, marksVisibleApps: true), .keepVisible)
        XCTAssertEqual(MenuBarItemMovePlan.action(from: .visible, to: .visible, isKept: false, marksVisibleApps: true), .drag)
        XCTAssertEqual(MenuBarItemMovePlan.action(from: .visible, to: .visible, isKept: true, marksVisibleApps: true), .none,
                       "a kept app's icon sits left of the arrow")
        XCTAssertEqual(MenuBarItemMovePlan.action(from: .visible, to: .hidden, isKept: true, marksVisibleApps: true), .stopKeepingAndDrag)
        XCTAssertEqual(MenuBarItemMovePlan.action(from: .hidden, to: .alwaysHidden, isKept: false, marksVisibleApps: true), .drag)
    }

    func testEverythingIsDraggedBeforeMacOS27() {
        for from in MenuBarSection.leftToRight {
            for to in MenuBarSection.leftToRight {
                XCTAssertEqual(MenuBarItemMovePlan.action(from: from, to: to, isKept: false, marksVisibleApps: false), .drag)
            }
        }
    }

    func testAnchorSkipsKeptAppsWhoseIconsSitLeftOfTheArrow() {
        // Visible lists a kept app first, though its icon is on the hidden side.
        XCTAssertEqual(MenuBarItemMovePlan.anchor(for: "clock", in: ["clock", "kept", "wifi"], excluding: ["kept"]), .before("wifi"))
        XCTAssertEqual(MenuBarItemMovePlan.anchor(for: "clock", in: ["kept", "clock"], excluding: ["kept"]), .emptyList)
        XCTAssertEqual(MenuBarItemMovePlan.anchor(for: "clock", in: ["wifi", "clock"], excluding: []), .after("wifi"))
    }
}

final class MenuBarAppRestartTests: XCTestCase {
    private func app(_ id: String, path: String? = nil) -> RestartableApp {
        RestartableApp(name: id, bundleIdentifier: id,
                       bundleURL: URL(fileURLWithPath: path ?? "/Applications/\(id).app"), processIdentifiers: [1])
    }

    private func item(_ id: String, unreadable: Bool = false) -> MenuBarInventoryItem {
        MenuBarInventoryItem(bundleIdentifier: id, frame: .zero, isUnreadable: unreadable)
    }

    func testPlanKeepsOnlyReadableIconOwnersOtherThanTuckawayAndSystemExtras() {
        let running = [app("a"), app("b"), app("c"), app("tuckaway"),
                       app("cc", path: "/System/Library/CoreServices/ControlCenter.app")]
        let items = [item("a"), item("a"), item("b", unreadable: true), item("tuckaway"), item("cc")]

        let plan = MenuBarAppRestartPlan.apps(owning: items, running: running, ownBundleIdentifier: "tuckaway")

        XCTAssertEqual(plan.map(\.bundleIdentifier), ["a"])
    }

    // A fake clock: `after` queues work, and the test fires it by hand.
    private final class Harness {
        var running: Set<String>
        var terminated: [String] = []
        var opened: [String] = []
        var pending: [() -> Void] = []
        init(running: Set<String>) { self.running = running }

        lazy var restarter = MenuBarAppRestarter(
            terminate: { [unowned self] in terminated.append($0.bundleIdentifier) },
            isRunning: { [unowned self] in running.contains($0.bundleIdentifier) },
            open: { [unowned self] in opened.append($0.bundleIdentifier) },
            after: { [unowned self] _, work in pending.append(work) })

        func tick() {
            let work = pending
            pending = []
            work.forEach { $0() }
        }
    }

    func testEachAppReopensOnceItHasQuit() {
        let harness = Harness(running: ["a", "b"])
        var result: [RestartableApp]?
        harness.restarter.restart([app("a"), app("b")]) { result = $0 }

        XCTAssertEqual(harness.terminated, ["a", "b"])
        XCTAssertEqual(harness.opened, [])
        harness.running.remove("a")
        harness.tick()
        XCTAssertEqual(harness.opened, ["a"])
        XCTAssertNil(result)
        harness.running.remove("b")
        harness.tick()
        XCTAssertEqual(harness.opened, ["a", "b"])
        XCTAssertEqual(result, [])
    }

    func testAnAppStillRunningAtTheDeadlineIsReportedAndNotReopened() {
        let harness = Harness(running: ["a"])
        var result: [RestartableApp]?
        harness.restarter.restart([app("a")]) { result = $0 }

        let ticks = Int(MenuBarAppRestarter.deadline / MenuBarAppRestarter.pollInterval)
        for _ in 0..<ticks { harness.tick() }

        XCTAssertEqual(result?.map(\.bundleIdentifier), ["a"])
        XCTAssertEqual(harness.opened, [])
        XCTAssertTrue(harness.pending.isEmpty)
    }
}

final class ActivityRevealTests: XCTestCase {
    private let quiet = ActivitySignature(width: 24, text: "")
    private let busy = ActivitySignature(width: 40, text: "3 new")

    func testFirstReadOnlySetsTheBaseline() {
        var tracker = ActivityTracker()
        XCTAssertEqual(tracker.changes(in: ["com.a": [quiet]]), [])
        XCTAssertEqual(tracker.changes(in: ["com.a": [busy], "com.b": [quiet]]), ["com.a"])
        XCTAssertEqual(tracker.changes(in: ["com.a": [busy], "com.b": [quiet]]), [])
    }

    func testAnAppThatLeftTheWatchListStartsOver() {
        var tracker = ActivityTracker()
        _ = tracker.changes(in: ["com.a": [quiet]])
        _ = tracker.changes(in: [:])
        XCTAssertEqual(tracker.changes(in: ["com.a": [busy]]), [])
    }

    func testAChangedIconShowsForAWhileThenHides() {
        var reads: [[String: [ActivitySignature]]] = [["com.a": [quiet]], ["com.a": [busy]], [:], [:]]
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        var watched: [Set<String>] = []
        let monitor = ActivityRevealMonitor(read: { bundles, completion in
            watched.append(bundles)
            completion(reads.removeFirst())
        }, now: { clock })
        var revealed: [Set<String>] = []
        let record: (Set<String>) -> Void = { revealed.append($0) }

        monitor.tick(watching: ["com.a", "com.apple.MenuBarAgent"], reveal: record)
        XCTAssertEqual(watched, [["com.a"]])
        XCTAssertEqual(revealed, [])
        monitor.tick(watching: ["com.a"], reveal: record)
        XCTAssertEqual(revealed, [["com.a"]])
        clock += ActivityRevealMonitor.revealDuration - 1
        monitor.tick(watching: [], reveal: record)
        XCTAssertEqual(revealed, [["com.a"]])
        clock += 1
        monitor.tick(watching: [], reveal: record)
        XCTAssertEqual(revealed, [["com.a"], []])
    }

    func testExpandingEndsRevealsAndForgetsTheBaseline() {
        var reads: [[String: [ActivitySignature]]] = [["com.a": [quiet]], ["com.a": [busy]], ["com.a": [quiet]]]
        let monitor = ActivityRevealMonitor(read: { _, completion in completion(reads.removeFirst()) }, now: Date.init)
        var revealed: [Set<String>] = []
        monitor.tick(watching: ["com.a"]) { revealed.append($0) }
        monitor.tick(watching: ["com.a"]) { revealed.append($0) }
        monitor.tick(watching: nil) { revealed.append($0) }
        XCTAssertEqual(revealed, [["com.a"], []])
        // After collapsing again, the first read is a baseline, not a change.
        monitor.tick(watching: ["com.a"]) { revealed.append($0) }
        XCTAssertEqual(revealed, [["com.a"], []])
    }

    func testAReadStillRunningIsNotStartedAgain() {
        var pending: (([String: [ActivitySignature]]) -> Void)?
        var reads = 0
        let monitor = ActivityRevealMonitor(read: { _, completion in
            reads += 1
            pending = completion
        }, now: Date.init)
        monitor.tick(watching: ["com.a"]) { _ in }
        monitor.tick(watching: ["com.a"]) { _ in }
        XCTAssertEqual(reads, 1)
        pending?([:])
        monitor.tick(watching: ["com.a"]) { _ in }
        XCTAssertEqual(reads, 2)
    }
}
