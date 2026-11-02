//
//  MenuBarLayout.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// Which of Hidden Bar's sections a menu-bar item belongs to, read from where the
// user ⌘-dragged it relative to the separators:
//
//     LTR:  [ always hidden ] | [ hidden ] | > [ visible ]
//                             ^            ^
//                  always-hidden separator  separator (beside the arrow)
enum MenuBarSection: Int, Comparable {
    case visible
    case hidden
    case alwaysHidden

    static func < (lhs: MenuBarSection, rhs: MenuBarSection) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// One status item another app owns. On macOS 27 Accessibility exposes no title or
// identifier for these, so the owning bundle and the frame are all there is.
struct MenuBarInventoryItem: Equatable {
    let bundleIdentifier: String?
    let frame: CGRect
    var isUnreadable = false
    // Read only for SystemUIServer, whose icons are told apart by title.
    var title: String? = nil
}

// What to call a status item. macOS's own extras all belong to one process
// (SystemUIServer), so its name says nothing; their titles do ("Siri").
enum MenuBarItemNaming {
    static let systemExtraOwner = "com.apple.systemuiserver"

    // Nil for titles that carry no name: empty, "-", or a placeholder.
    static func cleanedTitle(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value != "-", !value.hasPrefix("Item-")
        else { return nil }
        return value
    }

    static func displayName(appName: String?, title: String?, isSystemExtra: Bool) -> String? {
        if isSystemExtra, let title = cleanedTitle(title) { return title }
        return appName
    }
}

// AppKit and Accessibility describe the same desktop with different vertical
// origins.  Keeping both rectangles here makes the conversion explicit and,
// more importantly, gives the resolver a stable display identity when two
// screens have different widths or are vertically offset.
struct MenuBarDisplay: Equatable {
    let identifier: String
    let appKitFrame: CGRect
    let accessibilityFrame: CGRect
}

protocol MenuBarInventoryProviding: AnyObject {
    var isAuthorized: Bool { get }
    func requestAuthorization()
    // Every other app's status items, delivered on the main queue. Only meaningful
    // while nothing is hidden: once a native visibility assertion is active,
    // hidden items report stale frames.
    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void)
    // The same, for the given apps only, which is much faster.
    func snapshot(of bundles: Set<String>, completion: @escaping ([MenuBarInventoryItem]) -> Void)
}

struct MenuBarLayout: Equatable {
    // One section per owning bundle, because hiding is per bundle.
    var sections: [String: MenuBarSection]

    func bundles(in wanted: Set<MenuBarSection>) -> [String] {
        return sections.filter { wanted.contains($0.value) }.map(\.key).sorted()
    }
}

enum MenuBarLayoutResolver {
    // Bundles whose items are macOS's own controls protected by system item
    // identifiers (clock, Wi-Fi, Control Center...). They cannot be hidden by
    // bundle, so they are left out of the layout and kept visible separately.
    // SystemUIServer is not one of them: its legacy Menu Extras (Time
    // Machine...) carry no system item identifier and can only stay visible
    // through the per-bundle allow list, so they are sectioned by position like
    // any other app.
    static let systemItemOwners: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter"]

    static func resolve(inventory: [MenuBarInventoryItem],
                        separatorFrame: CGRect,
                        alwaysHiddenSeparatorFrame: CGRect?,
                        displays: [MenuBarDisplay],
                        isLTR: Bool,
                        excludingBundle ownBundle: String?) -> MenuBarLayout? {
        guard let boundaryDisplay = display(containingAppKitPoint: midpoint(of: separatorFrame), in: displays),
              alwaysHiddenSeparatorFrame.map({ display(containingAppKitPoint: midpoint(of: $0), in: displays) == boundaryDisplay }) ?? true else {
            return nil
        }

        var sections: [String: MenuBarSection] = [:]
        for item in inventory {
            guard let bundle = item.bundleIdentifier,
                  bundle != ownBundle,
                  !systemItemOwners.contains(bundle) else { continue }
            if item.isUnreadable {
                sections[bundle] = .visible
                continue
            }
            // An unassigned third-party item must never be guessed into the
            // hidden side: the native API would otherwise hide an icon the user
            // intentionally kept visible.  The caller fails open in this case.
            guard let itemDisplay = display(containingAccessibilityPoint: midpoint(of: item.frame), in: displays) else {
                return nil
            }
            let section = self.section(of: item.frame,
                                       separatorFrame: projected(separatorFrame, from: boundaryDisplay, to: itemDisplay, isLTR: isLTR),
                                       alwaysHiddenSeparatorFrame: alwaysHiddenSeparatorFrame.map {
                                           projected($0, from: boundaryDisplay, to: itemDisplay, isLTR: isLTR)
                                       },
                                       isLTR: isLTR)
            // One app can own several items, but hiding applies to the whole
            // bundle. The most visible item wins so an icon the user kept visible
            // is never hidden because a sibling sits in the hidden section.
            sections[bundle] = min(sections[bundle] ?? section, section)
        }
        return MenuBarLayout(sections: sections)
    }

