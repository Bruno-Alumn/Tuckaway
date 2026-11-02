//
//  MenuBarEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

enum ExpandIconStyle: String, CaseIterable {
    case standard
    case transparent
    case ellipsis

    var assetName: String? {
        switch self {
        case .standard: return "ic_expand"
        case .transparent: return "ic_expand_hidden"
        case .ellipsis: return nil
        }
    }
}

// StatusBarController decides WHAT the user wants (collapsed or expanded, which
// sections exist); an engine decides HOW the menu bar is made to do it. Keeping
// the mechanics here lets an OS release that changes menu-bar layout (#360) get
// its own engine without version checks spreading through the controller.
protocol MenuBarEngine: AnyObject {
    var state: MenuBarEngineState { get }

    func collapse(completion: @escaping (CollapseResult) -> Void)
    func expand()

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool)

    // Whether the user's ⌘-drag arrangement lets the engine hide anything: its
    // hiding boundary must sit on the hidden side of the arrow. The controller
    // does not collapse otherwise.
    var isArrangementValid: Bool { get }

    // Whether the always-hidden separator sits beyond the regular hidden section.
    var isAlwaysHiddenSeparatorPlaced: Bool { get }

    // Display geometry changed. Refreshes every hidden section independently,
    // preserving each section's presentation when displays are reconfigured.
    func invalidateLayout()
}

// macOS 27's separate hidden-items bar: macOS draws status items into the menu
// bar itself, so the bar shows the hidden section for a moment to capture it,
// and again to click one of its icons, without leaving the collapsed state.
protocol HiddenSectionPeeking: AnyObject {
    // Accessibility frames (top-left origin) of the hidden section's icons.
    var hiddenItems: [MenuBarInventoryItem] { get }
    var isPeeking: Bool { get }
    func peekHiddenSection(completion: @escaping (Bool) -> Void)
    func endPeek()
}

// New apps whose icons macOS 27 put on the hidden side are kept visible until
// the user decides (see NewMenuBarAppTracker). onNewApps gets every undecided
// app in the bar after each fresh read, so it repeats until they're resolved.
protocol NewMenuBarAppReporting: AnyObject {
    var onNewApps: (([String]) -> Void)? { get set }
    // Apps shown whatever their icon's place: kept, or new and undecided.
    var keptVisibleApps: Set<String> { get }
    func resolveNewApp(_ bundle: String, keepVisible: Bool)
}

// Presentation mode (macOS 27): hide every app's icon but Tuckaway's own;
// macOS's own items, such as the clock, stay.
protocol PresentationModeProviding: AnyObject {
    var isPresenting: Bool { get }
    func setPresenting(_ presenting: Bool)
}

enum MenuBarEngineState {
    case expanded
    case calibrating
    case collapsed
    case unavailable
}

enum CollapseResult {
    case collapsed
    case unavailable
}

enum MenuBarOrder {
    // True when `item` sits on the hidden side of `boundary`: to its left in a
    // left-to-right layout, to its right otherwise. False when either is not on
    // screen, since nothing can be judged then.
    static func isItem(_ item: NSStatusItem?, onHiddenSideOf boundary: NSStatusItem?) -> Bool {
        guard let itemOrigin = item?.button?.window?.frame.origin,
              let boundaryOrigin = boundary?.button?.window?.frame.origin,
              itemOrigin != .zero, boundaryOrigin != .zero else { return false }
        return Constant.isUsingLTRLanguage ? boundaryOrigin.x >= itemOrigin.x : boundaryOrigin.x <= itemOrigin.x
    }
}

// The controller owns and recreates the status items; engines only borrow them.
protocol MenuBarItemProvider: AnyObject {
    var toggleItem: NSStatusItem { get }
    var separatorItem: NSStatusItem { get }
    var alwaysHiddenItem: NSStatusItem? { get }
}
