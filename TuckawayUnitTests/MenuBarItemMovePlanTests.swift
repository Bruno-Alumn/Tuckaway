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
}
