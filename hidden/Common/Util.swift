//
//  Util.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/29/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices
import Foundation


class Util {
    
    @discardableResult
    static func setUpAutoStart(isAutoStart: Bool) -> Bool {
        // SMAppService (macOS 13+) registers the main app itself as a login item;
        // no helper app, no distributed-notification kill dance.
        return AutoStart.apply(enabled: isAutoStart)
    }
    
    static func showPrefWindow() {
        let prefWindow = PreferencesWindowController.shared.window
        prefWindow?.bringToFront()
    }

    // macOS 27 hiding reads the menu-bar sections through Accessibility; without
    // the permission the arrow does nothing, so the UI checks this to explain why.
    static var isAccessibilityPermissionMissing: Bool {
        return MenuBarEngineFactory.usesNativeVisibility && !AXIsProcessTrusted()
    }

    // The prompt adds Tuckaway to the Accessibility list (so the user only has
    // to flip the switch); the pane is opened too because the prompt is shown at
    // most once per launch and is easy to dismiss.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        let settingsURL: String
        if #available(macOS 27.0, *) {
            settingsURL = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        } else {
            settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: settingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // macOS posts this when any app's Accessibility grant changes. The trust
    // value lags the notification slightly, hence the delay before re-checking.
    static func observeAccessibilityPermissionChanges() {
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .accessibilityPermissionChanged, object: nil)
            }
        }
    }

}
