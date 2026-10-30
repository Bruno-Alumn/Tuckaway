//
//  UserDefault+Extension.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

extension UserDefaults {
    enum Key {
        static let globalKey = "globalKey"
        static let numberOfSecondForAutoHide = "numberOfSecondForAutoHide"
        static let isAutoStart = "isAutoStart"
        static let isAutoHide = "isAutoHide"
        static let autoCollapseOnFocusChange = "autoCollapseOnFocusChange"
        static let isShowPreference = "isShowPreferences"
        static let areSeparatorsHidden = "areSeparatorsHidden"
        static let alwaysHiddenSectionEnabled = "alwaysHiddenSectionEnabled"
        static let useFullStatusBarOnExpandEnabled = "useFullStatusBarOnExpandEnabled"
        static let showHiddenItemsInSeparateBar = "showHiddenItemsInSeparateBar"
        static let hoverToExpand = "hoverToExpand"
        static let clickEmptyMenuBarToToggle = "clickEmptyMenuBarToToggle"
        static let expandWhenExternalDisplayConnected = "expandWhenExternalDisplayConnected"
        static let notchOverflowEnabled = "notchOverflowEnabled"
        static let useTransparentExpandIconEnabled = "useTransparentExpandIconEnabled"
        static let expandIconStyle = "expandIconStyle"
        static let didShowMacOS27HideUnavailableNotice = "didShowMacOS27HideUnavailableNotice"
        static let automaticallyChecksForUpdates = "automaticallyChecksForUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let skippedUpdateVersion = "skippedUpdateVersion"
        static let hasLaunchedBefore = "hasLaunchedBefore"
    }
}
