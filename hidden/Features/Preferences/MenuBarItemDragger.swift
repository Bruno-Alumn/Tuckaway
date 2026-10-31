//
//  MenuBarItemDragger.swift
//  Tuckaway
//

import AppKit
import ApplicationServices

// Moves another app's status item by replaying ⌘-drags in the real menu bar.
// macOS has no API for this, so the drags are synthesized. The cursor is hidden
// and decoupled from the mouse during each drag, then put back where it was,
// so the user never sees it jump.
//
// What macOS 27 does with synthesized drags, measured on a real menu bar:
// - a quick press-move-release carries an item across any number of others
//   and usually lands it next to the item it was released over, but not always;
// - within one drag only one swap happens reliably, so a slow drag that should
//   pass several items stalls after the first;
// - while dragging, Accessibility reports the dragged item under the pointer,
//   but every item it passes visibly slides over.
// So a move is one quick drag, then single-neighbour corrections, each released
// as soon as that neighbour slides, until the bar's order is right.
enum MenuBarItemDragger {
    private static let settleTimeout: TimeInterval = 0.8
    private static let commandKeyCode: CGKeyCode = 0x37
    private static let attemptsPerStep = 4

    // Blocking: call it off the main thread. Puts the item on `side` of
    // `anchorElement`, or, with no anchor element (an empty list), of
    // Tuckaway's own item at the frame `boundary` returns. Returns whether the
    // menu bar ended up in that order.
    static func move(_ element: AXUIElement, _ side: MenuBarDropSide, of anchorElement: AXUIElement?,
                     boundary: () -> CGRect?) -> Bool {
        guard var bar = stillBar(around: element),
              let anchor = anchorElement.map(BarItem.init) ?? boundary().flatMap({ ownItem(in: bar, at: $0) })
        else { return false }
        let item = BarItem(element)
        // Done only when both are on the bar and in the right order.
        func isPlaced(_ bar: [(item: BarItem, frame: CGRect)]) -> Bool {
            let order = bar.map(\.item)
            return order.contains(item) && order.contains(anchor)
                && MenuBarItemMovePlan.nextStep(in: order, item: item, side, of: anchor) == nil
        }

        // One quick drag gets most moves there.
        if !isPlaced(bar),
           let itemFrame = bar.first(where: { $0.item == item })?.frame,
           let anchorFrame = bar.first(where: { $0.item == anchor })?.frame {
            let source = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
            guard isElement(element, at: source) else { return false }
            let releaseX = MenuBarItemMovePlan.releaseX(placing: itemFrame, side, of: anchorFrame)
            drag(from: source) { post in
                post(.leftMouseDragged, CGPoint(x: (source.x + releaseX) / 2, y: source.y))
                post(.leftMouseDragged, CGPoint(x: releaseX, y: source.y))
                // Let the items it passed finish sliding before letting go.
                holdUntilStill(anchor.element)
                usleep(120_000)
                return CGPoint(x: releaseX, y: source.y)
            }
            guard let settled = stillBar(of: bar.map(\.item)) else { return false }
            bar = settled
        }

        // Then pass one neighbour at a time until the order is right.
        for _ in 0..<(bar.count + 2) {
            if isPlaced(bar) { return true }
            guard let step = MenuBarItemMovePlan.nextStep(in: bar.map(\.item), item: item, side, of: anchor) else { return false }
            // About one synthesized drag in four doesn't register; a miss
            // changes nothing, so try again.
            var passed = false
            for _ in 0..<attemptsPerStep where !passed {
                guard let itemFrame = bar.first(where: { $0.item == item })?.frame else { return false }
                passed = passOne(element, from: itemFrame, neighbour: step.pass.element, direction: step.direction)
                guard let settled = stillBar(of: bar.map(\.item)) else { return false }
                bar = settled
            }
            guard passed else { return false }
        }
        return isPlaced(bar)
    }

    // Drags the item until `neighbour` slides over, then releases.
    private static func passOne(_ element: AXUIElement, from itemFrame: CGRect, neighbour: AXUIElement,
                                direction: MenuBarItemMovePlan.Direction) -> Bool {
        let source = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
        guard isElement(element, at: source), let neighbourStart = frame(of: neighbour)?.minX else { return false }
        let step: CGFloat = direction == .right ? 6 : -6
        // A pass registers after about 15 steps (90pt) whatever the widths;
        // a drag that hasn't passed the neighbour by 240pt never will.
        let maxSteps = 40
        var passed = false
        drag(from: source) { post in
            var point = source
            for _ in 0..<maxSteps {
                point.x += step
                post(.leftMouseDragged, point)
                // The neighbour slides the opposite way once it has been passed.
                // Releasing before it finishes sliding can undo the swap.
                if let x = frame(of: neighbour)?.minX, (x - neighbourStart) * step < -3 {
                    passed = true
                    holdUntilStill(neighbour)
                    break
                }
            }
            return point
        }
        return passed
    }

