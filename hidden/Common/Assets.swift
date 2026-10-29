//
//  Assets.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/28.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

struct Assets {
    private static var expandIcon: String {
        Preferences.useTransparentExpandIconEnabled ? "ic_expand_hidden" : "ic_expand"
    }

    static var expandImage: NSImage? {
        NSImage(named: NSImage.Name(Constant.isUsingLTRLanguage ? expandIcon : "ic_collapse"))
    }

    static var collapseImage: NSImage? {
        NSImage(named: NSImage.Name(Constant.isUsingLTRLanguage ? "ic_collapse" : expandIcon))
    }
}
