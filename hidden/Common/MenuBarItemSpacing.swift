//
//  MenuBarItemSpacing.swift
//  Tuckaway
//

import Foundation

// Where the spacing lives: the current host's global domain, which AppKit reads
// in every app. Behind a protocol so tests never touch the real setting.
protocol GlobalIntegerPreferences {
    func integer(forKey key: String) -> Int?
    func set(_ value: Int?, forKey key: String)
}

struct CurrentHostGlobalPreferences: GlobalIntegerPreferences {
    func integer(forKey key: String) -> Int? {
        let value = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return (value as? NSNumber)?.intValue
    }

    func set(_ value: Int?, forKey key: String) {
        CFPreferencesSetValue(key as CFString, value.map { $0 as NSNumber }, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}

// The gap AppKit leaves around every app's status item. Each app reads it when it
// launches, so a change shows up as apps restart. Measured on macOS 27.2: an
// item is its content plus the spacing (16 pt when unset); the selection padding
// only insets the highlight.
enum MenuBarItemSpacing: String, CaseIterable {
    case standard, compact, tight
    // A value set some other way, such as with `defaults` in Terminal.
    case custom

    static let spacingKey = "NSStatusItemSpacing"
    static let selectionPaddingKey = "NSStatusItemSelectionPadding"

    // The sandboxed build can't write another domain.
    static var isSupported: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    }

    var spacing: Int? {
        switch self {
        case .standard, .custom: return nil
        case .compact: return 8
        case .tight: return 4
        }
    }

    static var choices: [MenuBarItemSpacing] { [.standard, .compact, .tight] }

    static func current(in store: GlobalIntegerPreferences = CurrentHostGlobalPreferences()) -> MenuBarItemSpacing {
        guard let spacing = store.integer(forKey: spacingKey) else { return .standard }
        return choices.first { $0.spacing == spacing } ?? .custom
    }

    // .standard removes both keys, so macOS's own default comes back.
    static func apply(_ level: MenuBarItemSpacing, to store: GlobalIntegerPreferences = CurrentHostGlobalPreferences()) {
        guard level != .custom else { return }
        store.set(level.spacing, forKey: spacingKey)
        store.set(level.spacing.map { $0 / 2 }, forKey: selectionPaddingKey)
    }
}
