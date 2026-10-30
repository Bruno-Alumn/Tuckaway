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

    static var isUsingLTRLanguage = NSApplication.shared.userInterfaceLayoutDirection == .leftToRight
}

extension ProcessInfo {
    var isMacOS27OrLater: Bool {
        isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
    }
}
