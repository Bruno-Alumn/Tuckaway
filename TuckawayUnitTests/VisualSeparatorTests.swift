//
//  VisualSeparatorTests.swift
//  TuckawayUnitTests
//

import XCTest

// The decorative separator on macOS 27: shown only where the engine has taken the
// real separator out of the bar, and never before the arrow's place is known.
final class VisualSeparatorTests: XCTestCase {
    func testItAppearsOnTheNativeEngineWhenWanted() {
        XCTAssertEqual(VisualSeparator.appearance(usesNativeHiding: true, isEnabled: true, isArrowOnScreen: true),
                       VisualSeparator.Appearance(isShown: true, length: VisualSeparator.width))
    }

    func testNothingIsDrawnWhenSeparatorsAreHidden() {
        XCTAssertEqual(VisualSeparator.appearance(usesNativeHiding: true, isEnabled: false, isArrowOnScreen: true),
                       VisualSeparator.Appearance(isShown: false, length: 0))
    }

    // 13–26 still has the engine's real separator; a second one would double it.
    func testTheOlderEngineKeepsItsOwnSeparator() {
        XCTAssertEqual(VisualSeparator.appearance(usesNativeHiding: false, isEnabled: true, isArrowOnScreen: true),
                       VisualSeparator.Appearance(isShown: false, length: 0))
    }

    // Before the first layout there is nothing to sit next to, and an item made
    // then would land wherever macOS put it.
    func testNothingIsDrawnBeforeTheArrowIsPlaced() {
        XCTAssertEqual(VisualSeparator.appearance(usesNativeHiding: true, isEnabled: true, isArrowOnScreen: false),
                       VisualSeparator.Appearance(isShown: false, length: 0))
    }
}
