//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices

// macOS persists status-item positions before the items are created. Larger
// values sit further left; the required outer-to-inner order is always-hidden,
// separator, arrow. Repair only misplaced items and keep the separator anchored.
enum StatusItemPositions {
    private static let arrowKey = "NSStatusItem Preferred Position hiddenbar_expandcollapse"
    private static let separatorKey = "NSStatusItem Preferred Position hiddenbar_separate"
    private static let alwaysHiddenKey = "NSStatusItem Preferred Position hiddenbar_terminate"
    private static let slotGap: Double = 50

    static func repairIfNeeded() {
        let defaults = UserDefaults.standard
        let arrow = defaults.object(forKey: arrowKey) as? Double
        let separator = defaults.object(forKey: separatorKey) as? Double
        let alwaysHidden = defaults.object(forKey: alwaysHiddenKey) as? Double
        if arrow == nil && separator == nil && alwaysHidden == nil { return }
        if isOrderValid(arrow: arrow, separator: separator, alwaysHidden: alwaysHidden) { return }

        guard let separator = separator else {
            defaults.removeObject(forKey: alwaysHiddenKey)
            return
        }
        let repairedArrow = isOuter(separator, than: arrow) ? arrow : inward(of: separator)
        let repairedAlwaysHidden = alwaysHidden.map { isOuter($0, than: separator) ? $0 : outward(of: separator) }
        if let repairedArrow = repairedArrow {
            defaults.set(repairedArrow, forKey: arrowKey)
        }
        if let repairedAlwaysHidden = repairedAlwaysHidden {
            defaults.set(repairedAlwaysHidden, forKey: alwaysHiddenKey)
        }
    }

    static func pullArrowInside() {
        let defaults = UserDefaults.standard
        guard let separator = defaults.object(forKey: separatorKey) as? Double else {
            reset()
            return
        }
        defaults.set(inward(of: separator), forKey: arrowKey)
    }

    private static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: arrowKey)
        defaults.removeObject(forKey: separatorKey)
        defaults.removeObject(forKey: alwaysHiddenKey)
    }

    private static func inward(of position: Double) -> Double {
        NSApplication.shared.userInterfaceLayoutDirection == .leftToRight ? position - slotGap : position + slotGap
    }

    private static func outward(of position: Double) -> Double {
        NSApplication.shared.userInterfaceLayoutDirection == .leftToRight ? position + slotGap : position - slotGap
    }

    private static func isOrderValid(arrow: Double?, separator: Double?, alwaysHidden: Double?) -> Bool {
        isOuter(alwaysHidden, than: separator) && isOuter(separator, than: arrow)
    }

    private static func isOuter(_ outer: Double?, than inner: Double?) -> Bool {
        guard let outer = outer else { return true }
        guard let inner = inner else { return false }
        return NSApplication.shared.userInterfaceLayoutDirection == .leftToRight ? outer > inner : outer < inner
    }
}

class StatusBarController: MenuBarItemProvider {
    
    //MARK: - Variables
    private var timer:Timer? = nil
    private var accessibilityPermission = AccessibilityPermissionTransition(
        isTrusted: !Util.isAccessibilityPermissionMissing
    )

    //MARK: - BarItems

    private var btnExpandCollapse: NSStatusItem
    private var btnSeparate: NSStatusItem
    private var btnAlwaysHidden:NSStatusItem? = nil

    //MARK: - Notch Overflow
    private var notchOverflowController = NotchOverflowController()
    private let hiddenItemsBarController = HiddenItemsBarPanelController()
    private let hiddenItemsCaptureShieldController = HiddenItemsBarCaptureShieldController()
    private let hiddenItemsSeparatorOverlayController = HiddenItemsBarSeparatorOverlayController()
    private var activeExpandCollapseFrame: CGRect?
    private var activeStatusItemScreen: NSScreen?
    private var didExpandForExternalDisplay = false
    private var configurationDragMonitor: Any?
    private var isTemporarilyExpandedForConfigurationDrag = false
    private var configurationDragCollapseWorkItem: DispatchWorkItem?
    private var recollapseWorkItem: DispatchWorkItem?
    
    var toggleItem: NSStatusItem { btnExpandCollapse }
    var separatorItem: NSStatusItem { btnSeparate }
    var alwaysHiddenItem: NSStatusItem? { btnAlwaysHidden }
    
    // How hiding is achieved (separator lengths) lives in the engine; this class
    // owns the items, the UI, and when to collapse or expand.
    private lazy var menuBarEngine: MenuBarEngine = MenuBarEngineFactory.make(items: self)
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    
    private var isCollapsed: Bool {
        return menuBarEngine.state == .collapsed
    }

    private var usesSeparateHiddenItemsBar: Bool {
        return Preferences.showHiddenItemsInSeparateBar && MenuBarEngineFactory.supportsSeparateHiddenItemsBar
    }

    private var isSeparateHiddenItemsBarVisible: Bool {
        hiddenItemsBarController.isVisible
    }

    private var isMenuBarGeometryReady: Bool {
        guard let arrowOrigin = btnExpandCollapse.button?.window?.frame.origin,
              let separatorOrigin = btnSeparate.button?.window?.frame.origin else { return false }
        return arrowOrigin != .zero && separatorOrigin != .zero
    }
    
    private var isBtnAlwaysHiddenValidPosition: Bool {
        if !Preferences.alwaysHiddenSectionEnabled { return true }
        return menuBarEngine.isAlwaysHiddenSeparatorPlaced
    }
    
    private var isToggle = false
    private var arrowRescueCount = 0

    private var hoverMonitor: Any?
    private var hoverDwellTimer: Timer?
    private var emptyMenuBarMonitor: Any?

