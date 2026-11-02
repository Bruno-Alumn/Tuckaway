//
//  NativeVisibilityEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// macOS 27 hiding for the direct (non-App Store) build. Instead of inflating the
// separator, which macOS 27 ejects from the layout once it is too wide (#360),
// this reads which apps the user placed in each section and asks macOS to show
// only the allowed ones through the menu-bar visibility restriction behind
// assessment mode. macOS then hides the rest and reflows the bar itself, so the
// result does not depend on display width, the notch or the frontmost app's menus.
//
// The arrow is the boundary: apps left of it (LTR) are hidden, apps right of it
// stay visible. The regular separator is not needed and is taken out of the
// bar; even at zero width macOS keeps a gap for it. The always-hidden
// separator, when enabled, marks the third section; it shows while that section
// is shown so it can be ⌘-dragged, and is taken out of the bar while the section
// is hidden (collapsed, or expanded with "hide separators" on), where macOS has
// already removed everything it would separate. macOS puts it back where the
// user left it, which is what defines that section.
//
// Limits, all from what macOS 27 exposes:
// - Hiding is per app: an app with several icons hides or shows them together
//   (the most visible section wins).
// - The restriction is assessment (exam) mode's, and macOS applies the rest of
//   that mode while it is held (#437): Now Playing, Live Activities and the
//   capsule naming the app that uses the microphone or camera are hidden
//   whatever the allow-list says (the dot in the screen corner stays), and
//   clicking the clock does not open Notification Center (the trackpad swipe
//   still does). MenuBarAgent accepts two other origins for the same request,
//   and neither helps: userSessionTransition ignores the allow-list and hides
//   nothing, and campoDrag is rejected (measured on 27.0, 26A428). To keep that
//   capsule visible, no restriction is held while a microphone or camera is in
//   use; the bar is whole until capture stops, then hiding resumes.
// - macOS's own items that the allow-list can name (see systemItemsToKeep) are
//   always kept visible: Accessibility cannot tell them apart, so they cannot be
//   mapped to sections. SystemUIServer's legacy Menu Extras (Time Machine...)
//   are the exception: none was observed with a system item identifier, so they
//   are sectioned per bundle instead.
// - Hidden items report stale positions, so only shown ones are read. A collapse
//   from an unrestricted bar reads everything; with "hide separators" a
//   restriction is always held, so a collapse re-reads just the apps it shows
//   and keeps the always-hidden ones' cached section. An app launched while
//   something is hidden stays hidden until an unrestricted read, the same as a
//   new icon landing in the hidden section under the old mechanism.
// - The restriction is assessment mode, which makes macOS ignore the clock, so
//   Notification Center cannot open from it (#410). A click on the clock lifts
//   the restriction for a moment and presses it (MenuBarClock); hidden icons
//   can flash while it is lifted.
final class NativeVisibilityEngine: MenuBarEngine, HiddenSectionPeeking, NewMenuBarAppReporting, PresentationModeProviding, ActiveAppShowing, ProfileApplying {
    // System item identifiers to keep visible. Unknown identifiers are ignored,
    // so the range covers items a given Mac does not have. On 27.0, 0-63 resolves
    // to battery, bluetooth, clock, displays, keyboard, volume, wifi,
    // screenMirroring and primaryBentoBox (Control Center).
    static let systemItemsToKeep = Array(0..<64)

    private weak var items: MenuBarItemProvider?
    private let inventory: MenuBarInventoryProviding
    private let visibility: NativeVisibilityProviding
    private let captureActivity: CaptureActivityMonitoring
    private let clock: MenuBarClockProviding
    private let newApps: NewMenuBarAppStore
    var onNewApps: (([String]) -> Void)?
    private let ownBundleIdentifier: String?
    private let itemFrame: (NSStatusItem) -> CGRect?
    private let displays: () -> [MenuBarDisplay]
    private let isLTR: () -> Bool

    private let expandedLength: CGFloat = 20

