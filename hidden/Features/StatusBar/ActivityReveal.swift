//
//  ActivityReveal.swift
//  Tuckaway
//

import AppKit
import ApplicationServices

// What an icon looks like to Accessibility. Hidden icons stay in the tree on
// macOS 27 (measured on 27.2), so a change of width or text (a timer, a count,
// a status in the tooltip) shows without Screen Recording. A change to the
// picture alone doesn't.
struct ActivitySignature: Equatable {
    let width: Int
    let text: String
}

struct ActivityTracker {
    private(set) var baseline: [String: [ActivitySignature]] = [:]

    // The apps whose icons changed since the last read. An app read for the
    // first time, or again after it was revealed (it isn't watched meanwhile),
    // only sets its baseline, so showing and hiding it can't set it off.
    mutating func changes(in current: [String: [ActivitySignature]]) -> Set<String> {
        let changed = current.filter { bundle, signatures in
            baseline[bundle].map { $0 != signatures } ?? false
        }
        baseline = current
        return Set(changed.keys)
    }

    mutating func reset() {
        baseline = [:]
    }
}

// The versions of apps seen launching, to notice one that updated (#28).
struct AppVersions: Equatable {
    var known: [String: String] = [:]

    // Records the version; true when the app was seen before with another one.
    // An app seen for the first time is only recorded.
    mutating func launched(_ bundle: String, version: String) -> Bool {
        defer { known[bundle] = version }
        return known[bundle].map { $0 != version } ?? false
    }

    // "1.2 (45)", from an app's Info.plist; nil when it has neither.
    static func version(of info: [String: Any]?) -> String? {
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        guard short != nil || build != nil else { return nil }
        return "\(short ?? "") (\(build ?? ""))"
    }
}

// Reveals hidden icons that change, for a few seconds each, while collapsed.
// The clock and the reader are injected so tests drive them by hand.
final class ActivityRevealMonitor {
    static let pollInterval: TimeInterval = 2
    static let revealDuration: TimeInterval = 8
    static let updateRevealDuration: TimeInterval = 30
    // macOS's own items are hidden through MenuBarAgent's allow-list, not by app.
    static let ignoredOwners: Set<String> = ["com.apple.MenuBarAgent", MenuBarItemNaming.systemExtraOwner]

    private let read: (Set<String>, @escaping ([String: [ActivitySignature]]) -> Void) -> Void
    private let now: () -> Date
    private var tracker = ActivityTracker()
    private var revealedUntil: [String: Date] = [:]
    private var isReading = false

    init(read: @escaping (Set<String>, @escaping ([String: [ActivitySignature]]) -> Void) -> Void = ActivityRevealMonitor.readInBackground,
         now: @escaping () -> Date = Date.init) {
        self.read = read
        self.now = now
    }

    // One poll. `watching` is nil while expanded (or the option is off): every
    // reveal ends and the baseline is dropped, so expanding doesn't count as a
    // change. `reveal` gets the full set of apps to show.
    func tick(watching: Set<String>?, reveal: @escaping (Set<String>) -> Void) {
        guard let watching else {
            tracker.reset()
            if !revealedUntil.isEmpty {
                revealedUntil = [:]
                reveal([])
            }
            return
        }
        let expired = revealedUntil.filter { $0.value <= now() }
        if !expired.isEmpty {
            expired.keys.forEach { revealedUntil[$0] = nil }
            reveal(Set(revealedUntil.keys))
        }
        // Only updated apps are being shown (the activity option is off).
        guard !watching.isEmpty else { return tracker.reset() }
        guard !isReading else { return }
        isReading = true
        read(watching.subtracting(Self.ignoredOwners)) { [weak self] signatures in
            guard let self else { return }
            self.isReading = false
            let changed = self.tracker.changes(in: signatures)
            guard !changed.isEmpty else { return }
            let until = self.now().addingTimeInterval(Self.revealDuration)
            changed.forEach { self.revealedUntil[$0] = until }
            reveal(Set(self.revealedUntil.keys))
        }
    }

    // An app that just updated shows like a changed icon, for longer. Returns
    // every app to show now. The next tick ends it on time, or right away if
    // the bar is expanded.
    func revealUpdated(_ bundle: String) -> Set<String> {
        revealedUntil[bundle] = now().addingTimeInterval(Self.updateRevealDuration)
        return Set(revealedUntil.keys)
    }

    // Accessibility can block on a busy app, so the read happens off the main
    // thread with a short timeout per app.
    static func readInBackground(_ bundles: Set<String>, completion: @escaping ([String: [ActivitySignature]]) -> Void) {
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier.map(bundles.contains) ?? false
        }.map { ($0.bundleIdentifier!, $0.processIdentifier) }
        DispatchQueue.global(qos: .utility).async {
            var signatures: [String: [ActivitySignature]] = [:]
            for (bundle, pid) in apps {
                signatures[bundle, default: []] += readSignatures(pid: pid)
            }
            DispatchQueue.main.async { completion(signatures) }
        }
    }

    private static func readSignatures(pid: pid_t) -> [ActivitySignature] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar = attribute(app, "AXExtrasMenuBar") else { return [] }
        let items = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return items.map { item in
            var size = CGSize.zero
            if let value = attribute(item, kAXSizeAttribute) {
                AXValueGetValue(value as! AXValue, .cgSize, &size)
            }
            let text = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute]
                .map { attribute(item, $0).map { "\($0)" } ?? "" }
                .joined(separator: "\u{1F}")
            return ActivitySignature(width: Int(size.width.rounded()), text: text)
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
