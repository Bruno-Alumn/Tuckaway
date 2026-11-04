//
//  MenuBarPositionPlanTests.swift
//  TuckawayUnitTests
//

import XCTest

final class MenuBarPositionPlanTests: XCTestCase {
    // Measured on macOS 27.2: larger weights sit further left.
    private let table: [String: Double] = [
        "module:Clock": 0,
        "module:BentoBox-0": 110,
        "status:com.apple.TextInputMenuAgent::Item-0": 168,
        "status:Tuckaway::hiddenbar_expandcollapse": 212,
        "status:Thockbox::Item-0": 232,
        "status:Dropbox::Item-0": 300,
        "status:Dropbox::Item-1": 290
    ]

    private func order(_ table: [String: Double]) -> [String] {
        table.sorted { $0.value > $1.value }.map(\.key)
    }

    private func applying(_ weights: [String: Double]?) -> [String] {
        order(table.merging(weights ?? [:]) { _, new in new })
    }

    func testKeysMatchBundleIdentifierOrExecutableName() {
        XCTAssertEqual(MenuBarPositionPlan.keys(in: table, forAppsNamed: ["com.getdropbox.dropbox", "Dropbox"]),
                       ["status:Dropbox::Item-0", "status:Dropbox::Item-1"])
        XCTAssertEqual(MenuBarPositionPlan.keys(in: table, forAppsNamed: ["com.apple.TextInputMenuAgent"]),
                       ["status:com.apple.TextInputMenuAgent::Item-0"])
        // A prefix of another app's name isn't a match.
        XCTAssertEqual(MenuBarPositionPlan.keys(in: table, forAppsNamed: ["Drop"]), [])
    }

    func testMovingRightOfTheArrowLandsBetweenItsNeighbours() {
        let weights = MenuBarPositionPlan.weights(moving: ["status:Thockbox::Item-0"], .after,
                                                  of: ["status:Tuckaway::hiddenbar_expandcollapse"], in: table)
        XCTAssertEqual(applying(weights), [
            "status:Dropbox::Item-0", "status:Dropbox::Item-1", "status:Tuckaway::hiddenbar_expandcollapse",
            "status:Thockbox::Item-0", "status:com.apple.TextInputMenuAgent::Item-0", "module:BentoBox-0", "module:Clock"
        ])
    }

    func testAnAppsIconsMoveTogetherInTheirOrder() {
        let weights = MenuBarPositionPlan.weights(moving: ["status:Dropbox::Item-1", "status:Dropbox::Item-0"], .before,
                                                  of: ["status:com.apple.TextInputMenuAgent::Item-0"], in: table)
        XCTAssertEqual(applying(weights), [
            "status:Thockbox::Item-0", "status:Tuckaway::hiddenbar_expandcollapse",
            "status:Dropbox::Item-0", "status:Dropbox::Item-1",
            "status:com.apple.TextInputMenuAgent::Item-0", "module:BentoBox-0", "module:Clock"
        ])
    }

    func testMovingPastTheLeftmostItem() {
        let weights = MenuBarPositionPlan.weights(moving: ["status:Thockbox::Item-0"], .before,
                                                  of: ["status:Dropbox::Item-0", "status:Dropbox::Item-1"], in: table)
        XCTAssertEqual(applying(weights).first, "status:Thockbox::Item-0")
    }

    func testNoRoomRenumbersEverythingInOrder() {
        let crowded: [String: Double] = ["a": 10, "b": 10.2, "c": 10.4, "m": 50]
        let weights = MenuBarPositionPlan.weights(moving: ["m"], .after, of: ["b"], in: crowded)
        XCTAssertEqual(order(crowded.merging(weights ?? [:]) { _, new in new }), ["c", "b", "m", "a"])
    }

    func testAnAnchorWithoutAWeightGivesNothing() {
        XCTAssertNil(MenuBarPositionPlan.weights(moving: ["status:Thockbox::Item-0"], .after, of: ["status:Gone::Item-0"], in: table))
    }
}
