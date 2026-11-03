//
//  MenuBarRescue.swift
//  Tuckaway
//

import CoreGraphics

// What to do when Tuckaway's own items are not where the user can reach them.
//
// The arrow is the app's only UI. On macOS 13–26 it sits on the hidden side of a
// separator that can be as wide as twice the screen, and a bar too full to give
// the separator its length can push the arrow off screen — the app is then
// invisible and its menu unreachable. macOS also remembers status-item positions
// per app, so the broken place survives a relaunch unless it is repaired.
//
// The decision is kept free of AppKit so it can be tested: the caller passes the
// frames it read and gets what to do.
enum MenuBarRescue {
    // How far outside the screens counts as gone. A menu-bar item may sit a few
    // points over an edge while the bar reflows; only a real disappearance
    // should repair anything.
    static let tolerance: CGFloat = 8

    enum Action: Equatable {
        // Both items are reachable (or there is nothing to judge yet).
        case none
        // Expand, repair the saved order and rebuild the items: the arrow is off
        // the screens entirely, which a too-wide separator alone can't cause.
        case repair
        // Repairs already failed; tell the user instead of looping.
        case giveUp
    }

    // The most repairs in a row before giving up: each one expands and rebuilds
    // the items, so a bar that refuses the repaired positions must not be
    // dragged through them forever.
    static let maxRepairs = 2

    // Whether the arrow is on a screen, give or take the tolerance. With nothing
    // measured yet (no frame, or WindowServer's zero origin) it counts as
    // reachable: there is nothing to repair on a guess.
    static func isReachable(arrowFrame: CGRect?, screenFrames: [CGRect]) -> Bool {
        guard let arrowFrame, arrowFrame.origin != .zero, !screenFrames.isEmpty else { return true }
        return screenFrames.contains { $0.insetBy(dx: -tolerance, dy: -tolerance).intersects(arrowFrame) }
    }

    static func action(arrowFrame: CGRect?, screenFrames: [CGRect], isCollapsed: Bool,
                       repairsSoFar: Int) -> Action {
        guard !isReachable(arrowFrame: arrowFrame, screenFrames: screenFrames), isCollapsed else { return .none }
        // Off every screen while collapsed: the separator's length (bounded to
        // the widest display) can't reach that, so the saved position is wrong.
        guard repairsSoFar < maxRepairs else { return .giveUp }
        return .repair
    }
}
