//
//  MenuBarSpacers.swift
//  Tuckaway
//

import CoreGraphics

// Blank items to ⌘-drag between icons, to group them (#159).
enum MenuBarSpacers {
    static let maxCount = 5

    enum Width: Int, CaseIterable {
        case narrow = 8, medium = 16, wide = 32
    }

    static func autosaveName(_ index: Int) -> String {
        "tuckaway_spacer_\(index)"
    }

    // What each spacer's length should be. On macOS 27 Tuckaway can't hide its
    // own items (the arrow would go too), so while collapsed a spacer on the
    // hidden side of the arrow shrinks to nothing instead of leaving a gap. The
    // separator engine pushes them off screen with the other hidden icons.
    static func lengths(spacerMinX: [CGFloat], arrowMinX: CGFloat, isLTR: Bool,
                        collapsed: Bool, width: Width) -> [CGFloat] {
        spacerMinX.map { x in
            let isHiddenSide = isLTR ? x < arrowMinX : x > arrowMinX
            return collapsed && isHiddenSide ? 0 : CGFloat(width.rawValue)
        }
    }
}

// "Show how many icons are hidden": a number next to the arrow while collapsed.
enum HiddenIconCount {
    static func title(count: Int, collapsed: Bool, enabled: Bool) -> String {
        enabled && collapsed && count > 0 ? "\(count)" : ""
    }
}