    // True while the pointer sits in any screen's menubar band (the strip between
    // visibleFrame.maxY and frame.maxY, which is the menubar's exact height there).
    // On fullscreen spaces the menubar is hidden and the band collapses to ~zero,
    // so this returns false there: intentional, no visible menubar = no deferral.
    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }

    // Any mouse button held, anywhere: a click or drag is still in progress.
    private var isMouseButtonDown: Bool {
        return NSEvent.pressedMouseButtons != 0
    }

    // The preferences window is an ordinary app window, not in the menu bar, so
    // the mouse-in-menubar guard does not cover it. With "use full menu bar on
    // expanding" on, an auto-collapse deactivates the app and dismisses this
    // window mid-edit (#170, same family as #66/#151). Defer the collapse while
    // it is on screen, without creating the controller or loading its window
    // when preferences were never opened.
    private var isPreferencesWindowVisible: Bool {
        return PreferencesWindowController.isVisible
    }
    
    //MARK: - Methods
    init() {
        StatusItemPositions.repairIfNeeded()
        btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        btnSeparate = NSStatusBar.system.statusItem(withLength: 1)
        setupUI()
        restoreRemovedStatusItems()
        setupAlwayHideStatusBar()
        updateConfigurationDragMonitor()
        updateHoverMonitor()
        updateEmptyMenuBarMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWorkspaceMenuBarChange), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWorkspaceMenuBarChange), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleApplicationActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateExpandIcon), name: .transparentExpandIconToggle, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLegacyHideUnavailable), name: .legacyHideUnavailable, object: nil)
        if MenuBarEngineFactory.usesNativeVisibility {
            Util.observeAccessibilityPermissionChanges()
            NotificationCenter.default.addObserver(self, selector: #selector(handleAccessibilityPermissionChanged), name: .accessibilityPermissionChanged, object: nil)
        }
        collapseWhenGeometryReady()
        autoCollapseIfNeeded()
    }

    // Wait until macOS has placed both items; zero origins are not a valid order.
    private func collapseWhenGeometryReady(attempt: Int = 0) {
        let delay = attempt == 0 ? 1.0 : 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if self.isMenuBarGeometryReady || attempt >= 20 {
                if Preferences.areSeparatorsHidden { self.hideSeparators() }
                self.collapseMenuBar()
            } else {
                self.collapseWhenGeometryReady(attempt: attempt + 1)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let configurationDragMonitor = configurationDragMonitor {
            NSEvent.removeMonitor(configurationDragMonitor)
        }
        configurationDragCollapseWorkItem?.cancel()
        hoverDwellTimer?.invalidate()
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let emptyMenuBarMonitor {
            NSEvent.removeMonitor(emptyMenuBarMonitor)
        }
    }

    private func updateHoverMonitor() {
        guard Preferences.hoverToExpand else {
            hoverDwellTimer?.invalidate()
            hoverDwellTimer = nil
            if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
            hoverMonitor = nil
            return
        }
        guard hoverMonitor == nil else { return }
        NSLog("HoverToExpand: enabled, installing global mouse monitor")
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self else { return }
            guard self.isCollapsed && self.isMouseInMenuBar else {
                self.hoverDwellTimer?.invalidate()
                self.hoverDwellTimer = nil
                return
            }
            // Short dwell so a pointer merely passing through doesn't expand.
            guard self.hoverDwellTimer == nil else { return }
            self.hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.hoverDwellTimer = nil
                // A press means the user is clicking or ⌘-dragging an icon;
                // expanding under it would reflow the bar mid-gesture.
                if self.isCollapsed && self.isMouseInMenuBar && !self.isMouseButtonDown {
                    self.expandMenubar()
                }
            }
        }
    }

    private func updateEmptyMenuBarMonitor() {
        if Preferences.clickEmptyMenuBarToToggle {
            guard emptyMenuBarMonitor == nil else { return }
            emptyMenuBarMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                guard let self, self.isEmptyMenuBarClick() else { return }
                self.expandCollapseIfNeeded()
            }
        } else if let emptyMenuBarMonitor {
            NSEvent.removeMonitor(emptyMenuBarMonitor)
            self.emptyMenuBarMonitor = nil
        }
    }

    private func isEmptyMenuBarClick() -> Bool {
        guard isMouseInMenuBar,
              let desktopTop = NSScreen.screens.map(\.frame.maxY).max(),
              !Util.isAccessibilityPermissionMissing else { return false }
        let mouse = NSEvent.mouseLocation
        let point = ExpandCollapseActionResolver.accessibilityPoint(forAppKitPoint: mouse, desktopTop: desktopTop)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element else { return false }
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success else { return false }
        return ExpandCollapseActionResolver.isEmptyMenuBar(role: roleValue as? String)
    }
    
    @objc private func handleScreenParametersChanged() {
        activeExpandCollapseFrame = nil
        activeStatusItemScreen = nil
        let wasCollapsed = isCollapsed
        invalidateNativeLayoutAfterEnvironmentChange()
        applyExternalDisplayPreference(force: wasCollapsed)
    }

    // A new status item or a wake can change the Accessibility inventory just
    // as much as a monitor hot-plug. The native engine releases its global
    // restriction here instead of applying a stale per-display classification.
    @objc private func handleWorkspaceMenuBarChange() {
        invalidateNativeLayoutAfterEnvironmentChange()
    }

    @objc private func handleApplicationActivated(_ notification: Notification) {
        guard Preferences.autoCollapseOnFocusChange, !isCollapsed, !isMouseButtonDown,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        collapseMenuBar()
    }

    private func invalidateNativeLayoutAfterEnvironmentChange() {
        let wasCollapsed = isCollapsed
        // The engine refreshes both sections independently: the always-hidden
        // section can still need a wider spacer while the ordinary one is open.
        menuBarEngine.invalidateLayout()
        if wasCollapsed && !isCollapsed {
            didFailToCollapseMenuBar()
            scheduleRecollapse()
        }
        if wasCollapsed && Preferences.areSeparatorsHidden {
            menuBarEngine.updateAlwaysHiddenSection(enabled: Preferences.alwaysHiddenSectionEnabled, separatorHidden: true)
        }
    }

    // The engine reveals everything while the layout is stale. Hide again once
    // launches, wakes and display changes have settled (each one restarts the
    // wait), unless the user is in the menu bar or an external display keeps
    // the bar open.
    private func scheduleRecollapse(after delay: TimeInterval = 2) {
        recollapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isCollapsed, !self.didExpandForExternalDisplay else { return }
            if self.isMouseInMenuBar || self.isMouseButtonDown {
                self.scheduleRecollapse(after: 1)
                return
            }
            self.collapseMenuBar()
        }
        recollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func applyExternalDisplayPreference(force: Bool = false) {
        if Preferences.expandWhenExternalDisplayConnected && NSScreen.screens.count > 1 {
            guard isCollapsed || force else { return }
            didExpandForExternalDisplay = true
            expandMenubar(force: true)
        } else if didExpandForExternalDisplay {
            didExpandForExternalDisplay = false
            collapseMenuBar()
        }
    }
    
    // Collapsing failed while the permission was missing; once it is granted,
    // hide straight away instead of waiting for the next click or relaunch.
    @objc private func handleAccessibilityPermissionChanged() {
        guard accessibilityPermission.permissionWasRestored(
            isTrusted: !Util.isAccessibilityPermissionMissing
        ) else { return }
        collapseMenuBar()
    }

    private func restoreRemovedStatusItems() {
        // Cmd-dragging a status item off the bar is persisted by macOS via
        // autosaveName, leaving the app running but unreachable. These items are
        // the app's only UI, so they self-restore at launch.
        btnExpandCollapse.isVisible = true
        btnSeparate.isVisible = true
        // Create the engine now so one that does not use the separator (macOS 27
        // native hiding) takes it back out before it is ever drawn.
        _ = menuBarEngine
    }

    private func setupUI() {
        if let button = btnSeparate.button {
            button.image = self.imgIconLine
            button.target = self
            button.action = #selector(self.showContextMenuFromSeparator(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
            button.target = self
            
            button.action = #selector(self.btnExpandCollapsePressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        btnExpandCollapse.autosaveName = "hiddenbar_expandcollapse";
        btnSeparate.autosaveName = "hiddenbar_separate";
    }
    
    @objc func btnExpandCollapsePressed(sender: NSStatusBarButton) {
        activeExpandCollapseFrame = sender.window?.frame
        activeStatusItemScreen = sender.window?.screen
        let event = NSApp.currentEvent
        // AXPress synthesis carries no NSEvent; the resolver maps nil to .toggle
        // so VoiceOver can operate the bar.
        let optionPressed = ExpandCollapseActionResolver.isOptionPressed(eventFlags: event?.modifierFlags, liveFlags: NSEvent.modifierFlags)
        let controlPressed = (event?.modifierFlags.contains(.control) ?? false) || NSEvent.modifierFlags.contains(.control)
        switch ExpandCollapseActionResolver.action(eventType: event?.type, optionPressed: optionPressed, controlPressed: controlPressed) {
        case .toggle:
            self.expandCollapseIfNeeded()
        case .contextMenu:
            // Control-right-click opens the menu; plain right-click toggles (#434).
            showContextMenu(from: sender)
        case .toggleSeparators:
            // Both option+left and option+right land here: separators toggle.
            self.showHideSeparatorsAndAlwayHideArea()
        }
    }

    @objc private func showContextMenuFromSeparator(sender: NSStatusBarButton) {
        showContextMenu(from: sender)
    }

    // Builds a brand-new NSMenu for every presentation rather than mutating
    // a reused one via a delegate callback (content changes on an
    // already-displayed-before NSMenu instance could leave its backing
    // window at a stale size until an unrelated redraw corrected it).
    //
    // Uses popUp(at:), not performClick(nil): this method is ITSELF called
    // from this same button's own action handler (a real click already in
    // progress). performClick(nil) here re-entered NSStatusBarButtonCell's
    // own sendAction dispatch, recursing into this handler again and
    // stack-overflowing (SIGSEGV, confirmed via crash report) - unlike
    // NotchOverflowController.showOverflowMenuFromSeparator, which is safe
    // because it's invoked from a *different* control's action (a menu
    // item), not from btnExpandCollapse's own click handler.
    //
    // Previously anchored at `button.bounds.maxY + 5` (5pt above the
    // button's TOP edge). For a menu-bar item that's essentially the
    // physical top of the screen, so once "Show Notch Items" made the menu
    // one row taller, that top row landed in the sliver above the visible
    // screen and AppKit showed its standard "content doesn't fit here"
    // scroll-indicator caret instead of rendering it - hovering over the
    // indicator scrolled the whole menu into view, which is what looked
    // like the item "appearing on hover". Anchoring at the button's BOTTOM
    // edge instead (y: 0, not bounds.maxY) keeps the menu entirely within
    // on-screen space, growing downward from below the button.
    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = getContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }
    
    @objc func showHideSeparatorsAndAlwayHideArea() {
        Preferences.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()
        
        if self.isCollapsed {self.expandMenubar()}
    }
    
    private func showSeparators() {
        Preferences.areSeparatorsHidden = false
        
        if !self.isCollapsed {
            menuBarEngine.expand()
        }
        menuBarEngine.updateAlwaysHiddenSection(enabled: Preferences.alwaysHiddenSectionEnabled, separatorHidden: false)
    }
    
    private func hideSeparators() {
        guard self.isBtnAlwaysHiddenValidPosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            menuBarEngine.expand()
        }
        menuBarEngine.updateAlwaysHiddenSection(enabled: Preferences.alwaysHiddenSectionEnabled, separatorHidden: true)
    }
    
    func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        // Without Accessibility the collapse below cannot hide anything; show
        // the preferences, which explain what is missing, rather than no-op.
        if !isCollapsed && Util.isAccessibilityPermissionMissing {
            Util.showPrefWindow()
        }
        if isSeparateHiddenItemsBarVisible {
            collapseMenuBar()
        } else if isCollapsed && usesSeparateHiddenItemsBar {
            expandHiddenItemsBar()
        } else {
            isCollapsed ? expandMenubar() : collapseMenuBar()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }

    func prepareForItemManagement(completion: @escaping (MenuBarManagementLayout) -> Void) {
        expandMenubar(force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let layout = self?.currentManagementLayout() else { return }
            completion(layout)
        }
    }

    // Where the section boundaries are right now, without expanding. Moving an
    // item across them shifts Tuckaway's own items, so movers re-read this.
    func currentManagementLayout() -> MenuBarManagementLayout? {
        guard let expandCollapseFrame = btnExpandCollapse.button?.window?.frame else { return nil }
        let separatorFrame = MenuBarEngineFactory.usesNativeVisibility
            ? expandCollapseFrame
            : btnSeparate.button?.window?.frame
        guard let separatorFrame else { return nil }
        return MenuBarManagementLayout(separatorFrame: separatorFrame, expandCollapseFrame: expandCollapseFrame)
    }
    
    private func collapseMenuBar() {
        recollapseWorkItem?.cancel()
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        guard menuBarEngine.isArrangementValid && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }

        menuBarEngine.collapse { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .collapsed:
                self.didCollapseMenuBar()
            case .unavailable:
                self.didFailToCollapseMenuBar()
            }
        }
    }

    // Nothing was hidden (the engine cannot hide on this system, or is waiting for
    // a permission), so show the bar as expanded, and restore the activation
    // policy in case the UI had already switched to collapsed.
    private func didFailToCollapseMenuBar() {
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func didCollapseMenuBar() {
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
        rescueArrowIfSwallowed()
        applyExternalDisplayPreference()
    }

    // If collapsing hides the only control that can reopen the bar, undo it,
    // repair the saved order, and rebuild the two items. Cap retries to avoid a
    // collapse/rescue loop when macOS refuses the repaired positions.
    private func rescueArrowIfSwallowed() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCollapsed else { return }
            guard let arrowFrame = self.btnExpandCollapse.button?.window?.frame,
                  arrowFrame.origin != .zero else { return }
            guard !NSScreen.screens.contains(where: { $0.frame.intersects(arrowFrame) }) else { return }
            guard self.arrowRescueCount < 2 else {
                self.expandMenubar()
                return
            }
            self.arrowRescueCount += 1
            self.expandMenubar()
            StatusItemPositions.pullArrowInside()
            self.rebuildStatusItems()
        }
    }

    private func rebuildStatusItems() {
        NSStatusBar.system.removeStatusItem(btnExpandCollapse)
        NSStatusBar.system.removeStatusItem(btnSeparate)
        btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        btnSeparate = NSStatusBar.system.statusItem(withLength: 1)
        setupUI()
        restoreRemovedStatusItems()
        if MenuBarEngineFactory.usesNativeVisibility {
            btnSeparate.isVisible = false
        }
    }

    private func expandMenubar(force: Bool = false) {
        recollapseWorkItem?.cancel()
        guard self.isCollapsed || force else {return}
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        menuBarEngine.expand()
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        autoCollapseIfNeeded()
        
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            
        }
    }
    
    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {return}
        guard !didExpandForExternalDisplay else { return }
        guard !isCollapsed || isSeparateHiddenItemsBarVisible else { return }

        startTimerToAutoHide()
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            guard let self = self, Preferences.isAutoHide else { return }
            // Don't yank the bar shut mid-interaction. Preferences only needs the
            // same deferral when full-menu-bar activation could dismiss it (#170).
            if ExpandCollapseActionResolver.shouldDeferAutoCollapse(
                isMouseInMenuBar: self.isMouseInMenuBar,
                isMouseButtonDown: self.isMouseButtonDown,
                isPreferencesVisible: self.isPreferencesWindowVisible,
                usesFullMenuBar: Preferences.useFullStatusBarOnExpandEnabled
            ) {
                self.startTimerToAutoHide()
            } else {
                self.collapseMenuBar()
            }
        }
    }
    
    // Built fresh on every call (see showContextMenu(from:)), so every field
    // below reflects state as of THIS presentation - no separate "patch the
    // title after the fact" step is needed for the auto-collapse item.
    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()

        // Notch overflow menu item (only on notch Macs, and only when enabled)
        if NotchOverflowController.hasNotch && Preferences.notchOverflowEnabled {
            let overflowItem = NSMenuItem(title: "Show Notch Items".localized, action: #selector(showNotchOverflow), keyEquivalent: "")
            overflowItem.target = self
            menu.addItem(overflowItem)
            menu.addItem(NSMenuItem.separator())
        }

        if Preferences.didShowMacOS27HideUnavailableNotice && !MenuBarEngineFactory.usesNativeVisibility {
            let noticeItem = NSMenuItem(title: "Hiding unavailable on macOS 27 - Learn more".localized, action: #selector(openMacOS27Notice), keyEquivalent: "")
            noticeItem.target = self
            menu.addItem(noticeItem)
            menu.addItem(NSMenuItem.separator())
        }

        let toggleAutoHideItem = NSMenuItem(title: "Auto-collapse".localized, action: #selector(toggleAutoHide), keyEquivalent: "t")
        toggleAutoHideItem.state = Preferences.isAutoHide ? .on : .off
        toggleAutoHideItem.target = self
        menu.addItem(toggleAutoHideItem)

        let separatorTitle = Preferences.areSeparatorsHidden ? "Show separators" : "Hide separators"
        let separatorItem = NSMenuItem(title: separatorTitle.localized, action: #selector(showHideSeparatorsAndAlwayHideArea), keyEquivalent: "s")
        separatorItem.target = self
        menu.addItem(separatorItem)

        menu.addItem(NSMenuItem.separator())

        let itemsItem = NSMenuItem(title: "Manage Menu Bar Items…".localized, action: #selector(openMenuBarItemManager), keyEquivalent: "")
        itemsItem.target = self
        menu.addItem(itemsItem)

        if Updater.isSupported {
            let updateItem = NSMenuItem(title: "Check for Updates…".localized, action: #selector(Updater.checkForUpdates), keyEquivalent: "")
            updateItem.target = Updater.shared
            menu.addItem(updateItem)
        }

        let prefItem = NSMenuItem(title: "Settings…".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Tuckaway".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc func updateAutoHide() {
        updateConfigurationDragMonitor()
        updateHoverMonitor()
        updateEmptyMenuBarMonitor()
        if !usesSeparateHiddenItemsBar {
            hiddenItemsCaptureShieldController.hide()
            hiddenItemsBarController.hide()
            hiddenItemsSeparatorOverlayController.hide()
            updateExpandIcon()
        }
        applyExternalDisplayPreference()
        autoCollapseIfNeeded()
    }

    @objc private func updateExpandIcon() {
        btnExpandCollapse.button?.image = isCollapsed ? Assets.expandImage : Assets.collapseImage
    }

    @objc private func handleLegacyHideUnavailable() {
        didFailToCollapseMenuBar()
        timer?.invalidate()
        hoverDwellTimer?.invalidate()
    }

    @objc private func openMacOS27Notice() {
        guard let url = URL(string: "https://github.com/Bruno-Alumn/Tuckaway/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        PreferencesWindowController.shared.show(tab: .general)
    }

    @objc func openMenuBarItemManager() {
        PreferencesWindowController.shared.show(tab: .items)
    }

    @objc func showNotchOverflow() {
        notchOverflowController.showOverflowMenuFromSeparator(near: btnExpandCollapse)
    }
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}


//MARK: - Configuration drag support
extension StatusBarController {
    // Only the separate hidden-items bar needs to see drags, and this monitor
    // sees every left drag in every app, so install it only while that's on.
    // Global monitors already run on the main thread.
    private func updateConfigurationDragMonitor() {
        if usesSeparateHiddenItemsBar {
            guard configurationDragMonitor == nil else { return }
            configurationDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.handleConfigurationDragEvent(event)
            }
        } else if let configurationDragMonitor {
            NSEvent.removeMonitor(configurationDragMonitor)
            self.configurationDragMonitor = nil
            isTemporarilyExpandedForConfigurationDrag = false
        }
    }

    private func handleConfigurationDragEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            guard event.modifierFlags.contains(.command) else { return }
            temporarilyExpandForConfigurationDragIfNeeded()
        case .leftMouseUp:
            collapseAfterConfigurationDragIfNeeded()
        default:
            break
        }
    }

    private func temporarilyExpandForConfigurationDragIfNeeded() {
        guard usesSeparateHiddenItemsBar,
              !Preferences.areSeparatorsHidden,
              isCollapsed else { return }
        configurationDragCollapseWorkItem?.cancel()
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        menuBarEngine.expand()
        isTemporarilyExpandedForConfigurationDrag = true
        btnExpandCollapse.button?.image = Assets.collapseImage
    }

    private func collapseAfterConfigurationDragIfNeeded() {
        guard isTemporarilyExpandedForConfigurationDrag else { return }
        configurationDragCollapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isTemporarilyExpandedForConfigurationDrag = false
            self.collapseMenuBar()
        }
        configurationDragCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }
}

//MARK: - Separate hidden items bar
extension StatusBarController {
    private enum SeparateBarTiming {
        static let shieldSettleDelay: DispatchTimeInterval = .milliseconds(40)
        static let captureDelay: DispatchTimeInterval = .milliseconds(80)
        static let showDelayAfterCollapse: DispatchTimeInterval = .milliseconds(160)
    }

    private func expandHiddenItemsBar() {
        guard isCollapsed else { return }
        guard menuBarEngine.isArrangementValid else {
            restoreInlineMenuBarAfterInvalidSeparatePosition()
            return
        }
        guard canCaptureScreenForSeparatePanel() else {
            expandMenubar()
            return
        }
        guard let geometry = currentExpandCollapseGeometry() else { return }

        timer?.invalidate()
        hiddenItemsCaptureShieldController.show(
            on: geometry.screen,
            near: geometry.frame,
            covering: btnSeparate.button?.window?.frame
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + SeparateBarTiming.shieldSettleDelay) { [weak self] in
            guard let self = self else { return }
            guard self.usesSeparateHiddenItemsBar else {
                self.restoreInlineMenuBarAfterInvalidSeparatePosition()
                return
            }
            self.menuBarEngine.expand()
            self.btnExpandCollapse.button?.image = Assets.collapseImage

            DispatchQueue.main.asyncAfter(deadline: .now() + SeparateBarTiming.captureDelay) { [weak self] in
                guard let self = self else { return }
                guard self.usesSeparateHiddenItemsBar,
                      let capture = self.captureExpandedHiddenItems() else {
                    self.restoreInlineMenuBarAfterInvalidSeparatePosition()
                    return
                }

                self.menuBarEngine.collapse { result in
                    guard case .collapsed = result else {
                        self.restoreInlineMenuBarAfterInvalidSeparatePosition()
                        return
                    }
                    if Preferences.useFullStatusBarOnExpandEnabled {
                        NSApp.setActivationPolicy(.accessory)
                        NSApp.deactivate()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + SeparateBarTiming.showDelayAfterCollapse) { [weak self] in
                        guard let self = self else { return }
                        self.hiddenItemsCaptureShieldController.hide()
                        guard self.usesSeparateHiddenItemsBar && self.menuBarEngine.isArrangementValid else {
                            self.restoreInlineMenuBarAfterInvalidSeparatePosition()
                            return
                        }
                        let coveredCapture = self.captureByCoveringItemsStillVisibleInMenuBar(capture)
                        self.hiddenItemsBarController.show(capture: coveredCapture) { [weak self] sourceX in
                            self?.activateHiddenItem(atSourceX: sourceX, from: coveredCapture)
                        }
                        self.hiddenItemsSeparatorOverlayController.show(
                            frame: coveredCapture.menuBarOverlayFrame,
                            separatorFrame: coveredCapture.separatorFrame,
                            prefersDarkBackground: coveredCapture.prefersDarkBackground
                        )
                        self.btnExpandCollapse.button?.image = Assets.collapseImage
                        self.autoCollapseIfNeeded()
                    }
                }
            }
        }
    }

    private func canCaptureScreenForSeparatePanel() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func restoreInlineMenuBarAfterInvalidSeparatePosition() {
        timer?.invalidate()
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        menuBarEngine.expand()
        btnExpandCollapse.button?.image = Assets.collapseImage
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func captureExpandedHiddenItems() -> HiddenItemsBarCapture? {
        guard let windowList = menuBarWindowList() else { return nil }
        for screen in preferredCaptureScreens() {
            guard let separatorQuartzRect = statusItemQuartzRect(named: "hiddenbar_separate", statusItem: btnSeparate, from: windowList, on: screen),
                  let expandCollapseQuartzRect = statusItemQuartzRect(named: "hiddenbar_expandcollapse", statusItem: btnExpandCollapse, from: windowList, on: screen)
            else { continue }
            let items = captureVisibleHiddenSectionItems(
                from: windowList,
                separatorQuartzRect: separatorQuartzRect,
                expandCollapseQuartzRect: expandCollapseQuartzRect,
                on: screen
            )
            if !items.isEmpty {
                let separatorFrame = appKitRectFromQuartzRect(separatorQuartzRect, on: screen)
                return HiddenItemsBarCapture(
                    items: items,
                    screen: screen,
                    separatorFrame: separatorFrame,
                    menuBarOverlayFrame: menuBarOverlayFrame(for: separatorFrame, covering: [], on: screen),
                    prefersDarkBackground: prefersDarkBackground(for: items)
                )
            }
        }
        return nil
    }

    private func captureVisibleHiddenSectionItems(from windowList: [[String: Any]], separatorQuartzRect: CGRect, expandCollapseQuartzRect: CGRect, on screen: NSScreen) -> [HiddenItemsBarItem] {
        let capturedItems = windowList.compactMap { info -> (item: HiddenItemsBarItem, quartzRect: CGRect)? in
            guard let windowNumber = info[kCGWindowNumber as String] as? Int,
                  let quartzRect = visibleMenuBarItemQuartzRect(from: info, on: screen),
                  let image = CGWindowListCreateImage(
                    .null,
                    [.optionIncludingWindow],
                    CGWindowID(windowNumber),
                    [.boundsIgnoreFraming, .bestResolution]
                  )
            else { return nil }
            let appKitRect = appKitRectFromQuartzRect(quartzRect, on: screen)
            return (
                item: HiddenItemsBarItem(
                    image: NSImage(cgImage: image, size: appKitRect.size),
                    sourceRect: appKitRect,
                    windowNumber: windowNumber
                ),
                quartzRect: quartzRect
            )
        }
        .sorted { $0.item.sourceRect.minX < $1.item.sourceRect.minX }
        return capturedItems.filter {
            hiddenSectionCandidateLocation(
                $0.quartzRect,
                separatorQuartzRect: separatorQuartzRect,
                expandCollapseQuartzRect: expandCollapseQuartzRect
            ) != nil
        }.map { $0.item }
    }

    private func captureByCoveringItemsStillVisibleInMenuBar(_ capture: HiddenItemsBarCapture) -> HiddenItemsBarCapture {
        guard let windowList = menuBarWindowList() else { return capture }
        let visibleRectsByWindowNumber = Dictionary(uniqueKeysWithValues: windowList.compactMap { info -> (Int, CGRect)? in
            guard let windowNumber = info[kCGWindowNumber as String] as? Int,
                  let quartzRect = visibleMenuBarItemQuartzRect(from: info, on: capture.screen)
            else { return nil }
            return (windowNumber, appKitRectFromQuartzRect(quartzRect, on: capture.screen))
        })
        let visibleCapturedRects = capture.items.compactMap { visibleRectsByWindowNumber[$0.windowNumber] }
        guard !visibleCapturedRects.isEmpty else { return capture }
        return HiddenItemsBarCapture(
            items: capture.items,
            screen: capture.screen,
            separatorFrame: capture.separatorFrame,
            menuBarOverlayFrame: menuBarOverlayFrame(
                for: capture.separatorFrame,
                covering: visibleCapturedRects,
                on: capture.screen
            ),
            prefersDarkBackground: capture.prefersDarkBackground
        )
    }

    private func prefersDarkBackground(for items: [HiddenItemsBarItem]) -> Bool {
        var luminanceTotal: CGFloat = 0
        var sampleCount: CGFloat = 0
        for item in items {
            guard let cgImage = item.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            let xStep = max(1, bitmap.pixelsWide / 8)
            let yStep = max(1, bitmap.pixelsHigh / 8)
            stride(from: 0, to: bitmap.pixelsWide, by: xStep).forEach { x in
                stride(from: 0, to: bitmap.pixelsHigh, by: yStep).forEach { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                          color.alphaComponent > 0.2 else { return }
                    luminanceTotal += 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                    sampleCount += 1
                }
            }
        }
        guard sampleCount > 0 else { return false }
        return luminanceTotal / sampleCount > 0.55
    }

    private func menuBarOverlayFrame(for separatorFrame: CGRect, covering itemFrames: [CGRect], on screen: NSScreen) -> CGRect {
        let menuBarHeight = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
        let minX = max(screen.frame.minX, itemFrames.reduce(separatorFrame.minX) { min($0, $1.minX) })
        let maxX = min(screen.frame.maxX, itemFrames.reduce(separatorFrame.maxX) { max($0, $1.maxX) })
        return CGRect(
            x: minX,
            y: screen.frame.maxY - menuBarHeight,
            width: max(20, maxX - minX),
            height: menuBarHeight
        )
    }

    private func menuBarWindowList() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    }

    private func visibleMenuBarItemQuartzRect(from info: [String: Any], on screen: NSScreen) -> CGRect? {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let screenQuartzRect = quartzRectFromAppKitRect(screen.frame)
        let menuBarHeight = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
        let maxMenuBarQuartzY = screenQuartzRect.minY + menuBarHeight + 6
        let appBundleIdentifier = Bundle.main.bundleIdentifier
        guard (info[kCGWindowOwnerPID as String] as? Int32) != currentProcessID,
              !isHiddenBarStatusWindow(info, appBundleIdentifier: appBundleIdentifier),
              let layer = info[kCGWindowLayer as String] as? Int,
              layer == 25,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let quartzRect = rectFromWindowBounds(bounds),
              quartzRect.intersects(screenQuartzRect),
              quartzRect.minY >= screenQuartzRect.minY - 1,
              quartzRect.minY <= maxMenuBarQuartzY,
              quartzRect.height > 4,
              quartzRect.width > 4
        else { return nil }
        return quartzRect
    }

    private enum HiddenSectionCandidateLocation {
        case hiddenSection
    }

    private func hiddenSectionCandidateLocation(_ quartzRect: CGRect, separatorQuartzRect: CGRect, expandCollapseQuartzRect: CGRect) -> HiddenSectionCandidateLocation? {
        if expandCollapseQuartzRect.minX >= separatorQuartzRect.minX {
            return quartzRect.maxX <= separatorQuartzRect.minX + 1 ? .hiddenSection : nil
        }
        return quartzRect.minX >= separatorQuartzRect.maxX - 1 ? .hiddenSection : nil
    }

    private func preferredCaptureScreens() -> [NSScreen] {
        let preferred = btnExpandCollapse.button?.window?.screen ?? activeStatusItemScreen ?? NSScreen.main
        guard let first = preferred else { return NSScreen.screens }
        return [first] + NSScreen.screens.filter { $0 !== first }
    }

    private func currentExpandCollapseGeometry() -> (frame: CGRect, screen: NSScreen)? {
        if let frame = btnExpandCollapse.button?.window?.frame,
           let screen = btnExpandCollapse.button?.window?.screen {
            return (frame, screen)
        }
        guard let frame = activeExpandCollapseFrame else { return nil }
        let screen = activeStatusItemScreen
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let resolvedScreen = screen else { return nil }
        return (frame, resolvedScreen)
    }

    private func statusItemQuartzRect(named name: String, statusItem: NSStatusItem, from windowList: [[String: Any]], on screen: NSScreen) -> CGRect? {
        let screenQuartzRect = quartzRectFromAppKitRect(screen.frame)
        let menuBarQuartzRect = quartzMenuBarRect(on: screen)
        let appBundleIdentifier = Bundle.main.bundleIdentifier
        let namedWindows = windowList.compactMap { info -> CGRect? in
            guard (info[kCGWindowName as String] as? String) == name,
                  let quartzRect = statusItemWindowQuartzRect(from: info, screenQuartzRect: screenQuartzRect, menuBarQuartzRect: menuBarQuartzRect)
            else { return nil }
            return quartzRect
        }
        if let namedWindow = namedWindows.sorted(by: { $0.minX < $1.minX }).first {
            return namedWindow
        }
        guard let expectedFrame = statusItem.button?.window?.frame else { return nil }
        let expectedQuartzRect = quartzRectFromAppKitRect(expectedFrame)
        let bundleWindows = windowList.compactMap { info -> CGRect? in
            guard let title = info[kCGWindowName as String] as? String,
                  title == appBundleIdentifier || title.hasPrefix("hiddenbar_"),
                  let quartzRect = statusItemWindowQuartzRect(from: info, screenQuartzRect: screenQuartzRect, menuBarQuartzRect: menuBarQuartzRect)
            else { return nil }
            return quartzRect
        }
        return bundleWindows.sorted {
            statusItemMatchScore($0, expectedQuartzRect: expectedQuartzRect) < statusItemMatchScore($1, expectedQuartzRect: expectedQuartzRect)
        }.first
    }

    private func statusItemWindowQuartzRect(from info: [String: Any], screenQuartzRect: CGRect, menuBarQuartzRect: CGRect) -> CGRect? {
        guard let layer = info[kCGWindowLayer as String] as? Int,
              layer == 25,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let quartzRect = rectFromWindowBounds(bounds),
              quartzRect.intersects(screenQuartzRect),
              quartzRect.intersects(menuBarQuartzRect)
        else { return nil }
        return quartzRect
    }

    private func statusItemMatchScore(_ quartzRect: CGRect, expectedQuartzRect: CGRect) -> CGFloat {
        abs(quartzRect.midX - expectedQuartzRect.midX)
            + abs(quartzRect.midY - expectedQuartzRect.midY)
            + abs(quartzRect.width - expectedQuartzRect.width)
            + abs(quartzRect.height - expectedQuartzRect.height)
    }

    private func quartzMenuBarRect(on screen: NSScreen) -> CGRect {
        let screenQuartzRect = quartzRectFromAppKitRect(screen.frame)
        let menuBarHeight = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
        return CGRect(
            x: screenQuartzRect.minX,
            y: screenQuartzRect.minY - 2,
            width: screen.frame.width,
            height: menuBarHeight + 4
        )
    }

    private func isHiddenBarStatusWindow(_ info: [String: Any], appBundleIdentifier: String?) -> Bool {
        let title = info[kCGWindowName as String] as? String
        return title == appBundleIdentifier || title?.hasPrefix("hiddenbar_") == true
    }

    private func rectFromWindowBounds(_ bounds: [String: Any]) -> CGRect? {
        guard let x = bounds["X"] as? NSNumber,
              let y = bounds["Y"] as? NSNumber,
              let width = bounds["Width"] as? NSNumber,
              let height = bounds["Height"] as? NSNumber
        else { return nil }
        return CGRect(
            x: CGFloat(truncating: x),
            y: CGFloat(truncating: y),
            width: CGFloat(truncating: width),
            height: CGFloat(truncating: height)
        )
    }

    // Quartz measures y down from the top of the primary screen (the one with
    // the origin), not from NSScreen.main, which is whichever has key focus.
    private static var primaryScreenMaxY: CGFloat? {
        NSScreen.screens.first?.frame.maxY
    }

    private func appKitRectFromQuartzRect(_ quartzRect: CGRect, on screen: NSScreen) -> CGRect {
        let referenceMaxY = Self.primaryScreenMaxY ?? screen.frame.maxY
        return CGRect(
            x: quartzRect.minX,
            y: referenceMaxY - quartzRect.maxY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }

    private func quartzRectFromAppKitRect(_ appKitRect: CGRect) -> CGRect {
        let referenceMaxY = Self.primaryScreenMaxY ?? appKitRect.maxY
        return CGRect(
            x: appKitRect.minX,
            y: referenceMaxY - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    private func activateHiddenItem(atSourceX sourceX: CGFloat, from capture: HiddenItemsBarCapture) {
        guard canForwardClicksToMenuBarItems() else { return }
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        menuBarEngine.expand()
        btnExpandCollapse.button?.image = Assets.collapseImage
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            let clickPoint = CGPoint(
                x: sourceX,
                y: capture.items.first(where: { $0.sourceRect.minX <= sourceX && sourceX <= $0.sourceRect.maxX })?.sourceRect.midY ?? capture.screen.frame.maxY - 12
            )
            self.postClick(at: clickPoint)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.collapseMenuBar()
            }
        }
    }

    private func postClick(at appKitPoint: CGPoint) {
        let referenceMaxY = Self.primaryScreenMaxY ?? appKitPoint.y
        let eventPoint = CGPoint(x: appKitPoint.x, y: referenceMaxY - appKitPoint.y)
        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: eventPoint, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: eventPoint, mouseButton: .left)
        else { return }
        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
    }

    private func canForwardClicksToMenuBarItems() -> Bool {
        AXIsProcessTrusted()
    }
}

//MARK: - Alway hide feature
extension StatusBarController {
    private func setupAlwayHideStatusBar() {
        NotificationCenter.default.addObserver(self, selector: #selector(alwaysHiddenSectionToggled), name: .alwayHideToggle, object: nil)
        toggleStatusBarIfNeeded()
    }

    // Turning the section on shows its separator so it can be ⌘-dragged into
    // place; the saved "hide separators" state is reset to match, or the next
    // Option-click would only flip the preference and appear to do nothing.
    @objc private func alwaysHiddenSectionToggled() {
        if Preferences.alwaysHiddenSectionEnabled {
            Preferences.areSeparatorsHidden = false
        }
        toggleStatusBarIfNeeded()
    }

    private func toggleStatusBarIfNeeded() {
        if Preferences.alwaysHiddenSectionEnabled {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = NSStatusBar.system.statusItem(withLength: 0)
            if let button = btnAlwaysHidden?.button {
                button.image = self.imgIconLine
                button.appearsDisabled = true
            }
            self.btnAlwaysHidden?.autosaveName = "hiddenbar_terminate"
            self.btnAlwaysHidden?.isVisible = true
            // Last, so the engine decides whether the new item stays in the bar.
            menuBarEngine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        } else {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = nil
        }
    }
}
