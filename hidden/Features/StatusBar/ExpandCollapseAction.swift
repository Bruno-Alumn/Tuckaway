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

    static func accessibilityPoint(forAppKitPoint point: CGPoint, desktopTop: CGFloat) -> CGPoint {
        return CGPoint(x: point.x, y: desktopTop - point.y)
    }
}
