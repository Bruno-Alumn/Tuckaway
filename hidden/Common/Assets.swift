//
//  Assets.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/28.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

struct Assets {
    static var expandImage: NSImage? {
        image(expanded: true)
    }

    static var collapseImage: NSImage? {
        image(expanded: false)
    }

    private static func image(expanded: Bool) -> NSImage? {
        let style = Preferences.expandIconStyle
        guard let expandIcon = style.assetName else {
            return NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Tuckaway")
        }
        return NSImage(named: NSImage.Name(Constant.isUsingLTRLanguage == expanded ? expandIcon : "ic_collapse"))
    }
}
