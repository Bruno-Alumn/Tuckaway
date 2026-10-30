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

    // `expanded` names the arrow that expands the bar, shown while it is
    // collapsed. VoiceOver reads the image's description as the button's label,
    // so it says what a click will do.
    private static func image(expanded: Bool) -> NSImage? {
        let description = (expanded ? "Show hidden icons" : "Hide icons").localized
        let style = Preferences.expandIconStyle
        guard let expandIcon = style.assetName else {
            return NSImage(systemSymbolName: "ellipsis", accessibilityDescription: description)
        }
        // A copy: named images are shared, and the description differs by state.
        let image = NSImage(named: NSImage.Name(Constant.isUsingLTRLanguage == expanded ? expandIcon : "ic_collapse"))?.copy() as? NSImage
        image?.accessibilityDescription = description
        return image
    }
}
