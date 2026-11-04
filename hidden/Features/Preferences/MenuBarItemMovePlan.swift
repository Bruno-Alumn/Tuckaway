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

// How a move between the Menu Bar Items lists reaches the real menu bar.
enum MenuBarMoveAction: Equatable {
    case drag
    // Keep the app visible by name (macOS 27) instead of dragging its icon.
    case keepVisible
    // An app kept visible by name goes back to being placed by its icon.
    case stopKeepingAndDrag
    // Nothing to do in the menu bar.
    case none
}

// The pure part of moving an item from the Menu Bar Items lists, kept free of
// AppKit and Accessibility so it can be unit tested.
enum MenuBarItemMovePlan {
    // On macOS 27 a synthesized ⌘-drag doesn't pass Tuckaway's own arrow
    // (measured on 27.2), so a move into Visible marks the app instead, as
    // Keep Visible does. `marksVisibleApps` is true there.
    static func action(from: MenuBarSection, to: MenuBarSection, isKept: Bool, marksVisibleApps: Bool) -> MenuBarMoveAction {
        guard marksVisibleApps else { return .drag }
        if to == .visible {
            // A kept app's icon sits on the hidden side, so reordering it
            // within Visible would have to pass the arrow too.
            return from == .visible ? (isKept ? .none : .drag) : .keepVisible
        }
        return isKept ? .stopKeepingAndDrag : .drag
    }

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

    // The same, ignoring `excluded` neighbours: apps kept visible by name are
    // listed under Visible while their icons sit on the hidden side, so a drop
    // next to one would aim at the wrong side of the arrow.
    static func anchor(for id: String, in ordered: [String], excluding excluded: Set<String>) -> MenuBarDropAnchor {
        anchor(for: id, in: ordered.filter { $0 == id || !excluded.contains($0) })
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

// New weights for MenuBarLayoutStore's table (larger is further left) that put
// `moving` on `side` of `anchor`, keeping the moving keys' own order. The
// moving keys go evenly between the anchor and its neighbour; if they're too
// close to fit, every key is renumbered in its current order instead. Nil if
// the anchor has no weight.
enum MenuBarPositionPlan {
    static let spacing = 16.0

    // The keys an app owns in the table, given its names: MenuBarAgent keys an
    // item by its app's bundle identifier or its executable name.
    static func keys(in table: [String: Double], forAppsNamed names: [String]) -> [String] {
        let prefixes = Set(names).map { "status:\($0)::" }
        return table.keys.filter { key in prefixes.contains { key.hasPrefix($0) } }.sorted()
    }

    static func weights(moving: [String], _ side: MenuBarDropSide, of anchor: [String],
                        in table: [String: Double]) -> [String: Double]? {
        let anchorWeights = anchor.compactMap { table[$0] }
        guard !moving.isEmpty, !anchorWeights.isEmpty else { return nil }
        let movingSet = Set(moving)
        let others = table.filter { !movingSet.contains($0.key) }
        // Left to right.
        let movingOrder = moving.sorted { (table[$0] ?? 0) > (table[$1] ?? 0) }

        var right: Double?
        var left: Double?
        switch side {
        case .before:
            right = anchorWeights.max()!
            left = others.values.filter { $0 > right! }.min()
        case .after:
            left = anchorWeights.min()!
            right = others.values.filter { $0 < left! }.max()
        }
        let low = right ?? left! - spacing * Double(moving.count + 1)
        let high = left ?? right! + spacing * Double(moving.count + 1)
        let step = (high - low) / Double(moving.count + 1)
        if step >= 0.5 {
            return Dictionary(uniqueKeysWithValues: movingOrder.enumerated().map { index, key in
                (key, high - step * Double(index + 1))
            })
        }

        // No room: lay everything out again, right to left.
        let anchorKeys = Set(anchor)
        var order = others.sorted { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
        let insertAt: Int
        switch side {
        case .before: insertAt = (order.lastIndex { anchorKeys.contains($0) } ?? order.count - 1) + 1
        case .after: insertAt = order.firstIndex { anchorKeys.contains($0) } ?? 0
        }
        order.insert(contentsOf: movingOrder.reversed(), at: insertAt)
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, Double($0) * spacing) })
    }
}

// macOS 27 hides whole apps (#427), so Menu Bar Items lists one row per app
// there: an app with two icons would otherwise show twice, and moving one
// would move both. Items without a key (macOS's own, which are kept visible
// one by one) stay a row each.
enum MenuBarItemGrouping {
    struct Group<Item> {
        let section: MenuBarSection
        // Left to right, as given.
        let items: [Item]
    }

    // `items` in menu-bar order; each group sits where its leftmost item is.
    // An app is as visible as its most visible icon, as MenuBarLayout.resolve
    // decides, so that's the list it shows in.
    static func grouped<Item>(_ items: [Item], key: (Item) -> String?,
                              section: (Item) -> MenuBarSection) -> [Group<Item>] {
        var order: [String] = []
        var members: [String: [Item]] = [:]
        for (index, item) in items.enumerated() {
            let groupKey = key(item).map { "app:" + $0 } ?? "item:\(index)"
            if members[groupKey] == nil { order.append(groupKey) }
            members[groupKey, default: []].append(item)
        }
        return order.map { groupKey in
            let items = members[groupKey]!
            return Group(section: items.map(section).min()!, items: items)
        }
    }
}
