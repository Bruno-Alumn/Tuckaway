//
//  MenuBarItemMovePlan.swift
//  Tuckaway
//

import CoreGraphics

// Where a dropped item should end up in the real menu bar, described by the
// neighbour it lands next to in the list it was dropped into. Lists are in
// menu-bar order, left to right.
enum MenuBarDropAnchor: Equatable {
    case before(String)   // the item that ends up immediately to its right
    case after(String)    // the item that ends up immediately to its left
    case emptyList
}

// The pure part of moving an item from the Menu Bar Items lists, kept free of
// AppKit and Accessibility so it can be unit tested.
enum MenuBarItemMovePlan {
    // The list's order after dropping `id` above `row`. `row` is NSTableView's
    // proposed row in the list as shown, which still contains the item when it
    // is moved within one list.
    static func inserting(_ id: String, into ids: [String], aboveRow row: Int) -> [String] {
        var result = ids
        var row = row
        if let oldIndex = result.firstIndex(of: id) {
            result.remove(at: oldIndex)
            if oldIndex < row { row -= 1 }
        }
        result.insert(id, at: max(0, min(row, result.count)))
        return result
    }

    // The neighbour to aim for: the next item when there is one, so the item
    // lands right where it was dropped; otherwise the previous one.
    static func anchor(for id: String, in ordered: [String]) -> MenuBarDropAnchor {
        guard let index = ordered.firstIndex(of: id) else { return .emptyList }
        if index + 1 < ordered.count { return .before(ordered[index + 1]) }
        if index > 0 { return .after(ordered[index - 1]) }
        return .emptyList
    }

    // Where to release the ⌘-drag. macOS swaps a dragged item past a neighbour
    // once the pointer crosses into it, so aiming just inside the neighbour's
    // near edge settles the item on the requested side whichever way it moves.
    static func releaseX(for anchor: MenuBarDropAnchor, anchorFrame: CGRect?, emptyListX: CGFloat) -> CGFloat {
        guard let frame = anchorFrame else { return emptyListX }
        let inset = min(4, frame.width / 4)
        switch anchor {
        case .before: return frame.minX + inset
        case .after: return frame.maxX - inset
        case .emptyList: return emptyListX
        }
    }

    // Status items sit a few points apart (6–14pt measured on macOS 27); any
    // wider gap means something else is in between.
    static let neighbourGap: CGFloat = 24

    // Whether the item sits right next to its anchor, on the requested side.
    static func isSettled(itemFrame: CGRect, anchor: MenuBarDropAnchor, anchorFrame: CGRect?) -> Bool {
        guard let anchorFrame else { return true }
        switch anchor {
        case .before:
            let gap = anchorFrame.minX - itemFrame.maxX
            return gap > -1 && gap < neighbourGap
        case .after:
            let gap = itemFrame.minX - anchorFrame.maxX
            return gap > -1 && gap < neighbourGap
        case .emptyList:
            return true
        }
    }
}