    // Holds ⌘, presses the mouse at `source`, lets `moves` post the drag events
    // and return where to release, then releases the mouse and ⌘. The cursor is
    // hidden and the mouse decoupled meanwhile, and the cursor goes back where
    // it was. ⌘ is pressed and released as real key events: flags on the mouse
    // events alone leave macOS believing ⌘ is still held afterwards, which
    // breaks the next drag and the user's typing.
    private static func drag(from source: CGPoint, _ moves: ((CGEventType, CGPoint) -> Void) -> CGPoint) {
        let display = MenuBarDisplayInventory.current().first(where: { $0.accessibilityFrame.contains(source) })
            .flatMap { UInt32($0.identifier) } ?? CGMainDisplayID()
        let savedLocation = CGEvent(source: nil)?.location
        let eventSource = CGEventSource(stateID: .hidSystemState)

        func command(_ down: Bool) {
            let key = CGEvent(keyboardEventSource: eventSource, virtualKey: commandKeyCode, keyDown: down)
            key?.flags = down ? .maskCommand : []
            key?.post(tap: .cghidEventTap)
        }

        CGDisplayHideCursor(display)
        CGAssociateMouseAndMouseCursorPosition(0)
        command(true)
        defer {
            command(false)
            if let savedLocation { CGWarpMouseCursorPosition(savedLocation) }
            CGAssociateMouseAndMouseCursorPosition(1)
            CGDisplayShowCursor(display)
        }

        func post(_ type: CGEventType, _ point: CGPoint) {
            guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
            usleep(10_000)
        }

        post(.leftMouseDown, source)
        post(.leftMouseUp, moves(post))
    }

    // Waits, with the button still down, until `element` stops sliding.
    private static func holdUntilStill(_ element: AXUIElement) {
        var last = frame(of: element)?.minX
        var stillReadings = 0
        let deadline = Date().addingTimeInterval(0.4)
        while stillReadings < 2 && Date() < deadline {
            usleep(16_000)
            let current = frame(of: element)?.minX
            stillReadings = (current != nil && last != nil && abs(current! - last!) < 0.5) ? stillReadings + 1 : 0
            last = current
        }
    }

    // MARK: - Reading the bar

    // An Accessibility element compared by identity, so the plan can use it.
    struct BarItem: Equatable {
        let element: AXUIElement
        init(_ element: AXUIElement) { self.element = element }
        static func == (lhs: BarItem, rhs: BarItem) -> Bool { CFEqual(lhs.element, rhs.element) }
    }

    // Every status item on the item's menu-bar row, left to right, once nothing
    // has moved for three readings in a row. Frames read mid-animation point at
    // the wrong icon.
    private static func stillBar(around element: AXUIElement) -> [(item: BarItem, frame: CGRect)]? {
        guard let row = frame(of: element) else { return nil }
        return stillBar(of: barItems(onRowOf: row).map(\.item))
    }

    // The same, re-reading only the given items: scanning every app is slow,
    // and a move doesn't add or remove items.
    private static func stillBar(of items: [BarItem]) -> [(item: BarItem, frame: CGRect)]? {
        func read() -> [(item: BarItem, frame: CGRect)] {
            items.compactMap { item in frame(of: item.element).map { (item, $0) } }
                .sorted { $0.frame.minX < $1.frame.minX }
        }
        let deadline = Date().addingTimeInterval(settleTimeout)
        var last = read()
        var stillReadings = 0
        while Date() < deadline && stillReadings < 3 {
            usleep(20_000)
            let current = read()
            let same = current.count == last.count
                && zip(current, last).allSatisfy { $0.item == $1.item && abs($0.frame.minX - $1.frame.minX) < 0.5 }
            stillReadings = same ? stillReadings + 1 : 0
            last = current
        }
        return stillReadings == 3 && !last.isEmpty ? last : nil
    }

    private static func barItems(onRowOf row: CGRect) -> [(item: BarItem, frame: CGRect)] {
        var result: [(item: BarItem, frame: CGRect)] = []
        for app in NSWorkspace.shared.runningApplications where app.bundleURL?.pathExtension == "app" {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            var extras: AnyObject?
            var children: AnyObject?
            guard AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extras) == .success,
                  let extras, CFGetTypeID(extras) == AXUIElementGetTypeID(),
                  AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                  let elements = children as? [AXUIElement]
            else { continue }
            for element in elements {
                if let frame = frame(of: element), frame.width > 2, abs(frame.midY - row.midY) < 4 {
                    result.append((BarItem(element), frame))
                }
            }
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    // Tuckaway's own item at `frame` (the separator or the arrow), found by
    // position since the window frame is all the controller has.
    private static func ownItem(in bar: [(item: BarItem, frame: CGRect)], at frame: CGRect) -> BarItem? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return bar.first { entry in
            var pid: pid_t = 0
            AXUIElementGetPid(entry.item.element, &pid)
            return pid == ownPID && abs(entry.frame.minX - frame.minX) < 3
        }?.item
    }

    // Whether Accessibility hit-tests `point` to `element` (or something inside it).
    private static func isElement(_ element: AXUIElement, at point: CGPoint) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              var current = hit
        else { return false }
        for _ in 0..<4 {
            if CFEqual(current, element) { return true }
            var parent: AnyObject?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { return false }
            current = parent as! AXUIElement
        }
        return false
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
