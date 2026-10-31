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

enum MenuBarDropSide {
    case before, after
}

// The Menu Bar Items lists.
extension MenuBarSection {
    // Left to right, as in the menu bar.
    static let leftToRight: [MenuBarSection] = [.alwaysHidden, .hidden, .visible]

    // Which list an item centred at `x` belongs to. Items left of the
    // always-hidden separator are always hidden, the rest left of the hidden
    // section's boundary are hidden. No always-hidden separator means no such
    // section.
    static func of(centerX x: CGFloat, hiddenBoundaryX: CGFloat, alwaysHiddenBoundaryX: CGFloat?) -> MenuBarSection {
        if let alwaysHiddenBoundaryX, x < alwaysHiddenBoundaryX { return .alwaysHidden }
        return x < hiddenBoundaryX ? .hidden : .visible
    }

    // Where a drop into this list, while it is empty, lands: just left of the
    // section's own boundary item, or, for Visible, just right of the arrow.
    var emptyListSide: MenuBarDropSide {
        self == .visible ? .after : .before
    }
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

    // Where to release the first, quick ⌘-drag: just inside the anchor's near
    // edge. That usually lands the item next to the anchor in one go, however
    // far it travels; `nextStep` fixes the rest.
    static func releaseX(placing itemFrame: CGRect, _ side: MenuBarDropSide, of anchorFrame: CGRect) -> CGFloat {
        let inset = min(4, anchorFrame.width / 4)
        return side == .before ? anchorFrame.minX + inset : anchorFrame.maxX - inset
    }

    enum Direction { case left, right }

    // Given the whole bar in left-to-right order, which neighbour the item has
    // to pass next, and which way, to end up on `side` of `anchor`. Nil once it
    // is there (or if either is missing).
    //
    // A synthesized ⌘-drag reliably swaps an item with exactly one neighbour
    // (measured on macOS 27), so corrections pass one neighbour at a time.
    static func nextStep<ID: Equatable>(in order: [ID], item: ID, _ side: MenuBarDropSide, of anchor: ID) -> (pass: ID, direction: Direction)? {
        guard let itemIndex = order.firstIndex(of: item), let anchorIndex = order.firstIndex(of: anchor) else { return nil }
        guard itemIndex != anchorIndex else { return nil }
        let goal = side == .before ? anchorIndex - 1 : anchorIndex + 1
        if itemIndex == goal { return nil }
        // Too far left: pass the right-hand neighbour. Too far right: the left-hand one.
        let tooFarLeft = side == .before ? itemIndex < goal : itemIndex < anchorIndex
        return tooFarLeft ? (order[itemIndex + 1], .right) : (order[itemIndex - 1], .left)
    }
}
