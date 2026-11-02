//
//  ClockDateSetting.swift
//  Tuckaway
//

import AppKit

// macOS 13–26 (#207): the collapsed separator makes the menu bar look full, so
// a clock set to show the date "When Space Allows" drops it while icons are
// hidden. macOS 27 hides without a separator and keeps the date. The fix is
// the user's own Clock Options; Tuckaway only points there.
enum ClockDateSetting {
    // com.apple.menuextra.clock ShowDate: 0 (or unset) when space allows,
    // 1 always, 2 never.
    static func dropsDateWhileCollapsed(showDate: Int?, isAnalog: Bool, hidesWithSeparator: Bool) -> Bool {
        hidesWithSeparator && !isAnalog && (showDate ?? 0) == 0
    }

    // The sandboxed build can't read the clock's settings, so it can't tell.
    static func dropsDateWhileCollapsed(hidesWithSeparator: Bool) -> Bool {
        guard MenuBarItemSpacing.isSupported else { return false }
        let domain = "com.apple.menuextra.clock" as CFString
        let showDate = CFPreferencesCopyAppValue("ShowDate" as CFString, domain) as? NSNumber
        let isAnalog = CFPreferencesCopyAppValue("IsAnalog" as CFString, domain) as? Bool ?? false
        return dropsDateWhileCollapsed(showDate: showDate?.intValue, isAnalog: isAnalog,
                                       hidesWithSeparator: hidesWithSeparator)
    }

    // Clock Options is a button in the Control Center pane.
    static func openClockSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
