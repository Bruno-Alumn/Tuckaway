//
//  MenuBarEngineFactory.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import Foundation

// The single place that picks a hiding mechanism for the running OS.
enum MenuBarEngineFactory {
    static func make(items: MenuBarItemProvider) -> MenuBarEngine {
        // macOS 27 ejects an inflated separator from the menu bar (#360). The
        // direct build hides natively there instead, and so does the sandboxed
        // build once the user names the apps to keep: the sandbox blocks the
        // reads that locate the sections, but not each app's own extras menu bar.
        if usesNativeVisibility || (ProcessInfo.processInfo.isMacOS27OrLater && usesChosenAppsInSandbox) {
            return NativeVisibilityEngine(items: items, newApps: UserDefaultsNewMenuBarAppStore())
        }
        return LegacyLengthEngine(items: items)
    }

    // App Store build only: hide on macOS 27 from the apps the user named, since
    // the sandbox can't read where the icons are. Off by default while it is
    // unverified; see docs/ARCHITECTURE.md.
    static var usesChosenAppsInSandbox: Bool {
        #if HIDDENBAR_NATIVE_VISIBILITY
        return false
        #else
        return UserDefaults.standard.bool(forKey: UserDefaults.Key.usesChosenVisibleApps)
        #endif
    }

    // True when hiding goes through NativeVisibilityEngine, which has no
    // separator and needs the Accessibility permission to read the sections.
    static var usesNativeVisibility: Bool {
        #if HIDDENBAR_NATIVE_VISIBILITY
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        #else
        return false
        #endif
    }
}
