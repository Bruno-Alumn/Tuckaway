//
//  LayoutSettlePlan.swift
//  Tuckaway
//

import Foundation

// When the native engine should read the menu bar again after something made
// its cached layout stale (a display change, a wake, an app launch).
//
// Reading straight away is wrong: macOS lays the bar out over the next frames,
// and a read taken mid-reflow classifies icons from stale frames, which hides
// the wrong ones. Waiting a fixed amount is wrong too: the pointer may still be
// in the menu bar, where a reflow would pull an icon out from under it.
//
// So a read is due after `initialDelay`, and each check that finds the pointer
// (or a held mouse button) busy moves it `retryInterval` further out, up to
// `maxChecks` checks. After the last one the read happens regardless: leaving
// the bar expanded forever because the pointer happens to rest there is worse.
enum LayoutSettlePlan {
    static let initialDelay: TimeInterval = 2
    static let retryInterval: TimeInterval = 1
    static let maxChecks = 30

    static func delay(forAttempt attempt: Int) -> TimeInterval {
        attempt == 0 ? initialDelay : retryInterval
    }

    enum Decision: Equatable {
        // Wait, then check again.
        case wait
        // The pointer (or a button) is in the way, but waiting longer would
        // leave the bar expanded too long.
        case giveUp
        // Read the bar and hide again.
        case read
    }

    static func decision(attempt: Int, isBusy: Bool) -> Decision {
        guard isBusy else { return .read }
        return attempt >= maxChecks ? .giveUp : .wait
    }
}
