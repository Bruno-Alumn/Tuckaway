//
//  LayoutSettlePlanTests.swift
//  TuckawayUnitTests
//

import XCTest

// When the native engine reads the menu bar again after a display change, a
// wake or an app launch: it waits for the bar to settle, extends the wait while
// the pointer is in the menu bar, and gives up after a bounded number of checks
// so the bar can't stay expanded forever.
final class LayoutSettlePlanTests: XCTestCase {
    func testFirstWaitIsTheInitialDelayAndLaterOnesTheRetryInterval() {
        XCTAssertEqual(LayoutSettlePlan.delay(forAttempt: 0), LayoutSettlePlan.initialDelay)
        XCTAssertEqual(LayoutSettlePlan.delay(forAttempt: 1), LayoutSettlePlan.retryInterval)
        XCTAssertEqual(LayoutSettlePlan.delay(forAttempt: 9), LayoutSettlePlan.retryInterval)
    }

    func testAReadHappensAsSoonAsThePointerIsOutOfTheWay() {
        XCTAssertEqual(LayoutSettlePlan.decision(attempt: 0, isBusy: false), .read)
        XCTAssertEqual(LayoutSettlePlan.decision(attempt: 5, isBusy: false), .read)
    }

    func testTheWaitExtendsWhileThePointerUsesTheMenuBar() {
        XCTAssertEqual(LayoutSettlePlan.decision(attempt: 0, isBusy: true), .wait)
        XCTAssertEqual(LayoutSettlePlan.decision(attempt: LayoutSettlePlan.maxChecks - 1, isBusy: true), .wait)
    }

    // Waiting longer would leave every icon showing, so the last check reads
    // anyway.
    func testGivesUpAfterTheLastCheck() {
        XCTAssertEqual(LayoutSettlePlan.decision(attempt: LayoutSettlePlan.maxChecks, isBusy: true), .giveUp)
    }
}
