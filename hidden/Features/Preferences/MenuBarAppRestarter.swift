//
//  MenuBarAppRestarter.swift
//  Tuckaway
//

import AppKit

// An app that owns a menu bar icon, as far as restarting it goes.
struct RestartableApp: Equatable {
    let name: String
    let bundleIdentifier: String
    let bundleURL: URL
    // The processes to wait for: an app that relaunches itself, or one launchd
    // keeps alive, is back under a new ID and counts as restarted.
    let processIdentifiers: [pid_t]
}

enum MenuBarAppRestartPlan {
    // The apps worth restarting for a new icon spacing: ones whose icons
    // Accessibility could read (an unreadable entry is a placeholder for an app
    // that didn't answer, not an icon), minus Tuckaway and macOS's own extras in
    // /System, which come back with the next login.
    static func apps(owning items: [MenuBarInventoryItem], running: [RestartableApp],
                     ownBundleIdentifier: String?) -> [RestartableApp] {
        let owners = Set(items.filter { !$0.isUnreadable }.compactMap(\.bundleIdentifier))
        return running.filter { app in
            owners.contains(app.bundleIdentifier)
                && app.bundleIdentifier != ownBundleIdentifier
                && !app.bundleURL.path.hasPrefix("/System/")
        }
    }
}

// Quits each app politely, waits for it to exit, and opens it again in the
// background. An app that hasn't quit by the deadline (one asking to save, say)
// is left as it is and reported. The clock is injected, so tests drive it by
// hand instead of spinning the run loop.
final class MenuBarAppRestarter {
    static let pollInterval: TimeInterval = 0.25
    static let deadline: TimeInterval = 10

    private let terminate: (RestartableApp) -> Void
    private let isRunning: (RestartableApp) -> Bool
    private let open: (RestartableApp) -> Void
    private let after: (TimeInterval, @escaping () -> Void) -> Void

    init(terminate: @escaping (RestartableApp) -> Void = MenuBarAppRestarter.terminateRunning,
         isRunning: @escaping (RestartableApp) -> Bool = MenuBarAppRestarter.isRunning,
         open: @escaping (RestartableApp) -> Void = MenuBarAppRestarter.openInBackground,
         after: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }) {
        self.terminate = terminate
        self.isRunning = isRunning
        self.open = open
        self.after = after
    }

    func restart(_ apps: [RestartableApp], completion: @escaping (_ didNotQuit: [RestartableApp]) -> Void) {
        apps.forEach(terminate)
        poll(waiting: apps, elapsed: 0, completion: completion)
    }

    private func poll(waiting: [RestartableApp], elapsed: TimeInterval,
                      completion: @escaping ([RestartableApp]) -> Void) {
        let stillRunning = waiting.filter(isRunning)
        waiting.filter { !stillRunning.contains($0) }.forEach(open)
        guard !stillRunning.isEmpty, elapsed < Self.deadline else {
            completion(stillRunning)
            return
        }
        after(Self.pollInterval) { [self] in
            poll(waiting: stillRunning, elapsed: elapsed + Self.pollInterval, completion: completion)
        }
    }

    // One entry per bundle, holding all of its processes.
    static func runningApps() -> [RestartableApp] {
        var order: [String] = []
        var byBundle: [String: (app: NSRunningApplication, pids: [pid_t])] = [:]
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            guard let bundleIdentifier = app.bundleIdentifier, app.bundleURL != nil else { continue }
            if byBundle[bundleIdentifier] == nil { order.append(bundleIdentifier) }
            byBundle[bundleIdentifier, default: (app, [])].pids.append(app.processIdentifier)
        }
        return order.compactMap { bundleIdentifier in
            guard let entry = byBundle[bundleIdentifier], let bundleURL = entry.app.bundleURL else { return nil }
            return RestartableApp(name: entry.app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent,
                                  bundleIdentifier: bundleIdentifier, bundleURL: bundleURL,
                                  processIdentifiers: entry.pids)
        }
    }

    private static func instances(of app: RestartableApp) -> [NSRunningApplication] {
        app.processIdentifiers.compactMap(NSRunningApplication.init(processIdentifier:))
            .filter { !$0.isTerminated }
    }

    static func terminateRunning(_ app: RestartableApp) {
        instances(of: app).forEach { _ = $0.terminate() }
    }

    static func isRunning(_ app: RestartableApp) -> Bool {
        !instances(of: app).isEmpty
    }

    static func openInBackground(_ app: RestartableApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: app.bundleURL, configuration: configuration) { _, error in
            if let error { NSLog("Restart: couldn't reopen \(app.bundleIdentifier): \(error.localizedDescription)") }
        }
    }
}
