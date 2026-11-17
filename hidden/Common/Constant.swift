//
//  Constant.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit

enum Constant {
    static let appName = "Tuckaway"

    // Right-to-left languages such as Arabic mirror the menu bar. The layout
    // direction is fixed for the life of the process.
    static let isUsingLTRLanguage = NSApplication.shared.userInterfaceLayoutDirection == .leftToRight
}

extension ProcessInfo {
    var isMacOS27OrLater: Bool {
        isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
    }
}
