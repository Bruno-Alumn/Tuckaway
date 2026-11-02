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
    private let hiddenItemsFreezeController = HiddenItemsBarFreezeController()
    // Bumped by every expand and collapse, so a macOS 27 capture or click that
    // is still in flight doesn't act on a bar the user has since changed.
    private var nativeHiddenItemsRequest = 0
    private var nativeMenuWatchTimer: Timer?
    private var hoverRowLeaveTimer: Timer?
    private let newAppPrompt = NewMenuBarAppPromptController()
    private let hiddenIconSearch = HiddenIconSearchController()
    // New apps waiting to be asked about, in order; the first is on screen.
    private var newAppQueue: [String] = []
    private var activeExpandCollapseFrame: CGRect?
    private var activeStatusItemScreen: NSScreen?
    private var didExpandForExternalDisplay = false
    private var hasCollapsedSinceLaunch = false
    private var appliedExpandWhenExternalDisplay = Preferences.expandWhenExternalDisplayConnected
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
        return Preferences.showHiddenItemsInSeparateBar
    }

    private var isSeparateHiddenItemsBarVisible: Bool {
        hiddenItemsBarController.isVisible
    }

    private var isMenuBarGeometryReady: Bool {
        guard let arrowOrigin = btnExpandCollapse.button?.window?.frame.origin else { return false }
        guard arrowOrigin != .zero else { return false }
        if MenuBarEngineFactory.usesNativeVisibility { return true }
        guard let separatorOrigin = btnSeparate.button?.window?.frame.origin else { return false }
        return separatorOrigin != .zero
    }
    
    private var isBtnAlwaysHiddenValidPosition: Bool {
        if !Preferences.alwaysHiddenSectionEnabled { return true }
        return menuBarEngine.isAlwaysHiddenSeparatorPlaced
    }
    
    private var isToggle = false
    private var isManagingItems = false
    private var arrowRescueCount = 0

    private var hoverMonitor: Any?
    private var hoverDwellTimer: Timer?
    private var emptyMenuBarMonitor: Any?
    // Global monitors don't see clicks sent to Tuckaway itself, which is active
    // with "use the full menu bar" or while Settings is open.
    private var emptyMenuBarLocalMonitor: Any?

    // True while the pointer sits in any screen's menubar band: the strip above
    // visibleFrame. With "Automatically hide and show the menu bar" that strip
    // is empty even while the bar is shown, so then it's the menu bar's (or the
    // notch's) height, but only while the menu bar is actually visible: on a
    // full-screen Space the top of the app isn't the menu bar.
    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            var height = screen.frame.maxY - screen.visibleFrame.maxY
            if height < 1 && NSMenu.menuBarVisible() {
                height = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            }
            return height >= 1 && mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.frame.maxY - height && mouse.y <= screen.frame.maxY
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
        setupNewAppPrompts()
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
                // Menu Bar Items keeps the bar open; it collapses when it closes.
                guard !self.isManagingItems else { return }
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
        if let emptyMenuBarLocalMonitor {
            NSEvent.removeMonitor(emptyMenuBarLocalMonitor)
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
                if self.isCollapsed && self.isMouseInMenuBar && !self.isMouseButtonDown && !self.isPresenting {
                    if self.usesSeparateHiddenItemsBar {
                        self.openHiddenItemsBarOnHover()
                    } else {
                        self.expandMenubar()
                    }
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
            emptyMenuBarLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                if let self, self.isEmptyMenuBarClick() {
                    self.expandCollapseIfNeeded()
                }
                return event
            }
        } else if let emptyMenuBarMonitor {
            NSEvent.removeMonitor(emptyMenuBarMonitor)
            self.emptyMenuBarMonitor = nil
            if let emptyMenuBarLocalMonitor {
                NSEvent.removeMonitor(emptyMenuBarLocalMonitor)
                self.emptyMenuBarLocalMonitor = nil
            }
        }
    }

    private func isEmptyMenuBarClick() -> Bool {
        guard isMouseInMenuBar,
              let primaryScreenTop = NSScreen.screens.first?.frame.maxY,
              !Util.isAccessibilityPermissionMissing else { return false }
        let mouse = NSEvent.mouseLocation
        let point = ExpandCollapseActionResolver.accessibilityPoint(forAppKitPoint: mouse, primaryScreenTop: primaryScreenTop)
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
        let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        // Tuckaway coming forward (Settings) keeps the previous app's icon.
        if activated?.bundleIdentifier != Bundle.main.bundleIdentifier {
            updateActiveAppIcon(activated)
        }
        // Many menu-bar apps activate themselves when their icon is clicked; the
        // pointer is still in the menu bar then, and collapsing would hide the
        // icon whose menu or popover just opened.
        guard Preferences.autoCollapseOnFocusChange, !isCollapsed, !isMouseButtonDown, !isMouseInMenuBar, !isManagingItems,
              !didExpandForExternalDisplay,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        collapseMenuBar()
    }

    private func invalidateNativeLayoutAfterEnvironmentChange() {
        let wasCollapsed = isCollapsed
        // A capture or click in flight would wait on an answer that the
        // engine now drops, leaving the still image over a live bar.
        endNativeHiddenItemsRequest()
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
            button.toolTip = Constant.appName
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
        if isPresenting {
            // The arrow is the one icon left, so it ends presentation mode.
            togglePresentationMode()
        } else if isSeparateHiddenItemsBarVisible || hiddenSectionPeeker?.isPeeking == true {
            collapseMenuBar()
        } else if isCollapsed && usesSeparateHiddenItemsBar {
            showHiddenItemsBar()
        } else {
            isCollapsed ? expandMenubar() : collapseMenuBar()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }

    // While Menu Bar Items is open, the always-hidden section is shown too, so
    // its icons can be listed and moved; the saved "hide separators" choice
    // comes back in endItemManagement().
    func prepareForItemManagement(completion: @escaping (MenuBarManagementLayout) -> Void) {
        isManagingItems = true
        expandMenubar(force: true)
        if Preferences.alwaysHiddenSectionEnabled {
            menuBarEngine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let layout = self?.currentManagementLayout() else { return }
            completion(layout)
        }
    }

    func endItemManagement() {
        guard isManagingItems else { return }
        isManagingItems = false
        if Preferences.alwaysHiddenSectionEnabled {
            menuBarEngine.updateAlwaysHiddenSection(enabled: true, separatorHidden: Preferences.areSeparatorsHidden)
        }
        autoCollapseIfNeeded()
    }

    // Where the section boundaries are right now, without expanding. Moving an
    // item across them shifts Tuckaway's own items, so movers re-read this.
    func currentManagementLayout() -> MenuBarManagementLayout? {
        guard let expandCollapseFrame = btnExpandCollapse.button?.window?.frame else { return nil }
        let separatorFrame = MenuBarEngineFactory.usesNativeVisibility
            ? expandCollapseFrame
            : btnSeparate.button?.window?.frame
        guard let separatorFrame else { return nil }
        // The always-hidden separator has no width while it is out of the bar.
        let alwaysHiddenFrame = (btnAlwaysHidden?.button?.window?.frame).flatMap {
            Preferences.alwaysHiddenSectionEnabled && $0.width > 2 && $0.origin != .zero ? $0 : nil
        }
        return MenuBarManagementLayout(separatorFrame: separatorFrame, expandCollapseFrame: expandCollapseFrame,
                                       alwaysHiddenFrame: alwaysHiddenFrame)
    }
    
    private func collapseMenuBar() {
        recollapseWorkItem?.cancel()
        hiddenItemsCaptureShieldController.hide()
        hiddenItemsBarController.hide()
        hiddenItemsSeparatorOverlayController.hide()
        endNativeHiddenItemsRequest()
        guard menuBarEngine.isArrangementValid && !self.isCollapsed else {
            // The separate bar shows the expanded arrow while it is open.
            updateExpandIcon()
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
        // The collapse at launch is where "expand with an external display"
        // first applies. After that a collapse is the user's and wins until
        // the displays change; re-applying it here undid every collapse.
        if hasCollapsedSinceLaunch {
            didExpandForExternalDisplay = false
        } else {
            hasCollapsedSinceLaunch = true
            applyExternalDisplayPreference()
        }
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
        endNativeHiddenItemsRequest()
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
            // Collapsing mid-move would hide the icons being moved.
            if self.isManagingItems { return self.startTimerToAutoHide() }
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

        if Self.supportsHiddenIconSearch {
            let findItem = NSMenuItem(title: "Find Hidden Icon…".localized, action: #selector(showHiddenIconSearch), keyEquivalent: "")
            findItem.target = self
            menu.addItem(findItem)
        }

        if Self.supportsPresentationMode {
            let presentationItem = NSMenuItem(title: "Presentation Mode".localized, action: #selector(togglePresentationMode), keyEquivalent: "")
            presentationItem.state = isPresenting ? .on : .off
            presentationItem.target = self
            menu.addItem(presentationItem)
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

    private func updateActiveAppIcon(_ app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        guard let shower = menuBarEngine as? ActiveAppShowing else { return }
        let bundle = app?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app?.bundleIdentifier
        shower.setActiveApp(Preferences.showActiveAppIcon ? bundle : nil)
    }

    @objc func updateAutoHide() {
        updateActiveAppIcon()
        updateConfigurationDragMonitor()
        updateHoverMonitor()
        updateEmptyMenuBarMonitor()
        if !usesSeparateHiddenItemsBar {
            hiddenItemsCaptureShieldController.hide()
            hiddenItemsBarController.hide()
            hiddenItemsSeparatorOverlayController.hide()
            updateExpandIcon()
        }
        // Any preference posts this; only a change to this one should expand,
        // or toggling something else would undo the user's collapse.
        if Preferences.expandWhenExternalDisplayConnected != appliedExpandWhenExternalDisplay {
            appliedExpandWhenExternalDisplay = Preferences.expandWhenExternalDisplayConnected
            applyExternalDisplayPreference()
        }
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
    // On macOS 27 a ⌘-drag works the same with or without that bar.
    // Global monitors already run on the main thread.
    private func updateConfigurationDragMonitor() {
        if usesSeparateHiddenItemsBar && !MenuBarEngineFactory.usesNativeVisibility {
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
            // Only a ⌘-drag in the menu bar rearranges icons; elsewhere it's
            // just a window or a selection.
            guard event.modifierFlags.contains(.command), isMouseInMenuBar else { return }
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
                        self.hiddenItemsBarController.show(capture: coveredCapture, menuProvider: { [weak self] in
                            self?.hiddenItemMenu(for: $0)
                        }) { [weak self] sourceX in
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
                    windowNumber: windowNumber,
                    name: info[kCGWindowOwnerName as String] as? String,
                    bundleIdentifier: (info[kCGWindowOwnerPID as String] as? pid_t)
                        .flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
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
        postClick(atQuartzPoint: CGPoint(x: appKitPoint.x, y: referenceMaxY - appKitPoint.y))
    }

    // Quartz and Accessibility share the top-left origin.
    private func postClick(atQuartzPoint eventPoint: CGPoint) {
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

//MARK: - Separate hidden items bar on macOS 27
extension StatusBarController {
    private var hiddenSectionPeeker: HiddenSectionPeeking? {
        menuBarEngine as? HiddenSectionPeeking
    }

    private enum NativeSeparateBarTiming {
        // How long macOS takes to lay out the bar after the restriction changes.
        static let reflowDelay: DispatchTimeInterval = .milliseconds(200)
        // How long a click waits for the app to open a menu before the icon is
        // hidden again, and how often it checks whether that menu is still open.
        static let menuOpenGrace: TimeInterval = 1.5
        static let menuPollInterval: TimeInterval = 0.25
    }

    private func endNativeHiddenItemsRequest() {
        nativeHiddenItemsRequest += 1
        nativeMenuWatchTimer?.invalidate()
        nativeMenuWatchTimer = nil
        hiddenItemsFreezeController.hide()
        hiddenSectionPeeker?.endPeek()
    }

    // macOS 27 draws status items into the menu bar, so the hidden icons are
    // captured from the bar itself: a still image of the bar covers them, the
    // hidden section shows behind it for a moment, and the capture leaves out
    // Tuckaway's windows. Anything missing falls back to expanding.
    private func showNativeHiddenItemsBar() {
        guard #available(macOS 14.0, *),
              let peeker = hiddenSectionPeeker,
              canCaptureScreenForSeparatePanel(),
              let arrowFrame = btnExpandCollapse.button?.window?.frame,
              let display = MenuBarDisplayInventory.current().first(where: { $0.appKitFrame.contains(CGPoint(x: arrowFrame.midX, y: arrowFrame.midY)) }),
              let screen = NSScreen.screens.first(where: { $0.frame == display.appKitFrame })
        else { return expandMenubar() }
        let menuBarHeight = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
        let hiddenItems = peeker.hiddenItems
            .filter { display.accessibilityFrame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .sorted { $0.frame.minX < $1.frame.minX }
        let frames = hiddenItems.map(\.frame)
        guard let strip = MenuBarStripGeometry.strip(covering: frames, menuBarHeight: menuBarHeight, on: display) else {
            return expandMenubar()
        }

        timer?.invalidate()
        nativeHiddenItemsRequest += 1
        let request = nativeHiddenItemsRequest
        let stripFrame = display.appKitRect(fromAccessibility: strip)
        MenuBarStripCapture.image(of: strip, on: display, excludingOwnWindows: false) { [weak self] still, _ in
            guard let self, request == self.nativeHiddenItemsRequest else { return }
            if let still {
                self.hiddenItemsFreezeController.show(still, frame: stripFrame)
                // The whole capture takes well under a second. If an answer
                // never comes, don't leave a picture over the live bar.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, request == self.nativeHiddenItemsRequest,
                          self.hiddenItemsFreezeController.isVisible else { return }
                    NSLog("SeparateBar: capture didn't finish; giving up")
                    self.endNativeHiddenItemsRequest()
                }
            }
            peeker.peekHiddenSection { [weak self] succeeded in
                guard let self, request == self.nativeHiddenItemsRequest else { return }
                guard succeeded else { return self.expandMenubar() }
                DispatchQueue.main.asyncAfter(deadline: .now() + NativeSeparateBarTiming.reflowDelay) { [weak self] in
                    guard let self, request == self.nativeHiddenItemsRequest else { return }
                    // Where the icons are now, not where the last full read saw them.
                    peeker.refreshHiddenItemFrames { [weak self] fresh in
                        guard let self, request == self.nativeHiddenItemsRequest else { return }
                        let hiddenItems = fresh
                            .filter { display.accessibilityFrame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                            .sorted { $0.frame.minX < $1.frame.minX }
                        let freshStrip = MenuBarStripGeometry.strip(covering: hiddenItems.map(\.frame), menuBarHeight: menuBarHeight, on: display) ?? strip
                        MenuBarStripCapture.image(of: freshStrip, on: display, excludingOwnWindows: true) { [weak self] image, scale in
                            guard let self, request == self.nativeHiddenItemsRequest else { return }
                            peeker.endPeek()
                            DispatchQueue.main.asyncAfter(deadline: .now() + NativeSeparateBarTiming.reflowDelay) { [weak self] in
                                guard let self, request == self.nativeHiddenItemsRequest else { return }
                                self.hiddenItemsFreezeController.hide()
                                guard let image,
                                      let capture = self.nativeHiddenItemsCapture(from: image, scale: scale, strip: freshStrip,
                                                                                  items: hiddenItems, display: display, screen: screen)
                                else { return self.expandMenubar() }
                                self.hiddenItemsBarController.show(capture: capture, menuProvider: { [weak self] in
                                    self?.hiddenItemMenu(for: $0)
                                }) { [weak self] sourceX in
                                    guard let item = capture.items.first(where: { $0.sourceRect.minX <= sourceX && sourceX <= $0.sourceRect.maxX }) else { return }
                                    self?.clickNativeHiddenItem(at: display.accessibilityRect(fromAppKit: item.sourceRect))
                                }
                                self.btnExpandCollapse.button?.image = Assets.collapseImage
                                self.autoCollapseIfNeeded()
                            }
                        }
                    }
                }
            }
        }
    }

    private func nativeHiddenItemsCapture(from image: CGImage, scale: CGFloat, strip: CGRect, items hiddenItems: [MenuBarInventoryItem],
                                          display: MenuBarDisplay, screen: NSScreen) -> HiddenItemsBarCapture? {
        let items = hiddenItems.enumerated().compactMap { index, hidden -> HiddenItemsBarItem? in
            guard let pixels = MenuBarStripGeometry.pixelRect(of: hidden.frame, in: strip, scale: scale),
                  let cropped = image.cropping(to: pixels) else { return nil }
            let sourceRect = display.appKitRect(fromAccessibility: hidden.frame)
            let appName = hidden.bundleIdentifier.flatMap {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.localizedName
            }
            let name = MenuBarItemNaming.displayName(appName: appName, title: hidden.title,
                                                     isSystemExtra: hidden.bundleIdentifier == MenuBarItemNaming.systemExtraOwner)
            return HiddenItemsBarItem(image: NSImage(cgImage: cropped, size: sourceRect.size),
                                      sourceRect: sourceRect, windowNumber: index,
                                      name: name, bundleIdentifier: hidden.bundleIdentifier)
        }
        guard !items.isEmpty, let first = hiddenItems.first?.frame else { return nil }
        // The bar at the first icon's left edge, at the icons' height: icons
        // leave their outermost column empty.
        let sliver = CGRect(x: first.minX, y: first.minY, width: 1 / scale, height: first.height)
        let background = MenuBarStripGeometry.pixelRect(of: sliver, in: strip, scale: scale)
            .flatMap { image.cropping(to: $0) }
        let color = NSBitmapImageRep(cgImage: image).colorAt(x: 0, y: image.height / 2)?.usingColorSpace(.sRGB)
        let luminance = color.map { 0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent } ?? 1
        return HiddenItemsBarCapture(items: items, screen: screen, separatorFrame: .zero, menuBarOverlayFrame: .zero,
                                     prefersDarkBackground: luminance < 0.5,
                                     backgroundImage: background.map { NSImage(cgImage: $0, size: CGSize(width: 1, height: first.height)) })
    }

    // Shows the hidden section again, clicks the real icon, and hides it once
    // the menu or window that click opened has closed.
    private func clickNativeHiddenItem(at frame: CGRect) {
        guard canForwardClicksToMenuBarItems(), let peeker = hiddenSectionPeeker else { return }
        hiddenItemsBarController.hide()
        updateExpandIcon()
        timer?.invalidate()
        nativeHiddenItemsRequest += 1
        let request = nativeHiddenItemsRequest
        let owner = ownerPID(ofMenuBarItemAt: frame)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let previous = peeker.hiddenItems
        let clicked = previous.first { $0.frame.contains(center) }
        peeker.peekHiddenSection { [weak self] succeeded in
            guard let self, request == self.nativeHiddenItemsRequest else { return }
            guard succeeded else { return self.expandMenubar() }
            DispatchQueue.main.asyncAfter(deadline: .now() + NativeSeparateBarTiming.reflowDelay) { [weak self] in
                guard let self, request == self.nativeHiddenItemsRequest else { return }
                // The icon may have shifted since the row was captured; click
                // where it is now.
                peeker.refreshHiddenItemFrames { [weak self] fresh in
                    guard let self, request == self.nativeHiddenItemsRequest else { return }
                    let target = clicked.flatMap { MenuBarStripGeometry.counterpart(of: $0, among: fresh, in: previous) }?.frame ?? frame
                    let windowsBefore = owner.map { self.onScreenWindowNumbers(ownedBy: $0) } ?? []
                    self.postClick(atQuartzPoint: CGPoint(x: target.midX, y: target.midY))
                    self.endPeekWhenMenuCloses(owner: owner, ignoring: windowsBefore, request: request)
                }
            }
        }
    }

    private func ownerPID(ofMenuBarItemAt frame: CGRect) -> pid_t? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let bundle = hiddenSectionPeeker?.hiddenItems.first(where: { $0.frame.contains(center) })?.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier
    }

    private func onScreenWindowNumbers(ownedBy pid: pid_t) -> Set<Int> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(windows.compactMap { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid ? info[kCGWindowNumber as String] as? Int : nil
        })
    }

    // Some apps keep a window on screen all the time, so only windows that
    // appeared after the click count as its menu.
    private func endPeekWhenMenuCloses(owner: pid_t?, ignoring windowsBefore: Set<Int>, request: Int) {
        let start = Date()
        var sawMenu = false
        nativeMenuWatchTimer?.invalidate()
        nativeMenuWatchTimer = Timer.scheduledTimer(withTimeInterval: NativeSeparateBarTiming.menuPollInterval, repeats: true) { [weak self] timer in
            guard let self, request == self.nativeHiddenItemsRequest else { return timer.invalidate() }
            let isMenuOpen = owner.map { !self.onScreenWindowNumbers(ownedBy: $0).subtracting(windowsBefore).isEmpty } ?? false
            sawMenu = sawMenu || isMenuOpen
            let waitedForMenu = Date().timeIntervalSince(start) > NativeSeparateBarTiming.menuOpenGrace
            guard !isMenuOpen && (sawMenu || waitedForMenu) else { return }
            timer.invalidate()
            self.nativeMenuWatchTimer = nil
            self.hiddenSectionPeeker?.endPeek()
        }
    }
}

//MARK: - Find Hidden Icon (macOS 27)
extension StatusBarController {
    // Opening an icon relies on showing the hidden section for a moment.
    static var supportsHiddenIconSearch: Bool {
        MenuBarEngineFactory.usesNativeVisibility
    }

    @objc func showHiddenIconSearch() {
        guard Self.supportsHiddenIconSearch, !isPresenting, let peeker = hiddenSectionPeeker,
              let arrowFrame = btnExpandCollapse.button?.window?.frame,
              let screen = btnExpandCollapse.button?.window?.screen else { return }
        if hiddenIconSearch.isVisible { return hiddenIconSearch.hide() }
        // Close the separate bar properly, including a capture still in flight.
        endNativeHiddenItemsRequest()
        let entries = peeker.hiddenItems.sorted { $0.frame.minX < $1.frame.minX }.map { item -> HiddenIconSearchController.Entry in
            let app = item.bundleIdentifier.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            let name = MenuBarItemNaming.displayName(appName: app?.localizedName, title: item.title,
                                                     isSystemExtra: item.bundleIdentifier == MenuBarItemNaming.systemExtraOwner)
            return HiddenIconSearchController.Entry(name: name ?? item.bundleIdentifier ?? "", icon: app?.icon, frame: item.frame)
        }
        hiddenItemsBarController.hide()
        updateExpandIcon()
        hiddenIconSearch.show(entries: entries, below: arrowFrame, on: screen) { [weak self] entry in
            self?.openHiddenIcon(at: entry.frame)
        }
    }

    // Collapsed, the icon is shown for the click and hidden again once its menu
    // closes; expanded, it is already there.
    private func openHiddenIcon(at frame: CGRect) {
        if isCollapsed {
            clickNativeHiddenItem(at: frame)
        } else if canForwardClicksToMenuBarItems() {
            postClick(atQuartzPoint: CGPoint(x: frame.midX, y: frame.midY))
        }
    }
}

//MARK: - Presentation mode (macOS 27)
extension StatusBarController {
    // Only the native engine can hide icons on the visible side.
    static var supportsPresentationMode: Bool {
        MenuBarEngineFactory.usesNativeVisibility
    }

    var isPresenting: Bool {
        (menuBarEngine as? PresentationModeProviding)?.isPresenting ?? false
    }

    // Hides every app's icon but the arrow, for screen sharing or recording.
    @objc func togglePresentationMode() {
        guard let presenter = menuBarEngine as? PresentationModeProviding else { return }
        let presenting = !presenter.isPresenting
        if presenting {
            timer?.invalidate()
            endNativeHiddenItemsRequest()
            hiddenItemsBarController.hide()
            newAppPrompt.hide()
        }
        presenter.setPresenting(presenting)
        NSLog("PresentationMode: \(presenting ? "on" : "off")")
        if !presenting {
            showNextNewAppPrompt()
            autoCollapseIfNeeded()
        }
    }
}

//MARK: - Separate hidden items bar: hover and menus
extension StatusBarController {
    private func showHiddenItemsBar() {
        if MenuBarEngineFactory.usesNativeVisibility {
            showNativeHiddenItemsBar()
        } else {
            expandHiddenItemsBar()
        }
    }

    // With "Hover to expand" on, hovering opens the row instead of the bar,
    // and the row closes once the pointer has left both it and the menu bar.
    private func openHiddenItemsBarOnHover() {
        guard !isSeparateHiddenItemsBarVisible, !hiddenItemsFreezeController.isVisible,
              hiddenSectionPeeker?.isPeeking != true else { return }
        showHiddenItemsBar()
        hoverRowLeaveTimer?.invalidate()
        var outsideSince: Date?
        hoverRowLeaveTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            // Still opening: the row isn't up yet.
            if !self.isSeparateHiddenItemsBarVisible {
                if self.hiddenItemsFreezeController.isVisible || self.hiddenSectionPeeker?.isPeeking == true { return }
                return timer.invalidate()
            }
            let inside = self.isMouseInMenuBar
                || self.hiddenItemsBarController.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
            if inside {
                outsideSince = nil
            } else if let since = outsideSince {
                if Date().timeIntervalSince(since) > 0.6 {
                    timer.invalidate()
                    self.collapseMenuBar()
                }
            } else {
                outsideSince = Date()
            }
        }
    }

    // Right-click on an icon in the row. On macOS 27 an app can be kept
    // visible from here, the same mark the new-app question sets.
    private func hiddenItemMenu(for item: HiddenItemsBarItem) -> NSMenu? {
        let menu = NSMenu()
        if let bundle = item.bundleIdentifier, newAppReporter != nil {
            let keep = NSMenuItem(title: "Keep Visible".localized, action: #selector(keepHiddenItemVisible(_:)), keyEquivalent: "")
            keep.target = self
            keep.representedObject = bundle
            menu.addItem(keep)
            menu.addItem(NSMenuItem.separator())
        }
        let manage = NSMenuItem(title: "Manage Menu Bar Items…".localized, action: #selector(openMenuBarItemManager), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)
        return menu
    }

    @objc private func keepHiddenItemVisible(_ sender: NSMenuItem) {
        guard let bundle = sender.representedObject as? String else { return }
        collapseMenuBar()
        keepVisible(bundle)
    }
}

//MARK: - New menu bar apps (macOS 27)
extension StatusBarController {
    private var newAppReporter: NewMenuBarAppReporting? {
        menuBarEngine as? NewMenuBarAppReporting
    }

    private func setupNewAppPrompts() {
        newAppReporter?.onNewApps = { [weak self] bundles in
            guard let self else { return }
            self.newAppQueue += bundles.filter { !self.newAppQueue.contains($0) }
            self.showNextNewAppPrompt()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleApplicationTerminated),
                                                          name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    // Helpers can show an icon for a moment and quit. Their question goes with
    // them; the app stays undecided and is asked about if its icon comes back.
    @objc private func handleApplicationTerminated(_ notification: Notification) {
        guard let bundle = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
              newAppQueue.contains(bundle) else { return }
        newAppQueue.removeAll { $0 == bundle }
        if newAppPrompt.bundleIdentifier == bundle {
            newAppPrompt.hide()
        }
        showNextNewAppPrompt()
    }

    private func showNextNewAppPrompt() {
        newAppQueue.removeAll { NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard !newAppPrompt.isVisible, !isPresenting, let bundle = newAppQueue.first,
              let arrowFrame = btnExpandCollapse.button?.window?.frame,
              let screen = btnExpandCollapse.button?.window?.screen
        else { return }
        newAppPrompt.show(bundleIdentifier: bundle, below: arrowFrame, on: screen) { [weak self] keep in
            guard let self else { return }
            self.newAppQueue.removeAll { $0 == bundle }
            self.newAppReporter?.resolveNewApp(bundle, keepVisible: keep)
            self.showNextNewAppPrompt()
        }
    }

    // Apps kept visible by bundle; Menu Bar Items lists them as Visible.
    var keptVisibleApps: Set<String> {
        newAppReporter?.keptVisibleApps ?? []
    }

    func stopKeepingVisible(_ bundle: String) {
        dropNewAppQuestion(bundle)
        newAppReporter?.resolveNewApp(bundle, keepVisible: false)
    }

    func keepVisible(_ bundle: String) {
        dropNewAppQuestion(bundle)
        newAppReporter?.resolveNewApp(bundle, keepVisible: true)
    }

    // Decided elsewhere (Menu Bar Items, the row's menu), so a question still
    // on screen would only undo it.
    private func dropNewAppQuestion(_ bundle: String) {
        newAppQueue.removeAll { $0 == bundle }
        guard newAppPrompt.bundleIdentifier == bundle else { return }
        newAppPrompt.hide()
        showNextNewAppPrompt()
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
