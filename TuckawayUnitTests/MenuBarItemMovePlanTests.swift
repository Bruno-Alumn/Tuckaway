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

    func testReleasesJustInsideTheAnchorsNearEdge() {
        let frame = CGRect(x: 100, y: 0, width: 24, height: 22)
        XCTAssertEqual(MenuBarItemMovePlan.releaseX(for: .before("b"), anchorFrame: frame, emptyListX: 0), 104)
        XCTAssertEqual(MenuBarItemMovePlan.releaseX(for: .after("b"), anchorFrame: frame, emptyListX: 0), 120)
        XCTAssertEqual(MenuBarItemMovePlan.releaseX(for: .before("b"), anchorFrame: CGRect(x: 100, y: 0, width: 8, height: 22), emptyListX: 0), 102)
        XCTAssertEqual(MenuBarItemMovePlan.releaseX(for: .emptyList, anchorFrame: nil, emptyListX: 50), 50)
        XCTAssertEqual(MenuBarItemMovePlan.releaseX(for: .before("gone"), anchorFrame: nil, emptyListX: 50), 50)
    }

    func testSettledMeansRightNextToTheAnchorOnTheRequestedSide() {
        let anchor = CGRect(x: 100, y: 0, width: 24, height: 22)
        let justLeft = CGRect(x: 64, y: 0, width: 30, height: 22)     // 6pt gap
        let justRight = CGRect(x: 134, y: 0, width: 30, height: 22)   // 10pt gap
        let farLeft = CGRect(x: 10, y: 0, width: 30, height: 22)      // others in between
        XCTAssertTrue(MenuBarItemMovePlan.isSettled(itemFrame: justLeft, anchor: .before("a"), anchorFrame: anchor))
        XCTAssertFalse(MenuBarItemMovePlan.isSettled(itemFrame: justRight, anchor: .before("a"), anchorFrame: anchor))
        XCTAssertFalse(MenuBarItemMovePlan.isSettled(itemFrame: farLeft, anchor: .before("a"), anchorFrame: anchor))
        XCTAssertTrue(MenuBarItemMovePlan.isSettled(itemFrame: justRight, anchor: .after("a"), anchorFrame: anchor))
        XCTAssertFalse(MenuBarItemMovePlan.isSettled(itemFrame: justLeft, anchor: .after("a"), anchorFrame: anchor))
        XCTAssertTrue(MenuBarItemMovePlan.isSettled(itemFrame: farLeft, anchor: .emptyList, anchorFrame: nil))
    }
}