    // .calibrating stands for "an activation is in flight".
    private(set) var state: MenuBarEngineState = .expanded
    private(set) var layout: MenuBarLayout?
    // The hidden section's icons from the last unrestricted read. While peeking
    // they show at the same frames: the bar is anchored on the arrow's side, and
    // only the always-hidden icons, further out, stay hidden.
    private(set) var hiddenItems: [MenuBarInventoryItem] = []
    // Every item from that read, so hiddenItems can follow a decision about a
    // new or kept app without reading the bar again.
    private var inventoryItems: [MenuBarInventoryItem] = []
    private(set) var isPeeking = false
    // Presentation mode: no app's icon shows but Tuckaway's own, whatever the
    // sections say. Collapsing and expanding meanwhile only update `state`,
    // which is applied when presentation mode ends.
    private(set) var isPresenting = false
    // Asked for while a collapse was being worked out; applied once it is.
    private var isPresentingPending = false

    private var assertion: NativeVisibilityAssertion?
    // What the held assertion allows besides Hidden Bar, and the generation it was
    // activated in, which stays current while nothing newer is in flight.
    private var assertionBundles: [String] = []
    private var assertionGeneration = 0
    // Bumped whenever a pending activation must no longer win (an expand, a newer
    // activation); a late success is then invalidated straight away.
    private var generation = 0
    // An activation that is never answered would leave the engine calibrating,
    // which ignores every collapse until relaunch; this runs the give-up check.
    private let afterActivationTimeout: (@escaping () -> Void) -> Void
    private var lastUnavailableReason: String?
    // The capture state last acted on, so only a change moves the restriction.
    private var isCaptureActive: Bool

    private var alwaysHiddenEnabled = false
    private var alwaysHiddenSeparatorHidden = false

