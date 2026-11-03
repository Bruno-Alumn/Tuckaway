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
        // direct build hides natively there instead. The App Store build cannot:
        // the sandbox blocks the Accessibility reads that locate the sections.
        if usesNativeVisibility {
            return NativeVisibilityEngine(items: items, newApps: UserDefaultsNewMenuBarAppStore())
        }
        return LegacyLengthEngine(items: items)
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

    // macOS 26 and earlier, direct build only: the native engine takes over the
    // expanded bar so sections are chosen by the arrow and restored by macOS,
    // instead of by an inflated separator that a crowded bar can overflow.
    // Experimental until it has run on those systems, so it is opt-in:
    //
    //     defaults write com.brunoalumn.tuckaway useNativeVisibilityTakeover -bool true
    //
    // The App Store build never uses it: no Accessibility, so no sections.
    static var usesNativeVisibilityTakeover: Bool {
        #if HIDDENBAR_NATIVE_VISIBILITY
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27
            && UserDefaults.standard.bool(forKey: UserDefaults.Key.useNativeVisibilityTakeover)
        #else
        return false
        #endif
    }
}