    // Menu-bar extras are anchored to the arrow edge of each screen.  Translate
    // the arrow and always-hidden marker by their distance from that edge rather
    // than reusing an absolute x-coordinate from whichever display AppKit chose
    // for the status item window.
    private static func projected(_ frame: CGRect, from source: MenuBarDisplay, to target: MenuBarDisplay, isLTR: Bool) -> CGRect {
        let distanceFromArrowEdge = isLTR
            ? source.appKitFrame.maxX - frame.midX
            : frame.midX - source.appKitFrame.minX
        let projectedMidX = isLTR
            ? target.accessibilityFrame.maxX - distanceFromArrowEdge
            : target.accessibilityFrame.minX + distanceFromArrowEdge
        return CGRect(x: projectedMidX - frame.width / 2, y: 0, width: frame.width, height: frame.height)
    }

    private static func display(containingAppKitPoint point: CGPoint, in displays: [MenuBarDisplay]) -> MenuBarDisplay? {
        return displays.first { $0.appKitFrame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    private static func display(containingAccessibilityPoint point: CGPoint, in displays: [MenuBarDisplay]) -> MenuBarDisplay? {
        return displays.first { $0.accessibilityFrame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    private static func midpoint(of frame: CGRect) -> CGPoint {
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    static func section(of frame: CGRect,
                        separatorFrame: CGRect,
                        alwaysHiddenSeparatorFrame: CGRect?,
                        isLTR: Bool) -> MenuBarSection {
        // Distance toward the arrow side: positive means on the visible side.
        func towardArrow(_ x: CGFloat, from boundary: CGRect) -> CGFloat {
            return isLTR ? x - boundary.midX : boundary.midX - x
        }
        if towardArrow(frame.midX, from: separatorFrame) > 0 {
            return .visible
        }
        if let alwaysHidden = alwaysHiddenSeparatorFrame,
           towardArrow(frame.midX, from: alwaysHidden) < 0 {
            return .alwaysHidden
        }
        return .hidden
    }
}

extension MenuBarDisplay {
    func appKitRect(fromAccessibility rect: CGRect) -> CGRect {
        return CGRect(x: rect.minX,
                      y: appKitFrame.maxY - (rect.minY - accessibilityFrame.minY) - rect.height,
                      width: rect.width,
                      height: rect.height)
    }

    func accessibilityRect(fromAppKit rect: CGRect) -> CGRect {
        return CGRect(x: rect.minX,
                      y: accessibilityFrame.minY + (appKitFrame.maxY - rect.maxY),
                      width: rect.width,
                      height: rect.height)
    }
}

// Filters hidden icons by name for Find Hidden Icon. Names that start with the
// query come first, then ones that contain it; case and accents don't matter.
// An empty query keeps every entry in its order.
enum HiddenIconSearch {
    static func matches<Entry>(_ entries: [Entry], query: String, name: (Entry) -> String) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let prefixed = entries.filter { name($0).range(of: query, options: options.union(.anchored)) != nil }
        let containing = entries.filter {
            name($0).range(of: query, options: options) != nil && name($0).range(of: query, options: options.union(.anchored)) == nil
        }
        return prefixed + containing
    }
}

// Where the separate bar's pieces of the menu bar are, in Accessibility
// coordinates, kept free of capture so it can be unit tested.
enum MenuBarStripGeometry {
    // The full height of the menu bar, from the leftmost to the rightmost of
    // `frames`, so one capture holds every hidden icon.
    static func strip(covering frames: [CGRect], menuBarHeight: CGFloat, on display: MenuBarDisplay) -> CGRect? {
        guard let first = frames.first else { return nil }
        let span = frames.dropFirst().reduce(first) { $0.union($1) }
        let strip = CGRect(x: span.minX, y: display.accessibilityFrame.minY, width: span.width, height: menuBarHeight)
        let clipped = strip.intersection(display.accessibilityFrame)
        return clipped.isEmpty ? nil : clipped
    }

    // The same icon in a newer read: an app's icons keep their order, so the
    // n-th of its icons stays the n-th wherever the bar shifted it.
    static func counterpart(of item: MenuBarInventoryItem, among items: [MenuBarInventoryItem],
                            in previous: [MenuBarInventoryItem]) -> MenuBarInventoryItem? {
        func siblings(_ list: [MenuBarInventoryItem]) -> [MenuBarInventoryItem] {
            list.filter { $0.bundleIdentifier == item.bundleIdentifier }.sorted { $0.frame.minX < $1.frame.minX }
        }
        guard let rank = siblings(previous).firstIndex(of: item) else { return nil }
        let now = siblings(items)
        return now.indices.contains(rank) ? now[rank] : nil
    }

    // The pixels of `frame` in an image of `strip` taken at `scale` pixels per
    // point, rounded outward to whole pixels and kept inside the image.
    static func pixelRect(of frame: CGRect, in strip: CGRect, scale: CGFloat) -> CGRect? {
        let local = frame.intersection(strip).offsetBy(dx: -strip.minX, dy: -strip.minY)
        guard !local.isEmpty else { return nil }
        let pixels = CGRect(x: local.minX * scale, y: local.minY * scale,
                            width: local.width * scale, height: local.height * scale).integral
        let bounds = CGRect(x: 0, y: 0, width: (strip.width * scale).rounded(), height: (strip.height * scale).rounded())
        let clipped = pixels.intersection(bounds)
        return clipped.isEmpty ? nil : clipped
    }
}

// Which apps' menu-bar icons Tuckaway has seen. macOS 27 puts a new app's icon
// at the far left, on the hidden side of the arrow, so without this a freshly
// installed app's icon would be hidden before the user ever saw it. A new app
// found on the hidden side stays visible ("pending") until the user decides.
//
// Keeping one visible marks the app instead of ⌘-dragging its icon right of the
// arrow: synthesized drags don't pass Tuckaway's own arrow (measured on 27.2),
// and on macOS 27 hiding is per app anyway.
struct NewMenuBarAppTracker: Equatable {
    // Nil until the first read, which only records what is already there.
    var known: Set<String>?
    var pending: Set<String> = []
    // Shown wherever their icons are, until moved to a hidden list in Menu Bar Items.
    var kept: Set<String> = []

    // Records the apps in `layout`; returns the new ones it keeps visible.
    mutating func observe(_ layout: MenuBarLayout) -> [String] {
        let bundles = Set(layout.sections.keys)
        guard let known = known else {
            self.known = bundles
            return []
        }
        let found = bundles.subtracting(known)
        self.known = known.union(found)
        let hidden = found.filter { layout.sections[$0] != .visible }
        pending.formUnion(hidden)
        return hidden.sorted()
    }

    mutating func resolve(_ bundle: String, keepVisible: Bool) {
        pending.remove(bundle)
        if keepVisible {
            kept.insert(bundle)
        } else {
            kept.remove(bundle)
        }
    }

    func applied(to layout: MenuBarLayout) -> MenuBarLayout {
        var layout = layout
        for bundle in pending.union(kept) where layout.sections[bundle] != nil {
            layout.sections[bundle] = .visible
        }
        return layout
    }
}

protocol NewMenuBarAppStore: AnyObject {
    var tracker: NewMenuBarAppTracker { get set }
}

final class InMemoryNewMenuBarAppStore: NewMenuBarAppStore {
    var tracker = NewMenuBarAppTracker()
}

final class UserDefaultsNewMenuBarAppStore: NewMenuBarAppStore {
    private let defaults: UserDefaults
    private static let knownKey = "knownMenuBarApps"
    private static let pendingKey = "pendingMenuBarApps"
    private static let keptKey = "keptVisibleMenuBarApps"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var tracker: NewMenuBarAppTracker {
        get {
            NewMenuBarAppTracker(known: (defaults.array(forKey: Self.knownKey) as? [String]).map(Set.init),
                                 pending: Set(defaults.array(forKey: Self.pendingKey) as? [String] ?? []),
                                 kept: Set(defaults.array(forKey: Self.keptKey) as? [String] ?? []))
        }
        set {
            defaults.set(newValue.known.map { $0.sorted() }, forKey: Self.knownKey)
            defaults.set(newValue.pending.sorted(), forKey: Self.pendingKey)
            defaults.set(newValue.kept.sorted(), forKey: Self.keptKey)
        }
    }
}

// Profiles (macOS 27): named sets of apps that show while collapsed, replacing
// what the arrow's layout would show. See docs/PROFILES.md.
struct MenuBarProfiles: Equatable {
    var profiles: [String: [String]] = [:]
    var active: String?
    // Switched to while a second display is connected.
    var displayProfile: String?
    // What was active before the display switch, restored when it's unplugged.
    // Nil when nothing was switched (a manual choice while docked sticks).
    var beforeDisplay: Switched?

    enum Switched: Equatable {
        case from(String?)
    }

    // Called on every display change with whether more than one is connected.
    mutating func displaysChanged(external: Bool) {
        if external {
            guard let displayProfile, profiles[displayProfile] != nil, active != displayProfile,
                  beforeDisplay == nil else { return }
            beforeDisplay = .from(active)
            active = displayProfile
        } else if case .from(let previous)? = beforeDisplay {
            beforeDisplay = nil
            if active == displayProfile {
                active = previous.flatMap { profiles[$0] != nil ? $0 : nil }
            }
        }
    }

    var activeApps: Set<String>? {
        active.flatMap { profiles[$0] }.map(Set.init)
    }

    var names: [String] {
        profiles.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    mutating func save(_ name: String, apps: [String]) {
        profiles[name] = apps.sorted()
    }

    mutating func delete(_ name: String) {
        if displayProfile == name { setDisplayProfile(nil) }
        profiles[name] = nil
        if active == name { active = nil }
    }

    // A switch already made for the old choice is undone first, so the new one
    // starts clean (and unplugging restores what the user had).
    mutating func setDisplayProfile(_ name: String?) {
        if case .from(let previous)? = beforeDisplay {
            beforeDisplay = nil
            if active == displayProfile {
                active = previous.flatMap { profiles[$0] != nil ? $0 : nil }
            }
        }
        displayProfile = name
    }

    // Hiding or un-keeping an app takes it out of the active profile too.
    mutating func removeFromActive(_ bundle: String) {
        guard let active, let apps = profiles[active] else { return }
        profiles[active] = apps.filter { $0 != bundle }
    }

    // A kept app joins the active profile too, or keeping it would do nothing.
    mutating func addToActive(_ bundle: String) {
        guard let active, var apps = profiles[active], !apps.contains(bundle) else { return }
        apps.append(bundle)
        profiles[active] = apps.sorted()
    }

    // The layout as a profile shows it: its apps (and any `alsoVisible`) are
    // visible, every other app is hidden, and always-hidden apps stay so.
    static func applied(_ apps: Set<String>, alsoVisible: Set<String>, to layout: MenuBarLayout) -> MenuBarLayout {
        var layout = layout
        for (bundle, section) in layout.sections where section != .alwaysHidden {
            layout.sections[bundle] = apps.contains(bundle) || alsoVisible.contains(bundle) ? .visible : .hidden
        }
        return layout
    }
}

final class UserDefaultsMenuBarProfilesStore {
    private let defaults: UserDefaults
    private static let profilesKey = "menuBarProfiles"
    private static let activeKey = "activeMenuBarProfile"
    private static let displayKey = "displayMenuBarProfile"
    // "" stands for "no profile was active"; profile names are never empty.
    private static let beforeDisplayKey = "menuBarProfileBeforeDisplay"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var profiles: MenuBarProfiles {
        get {
            MenuBarProfiles(profiles: defaults.dictionary(forKey: Self.profilesKey) as? [String: [String]] ?? [:],
                            active: defaults.string(forKey: Self.activeKey),
                            displayProfile: defaults.string(forKey: Self.displayKey),
                            beforeDisplay: defaults.string(forKey: Self.beforeDisplayKey).map { .from($0.isEmpty ? nil : $0) })
        }
        set {
            defaults.set(newValue.profiles, forKey: Self.profilesKey)
            defaults.set(newValue.active, forKey: Self.activeKey)
            defaults.set(newValue.displayProfile, forKey: Self.displayKey)
            if case .from(let previous)? = newValue.beforeDisplay {
                defaults.set(previous ?? "", forKey: Self.beforeDisplayKey)
            } else {
                defaults.removeObject(forKey: Self.beforeDisplayKey)
            }
        }
    }
}
