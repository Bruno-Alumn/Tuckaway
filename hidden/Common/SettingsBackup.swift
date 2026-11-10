//
//  SettingsBackup.swift
//  Tuckaway
//

import Foundation

// Export Settings / Import Settings: Tuckaway's own preferences as a property
// list, for a new Mac or a clean install. Only the keys listed here travel:
// icon positions belong to macOS, and launch state, update bookkeeping and the
// list of apps already seen describe this Mac rather than the user's choices.
enum SettingsBackup {
    static let format = 1
    static let formatKey = "TuckawaySettingsFormat"

    static let keys = [
        "globalKey", "presentationModeKey", "findHiddenIconKey",
        "numberOfSecondForAutoHide", "isAutoHide", "autoCollapseOnFocusChange", "collapseOnWindowClick",
        "isShowPreferences", "areSeparatorsHidden", "alwaysHiddenSectionEnabled",
        "useFullStatusBarOnExpandEnabled", "showHiddenItemsInSeparateBar",
        "hoverToExpand", "clickEmptyMenuBarToToggle", "scrollMenuBarToToggle", "expandWhenExternalDisplayConnected",
        "notchOverflowEnabled", "useTransparentExpandIconEnabled", "expandIconStyle",
        "automaticallyChecksForUpdates", "isAutoStart", "keptVisibleMenuBarApps",
        "showActiveAppIcon", "revealIconsOnActivity", "revealUpdatedApps", "collapseWhenLocked", "showHiddenIconCount", "menuBarSpacerCount", "menuBarSpacerWidth", "menuBarProfiles", "activeMenuBarProfile",
        "displayMenuBarProfile", "profileShortcuts", "menuBarProfileSchedules", "menuBarProfileApps", "menuBarProfilePlaces", "menuBarProfilePlaceLabels",
    ]

    enum ImportError: Error, Equatable {
        case notTuckawaySettings
        case newerFormat
    }

    // Set while a display switch is in effect: the profile to go back to.
    static let beforeDisplayKey = "menuBarProfileBeforeDisplay"
    // The same, for a switch made by a profile's schedule.
    static let beforeScheduleKey = "menuBarProfileBeforeSchedule"
    static let beforeAppKey = "menuBarProfileBeforeApp"
    static let beforePlaceKey = "menuBarProfileBeforePlace"

    static func export(from defaults: UserDefaults) -> [String: Any] {
        var values: [String: Any] = [formatKey: format]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        // Mid display switch, the active profile is the display's; the user's
        // own choice is the one to carry over ("" means none).
        if let before = defaults.string(forKey: beforeDisplayKey) ?? defaults.string(forKey: beforeScheduleKey)
            ?? defaults.string(forKey: beforeAppKey) ?? defaults.string(forKey: beforePlaceKey) {
            values["activeMenuBarProfile"] = before.isEmpty ? nil : before
        }
        return values
    }

    // The values to apply from an exported file; anything unknown is dropped,
    // so a file can't set keys Tuckaway doesn't export.
    static func importable(_ plist: [String: Any]) throws -> [String: Any] {
        guard let fileFormat = plist[formatKey] as? Int else { throw ImportError.notTuckawaySettings }
        guard fileFormat <= format else { throw ImportError.newerFormat }
        return plist.filter { keys.contains($0.key) }
    }

    static func data(from values: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    static func values(from data: Data) throws -> [String: Any] {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ImportError.notTuckawaySettings
        }
        return plist
    }
}