    init(items: MenuBarItemProvider,
         inventory: MenuBarInventoryProviding = AccessibilityMenuBarInventory(),
         visibility: NativeVisibilityProviding = NativeVisibilityBridge(),
         captureActivity: CaptureActivityMonitoring = CaptureActivityMonitor(),
         clock: MenuBarClockProviding = SystemMenuBarClock(),
         newApps: NewMenuBarAppStore = InMemoryNewMenuBarAppStore(),
         ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
         itemFrame: @escaping (NSStatusItem) -> CGRect? = { $0.button?.window?.frame },
         displays: @escaping () -> [MenuBarDisplay] = MenuBarDisplayInventory.current,
         isLTR: @escaping () -> Bool = { Constant.isUsingLTRLanguage },
         afterActivationTimeout: @escaping (@escaping () -> Void) -> Void = {
             DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: $0)
         }) {
        self.items = items
        self.afterActivationTimeout = afterActivationTimeout
        self.inventory = inventory
        self.visibility = visibility
        self.captureActivity = captureActivity
        self.clock = clock
        self.newApps = newApps
        self.ownBundleIdentifier = ownBundleIdentifier
        self.itemFrame = itemFrame
        self.displays = displays
        self.isLTR = isLTR
        isCaptureActive = captureActivity.isActive
        items.separatorItem.isVisible = false
        captureActivity.onChange = { [weak self] in
            self?.captureActivityDidChange()
        }
    }

    func collapse(completion: @escaping (CollapseResult) -> Void) {
        if isPresenting {
            state = .collapsed
            return completion(.collapsed)
        }
        switch state {
        case .collapsed:
            endPeek()
            return completion(.collapsed)
        case .calibrating:
            // The activation in flight answers the request that started it.
            return
        case .expanded, .unavailable:
            break
        }
        if !hidesAlwaysHiddenSection {
            setSeparatorsVisible(true)
        }

        guard visibility.isAvailable else {
            logUnavailableOnce("the native menu-bar visibility API is not available in this build or on this macOS")
            state = .unavailable
            return completion(.unavailable)
        }
        guard inventory.isAuthorized else {
            // Without Accessibility the sections cannot be read, and guessing would
            // hide icons the user kept visible. Not latched: it works as soon as
            // the permission is granted.
            inventory.requestAuthorization()
            logUnavailableOnce("Accessibility permission is needed to read the menu-bar sections")
            return completion(.unavailable)
        }
        state = .calibrating
        withLayout(refreshingShownApps: true) { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                self.logUnavailableOnce("the arrow's position cannot be read yet")
                self.state = .expanded
                completion(.unavailable)
                return self.applyPendingPresentation()
            }
            self.activate(allowing: layout.bundles(in: [.visible])) { [weak self] succeeded in
                guard let self = self else { return }
                self.state = succeeded ? .collapsed : .expanded
                if succeeded {
                    self.setSeparatorsVisible(false)
                }
                completion(succeeded ? .collapsed : .unavailable)
                self.applyPendingPresentation()
                if self.visibleAppsChangedDuringCollapse {
                    self.visibleAppsChangedDuringCollapse = false
                    if succeeded, !self.isPresenting, let layout = self.effectiveLayout {
                        self.activate(allowing: layout.bundles(in: [.visible])) { _ in }
                    }
                }
            }
        }
    }

    func expand() {
        state = .expanded
        isPeeking = false
        // Presentation mode asked for during a collapse this expand cancels.
        applyPendingPresentation()
        if isPresenting { return }
        applyExpandedPresentation()
    }

    // Shows the hidden section while staying collapsed, for the separate bar to
    // capture it or to click one of its icons. The cached layout still holds:
    // sections only change by ⌘-dragging, which needs an expanded bar.
    func peekHiddenSection(completion: @escaping (Bool) -> Void) {
        guard state == .collapsed, !isPresenting, let layout = effectiveLayout else { return completion(false) }
        isPeeking = true
        activate(allowing: layout.bundles(in: [.visible, .hidden]), completion: completion)
    }

    func endPeek() {
        guard isPeeking else { return }
        isPeeking = false
        guard state == .collapsed, !isPresenting, let layout = effectiveLayout else { return }
        activate(allowing: layout.bundles(in: [.visible])) { _ in }
    }

    func refreshHiddenItemFrames(completion: @escaping ([MenuBarInventoryItem]) -> Void) {
        let bundles = Set(hiddenItems.compactMap(\.bundleIdentifier))
        guard isPeeking, !bundles.isEmpty else { return completion(hiddenItems) }
        inventory.snapshot(of: bundles) { [weak self] items in
            guard let self else { return }
            let fresh = items.filter { !$0.isUnreadable && $0.frame.width > 0 }
            // Keep the old frames if the read came back short (an app timed out).
            if Set(fresh.compactMap(\.bundleIdentifier)) == bundles, self.isPeeking {
                self.hiddenItems = fresh
            }
            completion(self.hiddenItems)
        }
    }

    // Presentation mode is meant for screen sharing, so unlike the other states it
    // holds its restriction while a camera or microphone is in use (the dot in
    // the screen corner still shows).
    func setPresenting(_ presenting: Bool) {
        // Starting it now would supersede the collapse in flight, whose answer
        // would then never arrive and leave the engine calibrating.
        if state == .calibrating && presenting && !isPresenting {
            isPresentingPending = true
            return
        }
        isPresentingPending = false
        guard presenting != isPresenting else { return }
        isPresenting = presenting
        isPeeking = false
        if presenting {
            guard visibility.isAvailable else { return }
            setSeparatorsVisible(false)
            activate(allowing: []) { _ in }
        } else {
            switch state {
            case .collapsed:
                guard let layout = effectiveLayout else {
                    state = .expanded
                    return revealAll()
                }
                activate(allowing: layout.bundles(in: [.visible])) { _ in }
            case .expanded:
                applyExpandedPresentation()
            case .calibrating, .unavailable:
                revealAll()
            }
        }
    }

    private func applyPendingPresentation() {
        guard isPresentingPending else { return }
        isPresentingPending = false
        setPresenting(true)
    }

    // Kept apps, and new ones not decided on yet: both show whatever their icon's place.
    var keptVisibleApps: Set<String> {
        newApps.tracker.kept.union(newApps.tracker.pending)
    }

    private func refreshHiddenItems() {
        guard let effective = effectiveLayout else { return }
        hiddenItems = inventoryItems.filter { item in
            item.bundleIdentifier.map { effective.sections[$0] == .hidden } ?? false
        }
    }

    // The user chose for a new app, or moved a kept one in Menu Bar Items.
    // While collapsed the restriction is redone right away.
    func resolveNewApp(_ bundle: String, keepVisible: Bool) {
        changeVisibleApps { newApps.tracker.resolve(bundle, keepVisible: keepVisible) }
    }

    // The sections as arranged, with kept apps and new ones the user hasn't
    // decided on yet visible.
    private var effectiveLayout: MenuBarLayout? {
        effectiveLayout(includingActiveApp: true)
    }

    private func effectiveLayout(includingActiveApp: Bool) -> MenuBarLayout? {
        layout.map { layout in
            var effective: MenuBarLayout
            if let profileApps {
                // New apps nobody has decided on yet still show, as without a profile.
                effective = MenuBarProfiles.applied(profileApps, alsoVisible: newApps.tracker.pending, to: layout)
            } else {
                effective = newApps.tracker.applied(to: layout)
            }
            // An app the user put in Always Hidden stays there.
            if includingActiveApp, let activeApp, effective.sections[activeApp] == .hidden {
                effective.sections[activeApp] = .visible
            }
            return effective
        }
    }

    private var activeApp: String?
    private var visibleAppsChangedDuringCollapse = false
    private var activationsInFlight = 0
    private var isPressingClock = false
    // The active profile's apps; nil when the arrow's layout decides.
    private var profileApps: Set<String>?

    func setActiveApp(_ bundle: String?) {
        guard bundle != activeApp else { return }
        changeVisibleApps { activeApp = bundle }
    }

    // What a profile saved now would keep: read fresh while the bar is shown
    // (icons may have moved since the last read), without the app that's only
    // shown for being in front. Nil while a collapse is being worked out, or
    // when nothing could be read.
    func readVisibleApps(completion: @escaping ([String]?) -> Void) {
        guard state != .calibrating else { return completion(nil) }
        let finish = { [weak self] in
            let apps = self?.effectiveLayout(includingActiveApp: false)?.bundles(in: [.visible])
            completion(apps?.isEmpty == false ? apps : nil)
        }
        // A fresh read would supersede an activation or clock press in flight.
        guard assertion == nil, activationsInFlight == 0, !isPressingClock else { return finish() }
        withLayout { _ in finish() }
    }

    func setProfile(_ apps: Set<String>?) {
        guard apps != profileApps else { return }
        changeVisibleApps { profileApps = apps }
    }

    // While collapsed the restriction is redone, but only when the effect
    // changes: an app that's visible anyway, or not in the bar, needs nothing.
    private func changeVisibleApps(_ change: () -> Void) {
        let before = effectiveLayout?.bundles(in: [.visible])
        change()
        refreshHiddenItems()
        // A collapse in flight already chose its list; redo it once it lands.
        if state == .calibrating {
            visibleAppsChangedDuringCollapse = true
            return
        }
        guard state == .collapsed, !isPeeking, !isPresenting, let layout = effectiveLayout,
              layout.bundles(in: [.visible]) != before else { return }
        activate(allowing: layout.bundles(in: [.visible])) { _ in }
    }

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {
        alwaysHiddenEnabled = enabled
        alwaysHiddenSeparatorHidden = separatorHidden
        if isPresenting { return setSeparatorsVisible(false) }
        switch state {
        case .collapsed:
            // A separator created while collapsed arrives visible.
            setSeparatorsVisible(false)
        case .expanded:
            applyExpandedPresentation()
        case .calibrating, .unavailable:
            setSeparatorsVisible(true)
        }
    }

    private var hidesAlwaysHiddenSection: Bool {
        return alwaysHiddenEnabled && alwaysHiddenSeparatorHidden
    }

    // A native visibility assertion is global, while AppKit may hand us the arrow
    // frame from any connected screen. On a display or workspace change there is
    // no safe cached answer: release the restriction and wait for the next fresh
    // expanded snapshot instead of hiding an icon from the wrong side.
    func invalidateLayout() {
        layout = nil
        // Presentation mode's allow-list doesn't depend on the layout, so it
        // keeps hiding; the state is re-read when it ends.
        if isPresenting {
            if assertion != nil { state = .expanded }
            return
        }
        if assertion != nil {
            releaseAssertion()
            state = .expanded
            setSeparatorsVisible(true)
            NSLog("NativeVisibility: released restriction while menu-bar layout is changing")
        } else {
            // Nothing held, but a read, an activation or a clock press may be in
            // flight with the old layout; drop it. Collapsed with nothing held
            // (a clock press) or mid-collapse, the bar is effectively expanded.
            generation += 1
            isPressingClock = false
            if state == .calibrating || (state == .collapsed && !captureActivity.isActive) {
                state = .expanded
                setSeparatorsVisible(true)
            }
        }
        applyPendingPresentation()
    }

    // Expanded shows the hidden section; the always-hidden section stays hidden
    // while "hide separators" is on, otherwise everything is revealed by dropping
    // the restriction altogether. Its separator goes and comes back with it, only
    // once the icons are hidden, so it never disappears on its own.
    private func applyExpandedPresentation() {
        guard hidesAlwaysHiddenSection, visibility.isAvailable, inventory.isAuthorized else {
            return revealAll()
        }
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                return self.revealAll()
            }
            self.activate(allowing: layout.bundles(in: [.visible, .hidden])) { [weak self] succeeded in
                self?.setSeparatorsVisible(!succeeded)
            }
        }
    }

    private func revealAll() {
        releaseAssertion()
        setSeparatorsVisible(true)
    }

    // The sections as the user arranged them. Read fresh only from an
    // unrestricted bar; while a restriction is active the cached ones stand in.
    // Superseded by any later expand or activation, like an activation is.
    private func withLayout(refreshingShownApps: Bool = false, _ body: @escaping (MenuBarLayout?) -> Void) {
        if assertion != nil {
            guard refreshingShownApps, layout != nil, generation == assertionGeneration else {
                return body(effectiveLayout)
            }
            return refreshShownApps(body)
        }
        guard let arrow = items?.toggleItem,
              let boundary = itemFrame(arrow) else { return body(nil) }
        let alwaysHiddenFrame = alwaysHiddenEnabled ? items?.alwaysHiddenItem.flatMap(itemFrame) : nil
        let isLTR = self.isLTR()
        generation += 1
        let generation = self.generation
        inventory.snapshot { [weak self] inventory in
            guard let self = self, generation == self.generation else { return }
            let displaySnapshot = self.displays()
            let layout = MenuBarLayoutResolver.resolve(inventory: inventory,
                                                       separatorFrame: boundary,
                                                       alwaysHiddenSeparatorFrame: alwaysHiddenFrame,
                                                       displays: displaySnapshot,
                                                       isLTR: isLTR,
                                                       excludingBundle: self.ownBundleIdentifier)
            guard let layout = layout else {
                NSLog("NativeVisibility: layout is incomplete for the connected displays; leaving the bar expanded")
                return body(nil)
            }
            NSLog("NativeVisibility: arrow at x=\(boundary.midX); visible \(layout.bundles(in: [.visible])), hidden \(layout.bundles(in: [.hidden])), always hidden \(layout.bundles(in: [.alwaysHidden]))")
            self.layout = layout
            let found = self.newApps.tracker.observe(layout)
            // The same layout every other path uses: kept and new apps, the
            // active profile and the frontmost app.
            let effective = self.effectiveLayout ?? layout
            self.inventoryItems = inventory
            self.refreshHiddenItems()
            if !found.isEmpty {
                NSLog("NativeVisibility: keeping new menu-bar apps visible: \(found)")
            }
            // Every undecided app that is in the bar, so one found before a
            // relaunch is still asked about.
            let undecided = self.newApps.tracker.pending.filter { layout.sections[$0] != nil }.sorted()
            if !undecided.isEmpty {
                self.onNewApps?(undecided)
            }
            body(effective)
        }
    }

    // With "hide separators" on a restriction is held even while expanded, so
    // the bar was never read again and icons ⌘-dragged since kept their old
    // section. The apps the held restriction shows report live frames, so
    // those are re-read and re-sectioned; the hidden ones (always hidden) keep
    // their cached section. Apps launched meanwhile are hidden by that
    // restriction and still wait for an unrestricted read. If the read can't be
    // resolved, the cached layout stands, as before.
    private func refreshShownApps(_ body: @escaping (MenuBarLayout?) -> Void) {
        guard let arrow = items?.toggleItem, let boundary = itemFrame(arrow) else { return body(effectiveLayout) }
        let shown = Set(assertionBundles)
        let alwaysHiddenFrame = alwaysHiddenEnabled ? items?.alwaysHiddenItem.flatMap(itemFrame) : nil
        let isLTR = self.isLTR()
        generation += 1
        let generation = self.generation
        inventory.snapshot(of: shown) { [weak self] items in
            guard let self = self, generation == self.generation else { return }
            let live = items.filter { item in item.bundleIdentifier.map(shown.contains) ?? false }
            if let fresh = MenuBarLayoutResolver.resolve(inventory: live,
                                                         separatorFrame: boundary,
                                                         alwaysHiddenSeparatorFrame: alwaysHiddenFrame,
                                                         displays: self.displays(),
                                                         isLTR: isLTR,
                                                         excludingBundle: self.ownBundleIdentifier),
               var layout = self.layout {
                for (bundle, section) in fresh.sections {
                    layout.sections[bundle] = section
                }
                self.layout = layout
                self.inventoryItems = self.inventoryItems.filter { item in
                    !(item.bundleIdentifier.map(shown.contains) ?? false)
                } + live
                self.refreshHiddenItems()
            }
            body(self.effectiveLayout)
        }
    }

    // Activates the new restriction before dropping the old one, so switching
    // between collapsed and expanded never flashes the whole bar visible.
    // While a microphone or camera is in use nothing is activated, but the
    // request still succeeds: the bar keeps the state the user asked for and the
    // restriction follows once capture stops.
    private func activate(allowing bundles: [String], completion: @escaping (Bool) -> Void) {
        generation += 1
        let generation = self.generation
        guard !captureActivity.isActive || isPresenting else {
            dropAssertionForCapture()
            return completion(true)
        }
        let allowed = (ownBundleIdentifier.map { [$0] } ?? []) + bundles
        var answered = false
        activationsInFlight += 1
        afterActivationTimeout { [weak self] in
            guard let self = self, !answered else { return }
            answered = true
            self.activationsInFlight -= 1
            guard generation == self.generation else { return }
            NSLog("NativeVisibility: activation timed out")
            // A late answer is now stale (failing bumps the generation) and is
            // invalidated when it arrives.
            self.didFailToActivate()
            completion(false)
        }
        visibility.activate(allowedSystemItems: Self.systemItemsToKeep,
                            allowedBundleIdentifiers: allowed) { [weak self] result in
            let timedOut = answered
            answered = true
            if !timedOut { self?.activationsInFlight -= 1 }
            guard let self = self, !timedOut, generation == self.generation else {
                if case .success(let stale) = result { stale.invalidate() }
                return
            }
            switch result {
            case .success(let newAssertion) where self.captureActivity.isActive && !self.isPresenting:
                // Capture started while this was in flight.
                newAssertion.invalidate()
                self.dropAssertionForCapture()
                completion(true)
            case .success(let newAssertion):
                let old = self.assertion
                self.assertion = newAssertion
                self.assertionBundles = bundles
                self.assertionGeneration = generation
                old?.invalidate()
                self.watchClock()
                completion(true)
            case .failure(let error):
                NSLog("NativeVisibility: activation failed: \(error.localizedDescription)")
                self.didFailToActivate()
                completion(false)
            }
        }
    }

    // Fail open: never leave icons hidden after an error or a timeout, and never
    // keep an older restriction that no longer matches what was asked. A
    // collapse's own completion sets its state; other callers (peeks, profile
    // and app changes, the clock) leave the bar collapsed in name only, so it
    // reads as expanded and the next collapse hides again.
    private func didFailToActivate() {
        releaseAssertion()
        isPresenting = false
        isPeeking = false
        if state == .collapsed {
            state = .expanded
            setSeparatorsVisible(true)
        }
    }

    // The always-hidden separator is taken out of the bar while its section is
    // hidden; a zero-width item would still be there and clickable.
    private func setSeparatorsVisible(_ visible: Bool) {
        items?.separatorItem.isVisible = false
        let shown = visible && alwaysHiddenEnabled
        items?.alwaysHiddenItem?.length = shown ? expandedLength : 0
        items?.alwaysHiddenItem?.isVisible = shown
    }

    // Any arrangement works: whatever sits left of the arrow is the hidden section.
    var isArrangementValid: Bool {
        return true
    }

    var isAlwaysHiddenSeparatorPlaced: Bool {
        return MenuBarOrder.isItem(items?.alwaysHiddenItem, onHiddenSideOf: items?.toggleItem)
    }

    private func releaseAssertion() {
        generation += 1
        assertion?.invalidate()
        assertion = nil
        watchClock()
    }

    // Any held restriction, collapsed or expanded with the always-hidden section
    // hidden, stops the clock from opening Notification Center.
    private func watchClock() {
        clock.onClick = assertion == nil ? nil : { [weak self] location in
            self?.openNotificationCenter(from: location)
        }
    }

    // macOS ignores the clock while a restriction is held, so lift it just long
    // enough for a press to land, then put the same one back. The panel stays
    // open under the restriction; hidden icons can show for a moment.
    private func openNotificationCenter(from location: CGPoint) {
        // Not while an activation or a section read is in flight: lifting now
        // would cancel it, and a cancelled collapse never reports back.
        guard assertion != nil, generation == assertionGeneration else { return }
        NSLog("NativeVisibility: lifting the restriction for a click on the clock")
        let bundles = assertionBundles
        releaseAssertion()
        let generation = self.generation
        isPressingClock = true
        clock.press(at: location) { [weak self] in
            self?.isPressingClock = false
            // An expand or collapse meanwhile already applied what the user wants.
            guard let self = self, generation == self.generation else { return }
            self.activate(allowing: bundles) { _ in }
        }
    }

    // Unlike releaseAssertion, an activation in flight is not superseded: it
    // still answers the collapse that started it, and drops its own result
    // because capture is active.
    private func dropAssertionForCapture() {
        assertion?.invalidate()
        assertion = nil
        watchClock()
    }

    private func captureActivityDidChange() {
        let isActive = captureActivity.isActive
        guard isActive != isCaptureActive else { return }
        isCaptureActive = isActive
        if isActive {
            if isPresenting { return }
            NSLog("NativeVisibility: a microphone or camera is in use; showing the whole menu bar until it stops")
            dropAssertionForCapture()
        } else {
            NSLog("NativeVisibility: capture stopped; hiding again")
            restorePresentation()
        }
    }

    // Re-applies the current state from a fresh read of the bar, which nothing
    // restricts at this point. A failure leaves the bar whole (fail open).
    private func restorePresentation() {
        if isPresenting {
            return activate(allowing: []) { _ in }
        }
        switch state {
        case .collapsed:
            withLayout { [weak self] layout in
                guard let self = self, let layout = layout else { return }
                self.activate(allowing: layout.bundles(in: self.isPeeking ? [.visible, .hidden] : [.visible])) { _ in }
            }
        case .expanded:
            applyExpandedPresentation()
        case .calibrating, .unavailable:
            // An activation in flight checks capture itself; unavailable holds nothing.
            break
        }
    }

    // Logged when the reason changes, so a retried collapse does not spam.
    private func logUnavailableOnce(_ reason: String) {
        guard reason != lastUnavailableReason else { return }
        lastUnavailableReason = reason
        NSLog("NativeVisibility: hiding unavailable: \(reason)")
    }
}
