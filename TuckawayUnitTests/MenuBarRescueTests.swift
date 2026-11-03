//
//  MenuBarRescueTests.swift
//  TuckawayUnitTests
//

import XCTest

// The arrow is Tuckaway's only UI, so a bar that puts it off screen makes the app
// unreachable. The decision is a pure mapping from the frames read to what to do,
// which is what makes it testable without a live menu bar.
final class MenuBarRescueTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1100)
    private let inBar = CGRect(x: 900, y: 1076, width: 24, height: 24)
    private let offScreen = CGRect(x: 4000, y: 1076, width: 24, height: 24)

    func testAReachableArrowNeedsNothing() {
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: inBar, screenFrames: [screen], isCollapsed: true, repairsSoFar: 0), .none)
    }

    // A frame a few points over the edge is a bar mid-reflow, not a lost arrow.
    func testASlightlyOverhangingArrowIsLeftAlone() {
        let overhang = CGRect(x: 1805, y: 1076, width: 24, height: 24)
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: overhang, screenFrames: [screen], isCollapsed: true, repairsSoFar: 0), .none)
    }

    // The separator's length doesn't move the arrow while the bar is expanded, so
    // an arrow off screen then means macOS put it there, not a collapse.
    func testAnArrowOffScreenWhileExpandedIsNotARescue() {
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: offScreen, screenFrames: [screen], isCollapsed: false, repairsSoFar: 0), .none)
    }

    func testAnArrowOffScreenWhileCollapsedIsRepaired() {
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: offScreen, screenFrames: [screen], isCollapsed: true, repairsSoFar: 0), .repair)
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: offScreen, screenFrames: [screen], isCollapsed: true, repairsSoFar: 1), .repair)
    }

    // Two repairs in a row is enough: a bar that refuses them would otherwise be
    // rebuilt forever.
    func testRepairsStopAfterTheLimit() {
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: offScreen, screenFrames: [screen], isCollapsed: true, repairsSoFar: 2), .giveUp)
    }

    // No measurement (no WindowServer answer yet) must not trigger anything.
    func testNothingToJudgeNeedsNothing() {
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: nil, screenFrames: [screen], isCollapsed: true, repairsSoFar: 0), .none)
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: .zero, screenFrames: [screen], isCollapsed: true, repairsSoFar: 0), .none)
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: offScreen, screenFrames: [], isCollapsed: true, repairsSoFar: 0), .none)
    }

    // With two displays, an arrow on the second one is reachable.
    func testAnArrowOnASecondDisplayIsReachable() {
        let second = CGRect(x: 1800, y: 0, width: 1440, height: 900)
        let onSecond = CGRect(x: 2000, y: 876, width: 24, height: 24)
        XCTAssertEqual(MenuBarRescue.action(arrowFrame: onSecond, screenFrames: [screen, second], isCollapsed: true, repairsSoFar: 0), .none)
    }
}
