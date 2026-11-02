//
//  Preferences.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

enum Preferences {

    static var globalKey: GlobalKeybindPreferences? {
        get { shortcut(forKey: UserDefaults.Key.globalKey) }
        set { setShortcut(newValue, forKey: UserDefaults.Key.globalKey) }
    }

    // Turns presentation mode on and off (macOS 27).
    static var presentationModeKey: GlobalKeybindPreferences? {
        get { shortcut(forKey: UserDefaults.Key.presentationModeKey) }
        set { setShortcut(newValue, forKey: UserDefaults.Key.presentationModeKey) }
    }

    // Opens the search for a hidden icon (macOS 27).
    static var findHiddenIconKey: GlobalKeybindPreferences? {
        get { shortcut(forKey: UserDefaults.Key.findHiddenIconKey) }
        set { setShortcut(newValue, forKey: UserDefaults.Key.findHiddenIconKey) }
    }

    // A shortcut per profile name (macOS 27): switches to that profile, or back
    // to the arrow when it's already active.
    static var profileShortcuts: [String: GlobalKeybindPreferences] {
        get {
            guard let data = UserDefaults.standard.data(forKey: UserDefaults.Key.profileShortcuts),
                  let shortcuts = try? JSONDecoder().decode([String: GlobalKeybindPreferences].self, from: data)
            else { return [:] }
            return shortcuts.filter { $0.value.isValidGlobalShortcut }
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: UserDefaults.Key.profileShortcuts)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    private static func shortcut(forKey key: String) -> GlobalKeybindPreferences? {
        guard let data = UserDefaults.standard.value(forKey: key) as? Data,
              let shortcut = try? JSONDecoder().decode(GlobalKeybindPreferences.self, from: data),
              shortcut.isValidGlobalShortcut
        else { return nil }
        return shortcut
    }

    private static func setShortcut(_ shortcut: GlobalKeybindPreferences?, forKey key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: key)

        NotificationCenter.default.post(Notification(name: .prefsChanged))
    }

    static var isAutoStart: Bool {
        get {
            return UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoStart)
        }

        set {
            // Apply first, then persist the outcome: on failure the stored value
            // stays at the previous state so the prefs checkbox shows reality
            // instead of the intent.
            let applied = Util.setUpAutoStart(isAutoStart: newValue)
            UserDefaults.standard.set(applied ? newValue : isAutoStart, forKey: UserDefaults.Key.isAutoStart)

            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var numberOfSecondForAutoHide: Double {
        get {
            UserDefaults.standard.double(forKey: UserDefaults.Key.numberOfSecondForAutoHide)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.numberOfSecondForAutoHide)

            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var isAutoHide: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoHide)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isAutoHide)

            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var autoCollapseOnFocusChange: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.autoCollapseOnFocusChange)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.autoCollapseOnFocusChange)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var isShowPreference: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.isShowPreference)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isShowPreference)

            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var areSeparatorsHidden: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.areSeparatorsHidden)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.areSeparatorsHidden)
        }
    }

    static var alwaysHiddenSectionEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.alwaysHiddenSectionEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.alwaysHiddenSectionEnabled)
            NotificationCenter.default.post(Notification(name: .alwayHideToggle))
        }
    }
    static var hoverToExpand: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.hoverToExpand)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.hoverToExpand)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // macOS 27: a hidden app's icon shows while that app is frontmost.
    static var showActiveAppIcon: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.showActiveAppIcon)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.showActiveAppIcon)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // macOS 27: a hidden icon that changes (#229) shows for a few seconds.
    static var revealIconsOnActivity: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.revealIconsOnActivity)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.revealIconsOnActivity)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // macOS 27: a hidden app's icon shows for a while after the app updates (#28).
    static var revealUpdatedApps: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.revealUpdatedApps)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.revealUpdatedApps)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var spacerCount: Int {
        get {
            min(max(UserDefaults.standard.integer(forKey: UserDefaults.Key.spacerCount), 0), MenuBarSpacers.maxCount)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.spacerCount)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var spacerWidth: MenuBarSpacers.Width {
        get {
            MenuBarSpacers.Width(rawValue: UserDefaults.standard.integer(forKey: UserDefaults.Key.spacerWidth)) ?? .medium
        }

        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaults.Key.spacerWidth)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var clickEmptyMenuBarToToggle: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.clickEmptyMenuBarToToggle)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.clickEmptyMenuBarToToggle)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var expandWhenExternalDisplayConnected: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.expandWhenExternalDisplayConnected)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.expandWhenExternalDisplayConnected)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var useFullStatusBarOnExpandEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.useFullStatusBarOnExpandEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.useFullStatusBarOnExpandEnabled)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var showHiddenItemsInSeparateBar: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.showHiddenItemsInSeparateBar)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.showHiddenItemsInSeparateBar)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var notchOverflowEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.notchOverflowEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.notchOverflowEnabled)
        }
    }

    static var expandIconStyle: ExpandIconStyle {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: UserDefaults.Key.expandIconStyle),
                  let style = ExpandIconStyle(rawValue: rawValue) else {
                return useTransparentExpandIconEnabled ? .transparent : .standard
            }
            return style
        }

        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaults.Key.expandIconStyle)
            NotificationCenter.default.post(Notification(name: .transparentExpandIconToggle))
        }
    }

    static var useTransparentExpandIconEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.useTransparentExpandIconEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.useTransparentExpandIconEnabled)
            NotificationCenter.default.post(Notification(name: .transparentExpandIconToggle))
        }
    }

    static func migrateFromHiddenBar(defaults: UserDefaults = .standard,
                                     legacyDomain: String = "com.dwarvesv.minimalbar",
                                     currentDomain: String = Bundle.main.bundleIdentifier ?? "") {
        let marker = "didMigrateFromHiddenBar"
        guard !defaults.bool(forKey: marker) else { return }
        let currentValues = defaults.persistentDomain(forName: currentDomain) ?? [:]
        if let legacyValues = defaults.persistentDomain(forName: legacyDomain) {
            for (key, value) in legacyValues where currentValues[key] == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: marker)
    }

    // Latches the one-time "hiding is unavailable on macOS 27" notice (#360) so it
    // is shown at most once per user. No notification post: nothing observes it.
    static var didShowMacOS27HideUnavailableNotice: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.didShowMacOS27HideUnavailableNotice)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.didShowMacOS27HideUnavailableNotice)
        }
    }

    static var automaticallyChecksForUpdates: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.automaticallyChecksForUpdates)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.automaticallyChecksForUpdates)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // Bookkeeping for the updater; nothing observes these.
    static var lastUpdateCheck: Date? {
        get { UserDefaults.standard.object(forKey: UserDefaults.Key.lastUpdateCheck) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.lastUpdateCheck) }
    }

    static var skippedUpdateVersion: String? {
        get { UserDefaults.standard.string(forKey: UserDefaults.Key.skippedUpdateVersion) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.skippedUpdateVersion) }
    }

}
