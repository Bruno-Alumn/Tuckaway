//
//  CoordinateSpaceTests.swift
//  TuckawayUnitTests
//

import XCTest

// The menu bar is described in two coordinate spaces that differ only in which
// edge of the primary screen y counts from. Pinning the conversion keeps capture
// rectangles, click points and icon frames agreeing with each other.
final class CoordinateSpaceTests: XCTestCase {
    // A 1800x1100 screen, level with the desk.
    private let space = MenuBarCoordinateSpace.Conversion(primaryScreenMaxY: 1100, fallbackMaxY: 0)

    // The menu bar strip at the very top of the screen: Quartz says y 0..24,
    // AppKit says y 1076..1100.
    func testTheTopStripMapsToTheTopStrip() {
        XCTAssertEqual(MenuBarCoordinateSpace.appKitRect(fromQuartz: CGRect(x: 100, y: 0, width: 30, height: 24), in: space),
                       CGRect(x: 100, y: 1076, width: 30, height: 24))
        XCTAssertEqual(MenuBarCoordinateSpace.quartzRect(fromAppKit: CGRect(x: 100, y: 1076, width: 30, height: 24), in: space),
                       CGRect(x: 100, y: 0, width: 30, height: 24),
                       "the conversion has to survive being used both ways")
    }

    func testXIsUntouched() {
        let converted = MenuBarCoordinateSpace.quartzPoint(fromAppKit: CGPoint(x: 1234, y: 1088), in: space)
        XCTAssertEqual(converted.x, 1234)
        XCTAssertEqual(converted.y, 12)
    }

    // With no screen reporting yet, the caller's value is used, so a click stays
    // where the user pointed instead of being mirrored off the bottom.
    func testWithoutAScreenTheFallbackIsUsed() {
        let fallback = MenuBarCoordinateSpace.Conversion(primaryScreenMaxY: nil, fallbackMaxY: 900)
        XCTAssertEqual(fallback.referenceMaxY, 900)
        XCTAssertEqual(MenuBarCoordinateSpace.quartzPoint(fromAppKit: CGPoint(x: 10, y: 890), in: fallback),
                       CGPoint(x: 10, y: 10))
    }

    // Round-tripping any rectangle returns it unchanged, which is the property the
    // capture code relies on when it converts frames back and forth.
    func testRoundTripsExactly() {
        let rect = CGRect(x: 512, y: 1032, width: 44, height: 24)
        let there = MenuBarCoordinateSpace.quartzRect(fromAppKit: rect, in: space)
        XCTAssertEqual(MenuBarCoordinateSpace.appKitRect(fromQuartz: there, in: space), rect)
    }

    func testHiddenSectionIsTheFarSideOfTheSeparator() {
        // Left-to-right: the arrow is right of the separator, hidden items left of it.
        let separator = CGRect(x: 500, y: 0, width: 20, height: 24)
        let arrow = CGRect(x: 530, y: 0, width: 20, height: 24)
        XCTAssertTrue(MenuBarCoordinateSpace.isInHiddenSection(CGRect(x: 470, y: 0, width: 31, height: 24),
                                                               separator: separator, expandCollapse: arrow))
        XCTAssertFalse(MenuBarCoordinateSpace.isInHiddenSection(CGRect(x: 470, y: 0, width: 32, height: 24),
                                                                separator: separator, expandCollapse: arrow))
        // Right-to-left: mirrored.
        let rtlArrow = CGRect(x: 470, y: 0, width: 20, height: 24)
        XCTAssertTrue(MenuBarCoordinateSpace.isInHiddenSection(CGRect(x: 519, y: 0, width: 20, height: 24),
                                                               separator: separator, expandCollapse: rtlArrow))
        XCTAssertFalse(MenuBarCoordinateSpace.isInHiddenSection(CGRect(x: 518, y: 0, width: 20, height: 24),
                                                                separator: separator, expandCollapse: rtlArrow))
    }
}
