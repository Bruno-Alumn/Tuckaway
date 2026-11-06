//
//  ExpandCollapseAction.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// What a press on the expand/collapse button should do. Kept as a pure mapping
// so the decision is unit-testable without a live status item or a real NSEvent.
enum ExpandCollapseAction {
    case toggle
    case contextMenu
    case toggleSeparators
}

// Scrolling on empty menu bar space shows the hidden icons (scroll up) or
// hides them (scroll down). A trackpad sends dozens of small events per swipe,
// so the deltas add up until they pass a threshold, and then the rest of that
// swipe, including its momentum, is ignored: one swipe, one change.
struct MenuBarScrollGesture {
    enum Direction: Equatable {
        case show
        case hide
    }

    static let threshold: CGFloat = 12
    // A pause this long ends a swipe, for wheels and devices without phases.
    static let quietGap: TimeInterval = 0.35

    private var total: CGFloat = 0
    private var didAct = false
    private var lastEvent: TimeInterval?

    // `deltaY` is AppKit's scrollingDeltaY, positive when the content would
    // move down (scrolling up). `began` is true for a new trackpad touch.
    mutating func handle(deltaY: CGFloat, deltaX: CGFloat = 0, began: Bool = false, at time: TimeInterval) -> Direction? {
        if began || lastEvent.map({ time - $0 > Self.quietGap }) ?? true {
            total = 0
            didAct = false
        }
        lastEvent = time
        guard !didAct else { return nil }
        // Sideways swipes are for something else (Spaces, pages).
        guard abs(deltaY) >= abs(deltaX) else { return nil }
        total += deltaY
        if total >= Self.threshold {
            didAct = true
            return .show
        }
        if total <= -Self.threshold {
            didAct = true
            return .hide
        }
        return nil
    }
}

enum ExpandCollapseActionResolver {
    // On macOS 27 the mouse-up event a status bar button hands to its action
    // carries empty modifier flags even while Option is held (#434), so the live
    // keyboard state is consulted as well.
    static func isOptionPressed(eventFlags: NSEvent.ModifierFlags?, liveFlags: NSEvent.ModifierFlags) -> Bool {
        return (eventFlags?.contains(.option) ?? false) || liveFlags.contains(.option)
    }

    // A nil event type means there is no real NSEvent behind the press, which is
    // what assistive synthesis (VoiceOver AXPress) produces: treat it as a plain
    // left click so VoiceOver users can toggle the bar at all.
    static func action(eventType: NSEvent.EventType?, optionPressed: Bool, controlPressed: Bool = false) -> ExpandCollapseAction {
        guard let eventType = eventType else { return .toggle }
        if optionPressed { return .toggleSeparators }
        switch eventType {
        case .leftMouseUp: return .toggle
        case .rightMouseUp: return controlPressed ? .contextMenu : .toggle
        default: return .toggleSeparators
        }
    }

    // An automatic collapse waits while the user is still using the menu bar:
    // the pointer is in it, or a mouse button is held. ⌘-dragging icons keeps
    // going after the pointer drifts below the bar, and collapsing under that
    // drag makes macOS reflow the bar mid-gesture.
    static func shouldDeferAutoCollapse(isMouseInMenuBar: Bool, isMouseButtonDown: Bool,
                                        isPreferencesVisible: Bool, usesFullMenuBar: Bool) -> Bool {
        return isMouseInMenuBar || isMouseButtonDown || (usesFullMenuBar && isPreferencesVisible)
    }

    static func isEmptyMenuBar(role: String?) -> Bool {
        return role == "AXMenuBar"
    }

    // `primaryScreenTop` is the top of the first screen: Accessibility measures
    // from there, not from the top of the whole desktop.
    static func accessibilityPoint(forAppKitPoint point: CGPoint, primaryScreenTop: CGFloat) -> CGPoint {
        return CGPoint(x: point.x, y: primaryScreenTop - point.y)
    }
}
