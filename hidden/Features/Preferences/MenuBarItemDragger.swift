//
//  MenuBarItemDragger.swift
//  Tuckaway
//

import AppKit
import ApplicationServices

// Moves another app's status item by replaying a ⌘-drag in the real menu bar.
// macOS has no API for this, so the drag is synthesized. The cursor is hidden
// and decoupled from the mouse for the few milliseconds it takes, then put back
// where it was, so the user never sees it jump.
enum MenuBarItemDragger {
    private static let eventGap: useconds_t = 12_000
    private static let settleTimeout: TimeInterval = 0.6

    // Blocking: call it off the main thread. Returns whether the item ended up
    // on the requested side of its anchor.
    static func move(_ element: AXUIElement, anchor: MenuBarDropAnchor, anchorElement: AXUIElement?, emptyListX: CGFloat) -> Bool {
        for _ in 0..<2 {
            guard let itemFrame = frame(of: element) else { return false }
            let anchorFrame = anchorElement.flatMap(frame(of:))
            if anchor != .emptyList,
               MenuBarItemMovePlan.isSettled(itemFrame: itemFrame, anchor: anchor, anchorFrame: anchorFrame) {
                return true
            }
            let source = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
            let target = CGPoint(x: MenuBarItemMovePlan.releaseX(for: anchor, anchorFrame: anchorFrame, emptyListX: emptyListX),
                                 y: source.y)
            drag(from: source, to: target)
            waitUntilSettled(element, from: itemFrame)
            if anchor == .emptyList { return true }
            if let moved = frame(of: element),
               MenuBarItemMovePlan.isSettled(itemFrame: moved, anchor: anchor, anchorFrame: anchorElement.flatMap(frame(of:))) {
                return true
            }
        }
        return false
    }

    private static func drag(from source: CGPoint, to target: CGPoint) {
        let display = CGMainDisplayID()
        let savedLocation = CGEvent(source: nil)?.location
        let eventSource = CGEventSource(stateID: .hidSystemState)

        CGDisplayHideCursor(display)
        CGAssociateMouseAndMouseCursorPosition(0)
        defer {
            if let savedLocation { CGWarpMouseCursorPosition(savedLocation) }
            CGAssociateMouseAndMouseCursorPosition(1)
            CGDisplayShowCursor(display)
        }

        func post(_ type: CGEventType, at point: CGPoint) {
            guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
            usleep(eventGap)
        }

        post(.leftMouseDown, at: source)
        post(.leftMouseDragged, at: CGPoint(x: (source.x + target.x) / 2, y: source.y))
        post(.leftMouseDragged, at: target)
        post(.leftMouseUp, at: target)
    }

    // macOS animates the reflow; wait until the item has moved and stopped.
    private static func waitUntilSettled(_ element: AXUIElement, from start: CGRect) {
        let deadline = Date().addingTimeInterval(settleTimeout)
        var last = start
        var hasMoved = false
        while Date() < deadline {
            usleep(20_000)
            guard let current = frame(of: element) else { return }
            if abs(current.minX - start.minX) > 1 { hasMoved = true }
            if hasMoved && abs(current.minX - last.minX) < 0.5 { return }
            last = current
        }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
