//
//  AccessibilityMenuBarInventory.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices

enum MenuBarDisplayInventory {
    // AX uses a desktop-wide top-left origin; AppKit uses bottom-left.  Use the
    // top of the entire desktop rather than the main display so stacked and
    // offset external displays map to the same coordinate system as AX.
    static func current() -> [MenuBarDisplay] {
        let screens = NSScreen.screens
        guard let desktopTop = screens.map(\.frame.maxY).max() else { return [] }
        return screens.enumerated().map { index, screen in
            let identifier = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { String($0.uint32Value) } ?? "screen-\(index)"
            let frame = screen.frame
            let accessibilityFrame = CGRect(x: frame.minX,
                                            y: desktopTop - frame.maxY,
                                            width: frame.width,
                                            height: frame.height)
            return MenuBarDisplay(identifier: identifier, appKitFrame: frame, accessibilityFrame: accessibilityFrame)
        }
    }
}

// Lists other apps' status items through public Accessibility API: every running
// app's AXExtrasMenuBar children, with the owning bundle from the process.
// Needs the Accessibility permission, and does not work inside the App Sandbox
// (the sandbox denies the mach-lookup to com.apple.axserver even when the
// permission is granted), so only the non-sandboxed direct build uses it.
final class AccessibilityMenuBarInventory: MenuBarInventoryProviding {
    private static let messagingTimeout: Float = 0.1
    private static let retryMessagingTimeout: Float = 1.0

    private var hasRequestedAuthorization = false

    var isAuthorized: Bool {
        return AXIsProcessTrusted()
    }

    // Shows the system prompt once per launch; asking on every collapse would
    // nag while the user is still in System Settings.
    func requestAuthorization() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // Accessibility round-trips to every app take about a second in total, so the
    // walk runs off the main thread.
    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void) {
        // Only app bundles own status items. Skipping the rest (dozens of WebKit
        // and XPC helpers, each of which would sit out the timeout) cuts the walk
        // from ~2.8s to ~1s.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app" }
            .map { (pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier) }
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let items = Self.statusItems(of: apps)
            NSLog("NativeVisibility: inventory of \(apps.count) apps took \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            DispatchQueue.main.async { completion(items) }
        }
    }

    // Each app is an independent IPC round-trip, so they run concurrently; serial
    // walking made collapse lag by the sum of every app's latency. Results keep
    // the running-app order.
    private static func statusItems(of apps: [(pid: pid_t, bundleIdentifier: String?)]) -> [MenuBarInventoryItem] {
        var perApp = [[MenuBarInventoryItem]](repeating: [], count: apps.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = apps[index]
            let found = statusItems(of: app, timeout: messagingTimeout)
                ?? statusItems(of: app, timeout: retryMessagingTimeout)
                ?? [MenuBarInventoryItem(bundleIdentifier: app.bundleIdentifier, frame: .zero, isUnreadable: true)]
            lock.lock()
            perApp[index] = found
            lock.unlock()
        }
        return perApp.flatMap { $0 }
    }

    private static func statusItems(of app: (pid: pid_t, bundleIdentifier: String?),
                                    timeout: Float) -> [MenuBarInventoryItem]? {
        let element = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        var barValue: CFTypeRef?
        let barError = AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue)
        if barError == .noValue { return [] }
        guard barError == .success, let bar = barValue,
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        var childrenValue: CFTypeRef?
        let childrenError = AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue)
        if childrenError == .noValue { return [] }
        guard childrenError == .success, let children = childrenValue as? [AXUIElement] else { return nil }
        var items: [MenuBarInventoryItem] = []
        for child in children {
            guard let frame = frame(of: child) else { return nil }
            items.append(MenuBarInventoryItem(bundleIdentifier: app.bundleIdentifier, frame: frame))
        }
        return items
    }

    // Accessibility frames use a top-left origin, AppKit's bottom-left. Only the
    // horizontal position matters for sections, and x is the same in both.
    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
