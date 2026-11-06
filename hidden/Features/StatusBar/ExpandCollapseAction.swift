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

    // "Collapse when you click into a window": after a click outside the menu
    // bar, collapse if the app that received it (Accessibility's hit test) is
    // the app in front, a regular app other than Tuckaway. That covers going
    // back to the app you were already in, which "another app becomes active"
    // misses. A menu-bar app's popover or menu belongs to an accessory app, so
    // clicking inside one leaves its icon showing. The window list can't be
    // used: on macOS 27 the Dock keeps a click-through window over the screen.
    static func shouldCollapseAfterWindowClick(clickedApp: pid_t?, frontmostApp: pid_t?,
                                               frontmostIsRegular: Bool, ownPid: pid_t) -> Bool {
        guard let clickedApp, let frontmostApp, frontmostIsRegular,
              clickedApp == frontmostApp, clickedApp != ownPid else { return false }
        return true
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

// Watches left clicks anywhere, including in Tuckaway's own windows. On macOS 27
// an NSEvent global monitor can miss clicks entirely (seen in a macOS 27 VM,
// where it reported none while an event tap saw every one), so a listen-only
// event tap is used when Accessibility allows it, and NSEvent monitors
// otherwise. The handler runs on the main thread.
final class ClickObserver {
    private let handler: () -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitors: [Any] = []

    init(_ type: NSEvent.EventType, handler: @escaping () -> Void) {
        self.handler = handler
        let cgType: CGEventType = type == .leftMouseDown ? .leftMouseDown : .leftMouseUp
        let callback: CGEventTapCallBack = { _, eventType, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let observer = Unmanaged<ClickObserver>.fromOpaque(info).takeUnretainedValue()
            if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
                if let tap = observer.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                observer.handler()
            }
            return Unmanaged.passUnretained(event)
        }
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                       eventsOfInterest: CGEventMask(1) << cgType.rawValue,
                                       callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) {
            self.tap = tap
            source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            let mask = NSEvent.EventTypeMask(rawValue: 1 << type.rawValue)
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in handler() }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in handler(); return event }) {
                monitors.append(local)
            }
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    deinit {
        stop()
    }
}
