//
//  AutoStart.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import Foundation
import ServiceManagement

// The login-item surface of SMAppService behind a protocol so the apply logic is
// unit-testable without touching the real system registration.
protocol LoginItemServing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServing {}

enum LegacyLoginItemMigration {
    private static let migratedKey = "smAppServiceMigrated"

    @discardableResult
    static func migrate(defaults: UserDefaults = .standard,
                        setEnabled: (CFString, Bool) -> Bool = SMLoginItemSetEnabled) -> Bool {
        guard !defaults.bool(forKey: migratedKey) else { return true }
        let succeeded = setEnabled("com.dwarvesv.LauncherApplication" as CFString, false)
        if succeeded {
            defaults.set(true, forKey: migratedKey)
        } else {
            NSLog("Legacy login-item cleanup failed; it will be retried on the next launch")
        }
        return succeeded
    }
}

enum AutoStart {
    // Returns whether the system ended up in the desired state. A throw is one
    // failure mode; a register() that lands on .requiresApproval (or any status
    // other than the terminal one) is another, so the post-call status is what
    // decides, not the absence of an error.
    @discardableResult
    static func apply(enabled: Bool, service: LoginItemServing = SMAppService.mainApp) -> Bool {
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status != .notRegistered { try service.unregister() }
            }
        } catch {
            NSLog("AutoStart: \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        let ok = service.status == (enabled ? SMAppService.Status.enabled : .notRegistered)
        NSLog("AutoStart: status = \(service.status.rawValue)")
        return ok
    }
}
