//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices
import CoreLocation

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
    // Fires at the start of every minute while any profile has a schedule.
    private var profileScheduleTimer: Timer?
    private let profileLocation = ProfileLocationMonitor()
    private var activityRevealTimer: Timer?
    private var spacerItems: [NSStatusItem] = []
    private let activityReveal = ActivityRevealMonitor()
    private var hoverRowLeaveTimer: Timer?
    private let newAppPrompt = NewMenuBarAppPromptController()
    private let arrowNotice = ArrowLostNoticeController()
    // Set by Not Now, so a bar that keeps losing the arrow doesn't re-offer the
    // panel on every collapse until Tuckaway is relaunched.
    private var arrowNoticeDeclined = false
    private let hiddenIconSearch = HiddenIconSearchController()
    private let profilesStore = UserDefaultsMenuBarProfilesStore()
    // New apps waiting to be asked about, in order; the first is on screen.
    private var newAppQueue: [String] = []
    // The last answer to the new-app question, so it can be undone for a few
    // minutes (NewAppAnswerUndo).
    private var newAppAnswer: NewAppAnswerUndo?
    private var activeExpandCollapseFrame: CGRect?
    private var activeStatusItemScreen: NSScreen?
    private var didExpandForExternalDisplay = false
    private var hasCollapsedSinceLaunch = false
    private var appliedExpandWhenExternalDisplay = Preferences.expandWhenExternalDisplayConnected
    private var configurationDragMonitor: Any?
    private var commandKeyMonitor: Any?
    private var runningAppsObservation: NSKeyValueObservation?
    // The bar was expanded by holding ⌘ over it, not by the user's choice.
    private var isExpandedForCommand = false
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
    private var emptyMenuBarObserver: ClickObserver?
    private var emptyMenuBarObserverLacksTap = false
    private var scrollMonitor: Any?
    private var scrollLocalMonitor: Any?
    private var scrollGesture = MenuBarScrollGesture()
    private var windowClickObserver: ClickObserver?
    private var windowClickObserverLacksTap = false

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
        (menuBarEngine as? ProfileApplying)?.setProfile(profilesStore.profiles.activeApps)
        applyDisplayProfile()
        updateProfileSchedule()
        applyAppTriggeredProfile()
        updateProfilePlaces()
        updateActiveAppIcon()
        updateActivityReveal()
        updateSpacers()
        updateConfigurationDragMonitor()
        updateHoverMonitor()
        updateEmptyMenuBarMonitor()
        updateScrollMonitor()
        updateWindowClickMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWorkspaceMenuBarChange), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleApplicationActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(fitSpacersToState), name: NativeVisibilityEngine.stateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateHiddenCount), name: NativeVisibilityEngine.stateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateHiddenCount), name: NativeVisibilityEngine.hiddenItemsDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleLockOrSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleLockOrSleep), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        recordVersions(of: NSWorkspace.shared.runningApplications, reveal: false)
        observeRunningApplications()
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
        if let commandKeyMonitor {
            NSEvent.removeMonitor(commandKeyMonitor)
        }
        if let configurationDragMonitor = configurationDragMonitor {
            NSEvent.removeMonitor(configurationDragMonitor)
        }
        configurationDragCollapseWorkItem?.cancel()
        hoverDwellTimer?.invalidate()
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
        emptyMenuBarObserver?.stop()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        if let scrollLocalMonitor {
            NSEvent.removeMonitor(scrollLocalMonitor)
        }
        windowClickObserver?.stop()
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

    // Accessibility can arrive after launch, and only then can the event tap
    // be made, so a fallback observer is replaced once it's granted.
    private func updateEmptyMenuBarMonitor() {
        if Preferences.clickEmptyMenuBarToToggle {
            guard emptyMenuBarObserver == nil || (emptyMenuBarObserverLacksTap && AXIsProcessTrusted()) else { return }
            emptyMenuBarObserver?.stop()
            emptyMenuBarObserverLacksTap = !AXIsProcessTrusted()
            emptyMenuBarObserver = ClickObserver(.leftMouseUp) { [weak self] in
                guard let self, self.isEmptyMenuBarClick() else { return }
                self.expandCollapseIfNeeded()
            }
        } else {
            emptyMenuBarObserver?.stop()
            emptyMenuBarObserver = nil
        }
    }

    private func updateScrollMonitor() {
        if Preferences.scrollMenuBarToToggle {
            guard scrollMonitor == nil else { return }
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleMenuBarScroll(event)
            }
            scrollLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleMenuBarScroll(event)
                return event
            }
        } else if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
            if let scrollLocalMonitor {
                NSEvent.removeMonitor(scrollLocalMonitor)
                self.scrollLocalMonitor = nil
            }
        }
    }

    // Clicks in Tuckaway's own windows (Settings) never count: the decision
    // below skips windows Tuckaway owns.
    private func updateWindowClickMonitor() {
        if Preferences.collapseOnWindowClick {
            guard windowClickObserver == nil || (windowClickObserverLacksTap && AXIsProcessTrusted()) else { return }
            windowClickObserver?.stop()
            windowClickObserverLacksTap = !AXIsProcessTrusted()
            windowClickObserver = ClickObserver(.leftMouseDown) { [weak self] in
                self?.handleWindowClick()
            }
        } else {
            windowClickObserver?.stop()
            windowClickObserver = nil
        }
    }

    private func handleWindowClick() {
        guard !isCollapsed, !isMouseInMenuBar, !isManagingItems, !isPresenting,
              !didExpandForExternalDisplay else { return }
        // Give the clicked window a moment to come forward first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isCollapsed, !self.isMouseInMenuBar, !self.isManagingItems else { return }
            let frontmost = NSWorkspace.shared.frontmostApplication
            guard ExpandCollapseActionResolver.shouldCollapseAfterWindowClick(
                clickedApp: self.appUnderPointer(),
                frontmostApp: frontmost?.processIdentifier,
                frontmostIsRegular: frontmost?.activationPolicy == .regular,
                ownPid: ProcessInfo.processInfo.processIdentifier) else { return }
            self.collapseMenuBar()
        }
    }

    // The app owning whatever is under the pointer, as Accessibility hit-tests
    // it (so click-through overlays don't count).
    private func appUnderPointer() -> pid_t? {
        guard let primaryScreenTop = NSScreen.screens.first?.frame.maxY,
              !Util.isAccessibilityPermissionMissing else { return nil }
        let point = ExpandCollapseActionResolver.accessibilityPoint(forAppKitPoint: NSEvent.mouseLocation,
                                                                    primaryScreenTop: primaryScreenTop)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    // Only on empty space: some apps use scrolling over their own icon (a
    // volume or brightness slider), and that has to keep working.
    private func handleMenuBarScroll(_ event: NSEvent) {
        guard isMouseInMenuBar, !isMouseButtonDown, !isPresenting, !isManagingItems else { return }
        let direction = scrollGesture.handle(deltaY: event.scrollingDeltaY, deltaX: event.scrollingDeltaX,
                                             began: event.phase.contains(.began), at: event.timestamp)
        guard let direction, isEmptyMenuBarClick() else { return }
        let isShowing = !isCollapsed || isSeparateHiddenItemsBarVisible || hiddenSectionPeeker?.isPeeking == true
        switch direction {
        case .show where !isShowing:
            expandCollapseIfNeeded()
        case .hide where isShowing:
            expandCollapseIfNeeded()
        default:
            break
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
        applyDisplayProfile()
    }

    // A new status item or a wake can change the Accessibility inventory just
    // as much as a monitor hot-plug. The native engine releases its global
    // restriction here instead of applying a stale per-display classification.
    @objc private func handleWorkspaceMenuBarChange() {
        invalidateNativeLayoutAfterEnvironmentChange()
        applyScheduledProfile()
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

    // So nobody walking up to a locked Mac sees the hidden icons.
    @objc private func handleLockOrSleep() {
        guard Preferences.collapseWhenLocked, !isCollapsed, !isManagingItems else { return }
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
        if Preferences.expandWhenExternalDisplayConnected && Self.hasExternalDisplay {
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
        updateEmptyMenuBarMonitor()
        updateWindowClickMonitor()
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
        isExpandedForCommand = false
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
    // repair the saved order, and rebuild the two items. The decision is
    // MenuBarRescue's, so what counts as lost and when to stop repairing are
    // covered by tests.
    private func rescueArrowIfSwallowed() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let action = MenuBarRescue.action(arrowFrame: self.btnExpandCollapse.button?.window?.frame,
                                              screenFrames: NSScreen.screens.map(\.frame),
                                              isCollapsed: self.isCollapsed,
                                              repairsSoFar: self.arrowRescueCount)
            switch action {
            case .none:
                return
            case .giveUp:
                self.expandMenubar()
                self.showArrowLostNotice()
            case .repair:
                self.arrowRescueCount += 1
                self.expandMenubar()
                StatusItemPositions.pullArrowInside()
                self.rebuildStatusItems()
            }
        }
    }

    // Tuckaway keeps repairing a lost arrow on every launch, but that can leave
    // the user with an app they can't reach and no explanation. The panel names
    // the problem and offers the two ways out.
    private func showArrowLostNotice() {
        guard !arrowNotice.isVisible, !arrowNoticeDeclined else { return }
        // The arrow is off every screen here, so its window has no screen to
        // offer: show the panel on the main one instead.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let arrowFrame = btnExpandCollapse.button?.window?.frame ?? .zero
        arrowNotice.show(below: arrowFrame, on: screen, actions: ArrowLostNoticeController.Actions(
            repair: { [weak self] in self?.repairArrowPosition() },
            openSettings: { PreferencesWindowController.shared.show(tab: .general) },
            quit: { NSApp.terminate(nil) },
            notNow: { [weak self] in self?.arrowNoticeDeclined = true }
        ))
    }

    // Puts the arrow back near the right side of the bar and rebuilds the
    // items, starting the repair count over. Shared by the panel above and
    // anything else that offers a repair.
    func repairArrowPosition() {
        arrowRescueCount = 0
        StatusItemPositions.pullArrowInside()
        rebuildStatusItems()
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
    
    // A menu item whose action is this controller's: the four lines every entry
    // below needs, once.
    private func menuItem(_ title: String, action: Selector, key: String = "",
                          isOn: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let isOn { item.state = isOn ? .on : .off }
        return item
    }

    // Built fresh on every call (see showContextMenu(from:)), so every field
    // below reflects state as of THIS presentation - no separate "patch the
    // title after the fact" step is needed for the auto-collapse item.
    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()

        // Notch overflow menu item (only on notch Macs, and only when enabled)
        if NotchOverflowController.hasNotch && Preferences.notchOverflowEnabled {
            menu.addItem(menuItem("Show Notch Items".localized, action: #selector(showNotchOverflow)))
            menu.addItem(NSMenuItem.separator())
        }

        if Preferences.didShowMacOS27HideUnavailableNotice && !MenuBarEngineFactory.usesNativeVisibility {
            menu.addItem(menuItem("Hiding unavailable on macOS 27 - Learn more".localized,
                                  action: #selector(openMacOS27Notice)))
            menu.addItem(NSMenuItem.separator())
        }

        if Self.supportsHiddenIconSearch {
            menu.addItem(menuItem("Find Hidden Icon…".localized, action: #selector(showHiddenIconSearch)))
        }

        if menuBarEngine is ProfileApplying {
            menu.addItem(profilesMenuItem())
        }

        if let undo = activeNewAppUndo {
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: undo.bundle).first
            let name = app?.localizedName ?? undo.bundle
            let format = undo.undoesToKeepVisible ? "Undo: keep %@ visible" : "Undo: hide %@"
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem(String(format: format.localized, name), action: #selector(undoNewAppAnswer)))
        }

        if Self.supportsPresentationMode {
            menu.addItem(menuItem("Presentation Mode".localized, action: #selector(togglePresentationMode),
                                  isOn: isPresenting))
        }

        menu.addItem(menuItem("Auto-collapse".localized, action: #selector(toggleAutoHide), key: "t",
                              isOn: Preferences.isAutoHide))
        // The title asks for the opposite of what is on, so the menu says what a
        // click will do.
        menu.addItem(menuItem(Preferences.areSeparatorsHidden ? "Show separators".localized : "Hide separators".localized,
                              action: #selector(showHideSeparatorsAndAlwayHideArea), key: "s"))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Manage Menu Bar Items…".localized, action: #selector(openMenuBarItemManager)))

        if Updater.isSupported {
            // Not this controller's action: the updater's.
            let updateItem = NSMenuItem(title: "Check for Updates…".localized, action: #selector(Updater.checkForUpdates), keyEquivalent: "")
            updateItem.target = Updater.shared
            menu.addItem(updateItem)
        }

        menu.addItem(menuItem("Settings…".localized, action: #selector(openPreferenceViewControllerIfNeeded), key: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Tuckaway".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    // Polls while either option is on; each tick decides from the bar's
    // state, so collapsing and expanding need no hooks of their own.
    private func updateActivityReveal() {
        guard menuBarEngine is ActivityRevealing else { return }
        guard Preferences.revealIconsOnActivity || Preferences.revealUpdatedApps else {
            activityRevealTimer?.invalidate()
            activityRevealTimer = nil
            checkActivity()
            return
        }
        guard activityRevealTimer == nil else { return }
        let timer = Timer(timeInterval: ActivityRevealMonitor.pollInterval, repeats: true) { [weak self] _ in
            self?.checkActivity()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        activityRevealTimer = timer
    }

    private func checkActivity() {
        guard let revealer = menuBarEngine as? ActivityRevealing else { return }
        let isWatching = (Preferences.revealIconsOnActivity || Preferences.revealUpdatedApps) && isCollapsed && !isPresenting
        let watching = isWatching ? (Preferences.revealIconsOnActivity ? revealer.appsWatchedForActivity : []) : nil
        activityReveal.tick(watching: watching) { [weak revealer] apps in
            revealer?.setRevealedApps(apps)
        }
    }

    // The number sits right of the arrow; the arrow's image stays what VoiceOver
    // reads, and the number follows it.
    @objc private func updateHiddenCount() {
        guard let button = btnExpandCollapse.button else { return }
        let count = (menuBarEngine as? HiddenSectionPeeking)?.hiddenItems.count ?? 0
        let title = HiddenIconCount.title(count: count, collapsed: isCollapsed,
                                          enabled: Preferences.showHiddenIconCount && menuBarEngine is HiddenSectionPeeking)
        guard button.title != title else { return }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        button.title = title
    }

    // Adds or removes spacer items to match the setting. macOS remembers each
    // one's place by its autosave name, so a spacer comes back where it was.
    private func updateSpacers() {
        let count = Preferences.spacerCount
        while spacerItems.count > count {
            NSStatusBar.system.removeStatusItem(spacerItems.removeLast())
        }
        while spacerItems.count < count {
            let item = NSStatusBar.system.statusItem(withLength: CGFloat(Preferences.spacerWidth.rawValue))
            item.autosaveName = MenuBarSpacers.autosaveName(spacerItems.count + 1)
            item.button?.setAccessibilityLabel("Spacer".localized)
            spacerItems.append(item)
        }
        fitSpacersToState()
    }

    @objc private func fitSpacersToState() {
        guard !spacerItems.isEmpty else { return }
        let arrowMinX = btnExpandCollapse.button?.window?.frame.minX ?? 0
        let lengths = MenuBarSpacers.lengths(
            spacerMinX: spacerItems.map { $0.button?.window?.frame.minX ?? arrowMinX },
            arrowMinX: arrowMinX,
            isLTR: NSApp.userInterfaceLayoutDirection == .leftToRight,
            collapsed: MenuBarEngineFactory.usesNativeVisibility && isCollapsed,
            width: Preferences.spacerWidth)
        for (item, length) in zip(spacerItems, lengths) where item.length != length {
            item.length = length
        }
    }

    // Every launch records the app's version; one that changed since the last
    // launch shows for a moment if that option is on (#28). Apps running when
    // Tuckaway starts are recorded too, so their next update is noticed.
    // NSWorkspace doesn't post didLaunch or didTerminate for apps with
    // LSUIElement, which is nearly every menu-bar app (seen on 27.2: a new
    // app's icon went unnoticed until the next expand). Its running
    // applications change for every app, so watch those instead.
    private func observeRunningApplications() {
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, change in
            let launched = change.kind == .insertion ? change.newValue ?? [] : []
            DispatchQueue.main.async { self?.runningApplicationsChanged(launched: launched) }
        }
    }

    private func runningApplicationsChanged(launched: [NSRunningApplication]) {
        applyAppTriggeredProfile()
        // Background-only apps can't own a status item, and there are many of them.
        let launched = launched.filter { $0.activationPolicy != .prohibited }
        guard !launched.isEmpty else { return }
        recordVersions(of: launched, reveal: true)
        handleWorkspaceMenuBarChange()
    }

    private func recordVersions(of apps: [NSRunningApplication], reveal: Bool) {
        guard menuBarEngine is ActivityRevealing else { return }
        var versions = AppVersions(known: UserDefaults.standard.dictionary(forKey: Self.appVersionsKey) as? [String: String] ?? [:])
        var updated: [String] = []
        for app in apps {
            guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
                  let url = app.bundleURL, let version = AppVersions.version(of: Bundle(url: url)?.infoDictionary) else { continue }
            if versions.launched(bundle, version: version) { updated.append(bundle) }
        }
        UserDefaults.standard.set(versions.known, forKey: Self.appVersionsKey)
        guard reveal, Preferences.revealUpdatedApps, isCollapsed, !isPresenting,
              let revealer = menuBarEngine as? ActivityRevealing else { return }
        for bundle in updated {
            revealer.setRevealedApps(activityReveal.revealUpdated(bundle))
        }
    }

    private static let appVersionsKey = "knownAppVersions"

    // Tuckaway itself in front (Settings) keeps the previous app shown.
    private func updateActiveAppIcon(_ app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        guard let shower = menuBarEngine as? ActiveAppShowing else { return }
        guard Preferences.showActiveAppIcon else { return shower.setActiveApp(nil) }
        if let app, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            shower.setActiveApp(app.bundleIdentifier)
        }
    }

    @objc func updateAutoHide() {
        updateActiveAppIcon()
        updateActivityReveal()
        updateSpacers()
        updateHiddenCount()
        updateConfigurationDragMonitor()
        updateHoverMonitor()
        updateEmptyMenuBarMonitor()
        updateScrollMonitor()
        updateWindowClickMonitor()
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

    @objc func openMacOS27Notice() {
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
        updateCommandKeyMonitor()
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

    // On macOS 27 the restriction that hides icons while collapsed also stops
    // the visible ones from being ⌘-dragged, and expanding once the drag has
    // begun is too late for it. So holding ⌘ with the pointer over the menu bar
    // expands first, whether ⌘ goes down over the bar or the pointer arrives
    // with it held. Once ⌘ and the mouse are both released it collapses again,
    // as soon as the pointer leaves the bar, even with auto-collapse off: the
    // user never asked for it to stay open.
    private func updateCommandKeyMonitor() {
        guard MenuBarEngineFactory.usesNativeVisibility, commandKeyMonitor == nil else { return }
        commandKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .mouseMoved, .leftMouseUp]) { [weak self] event in
            guard let self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if self.isExpandedForCommand {
                guard event.type != .mouseMoved, !flags.contains(.command),
                      event.type == .leftMouseUp || !self.isMouseButtonDown
                else { return }
                self.isExpandedForCommand = false
                if !self.isCollapsed && !self.isManagingItems { self.scheduleRecollapse(after: 1) }
                return
            }
            guard event.type != .leftMouseUp, flags == .command,
                  self.isCollapsed, self.isMouseInMenuBar, !self.isMouseButtonDown, !self.isPresenting
            else { return }
            self.isExpandedForCommand = true
            self.expandMenubar()
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
    // MenuBarCoordinateSpace does the arithmetic, so it is covered by tests.
    private static func coordinateSpace(fallbackMaxY: CGFloat) -> MenuBarCoordinateSpace.Conversion {
        .init(primaryScreenMaxY: NSScreen.screens.first?.frame.maxY, fallbackMaxY: fallbackMaxY)
    }

    private func appKitRectFromQuartzRect(_ quartzRect: CGRect, on screen: NSScreen) -> CGRect {
        MenuBarCoordinateSpace.appKitRect(fromQuartz: quartzRect,
                                          in: Self.coordinateSpace(fallbackMaxY: screen.frame.maxY))
    }

    private func quartzRectFromAppKitRect(_ appKitRect: CGRect) -> CGRect {
        MenuBarCoordinateSpace.quartzRect(fromAppKit: appKitRect,
                                          in: Self.coordinateSpace(fallbackMaxY: appKitRect.maxY))
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
        let space = Self.coordinateSpace(fallbackMaxY: appKitPoint.y)
        postClick(atQuartzPoint: MenuBarCoordinateSpace.quartzPoint(fromAppKit: appKitPoint, in: space))
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

//MARK: - Profiles (macOS 27)
extension StatusBarController {
    static func describe(_ reason: MenuBarProfiles.SwitchReason) -> String {
        switch reason {
        case .place(let label):
            return label.map { String(format: "Switched at %@".localized, $0) } ?? "Switched at this place".localized
        case .app(let bundle):
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundle
            return String(format: "Switched while %@ is open".localized, name)
        case .schedule:
            return "Switched by its schedule".localized
        case .display:
            return "Switched for the connected display".localized
        }
    }

    fileprivate func profilesMenuItem() -> NSMenuItem {
        let profiles = profilesStore.profiles
        let submenu = NSMenu()
        let arrow = NSMenuItem(title: "Use the Arrow".localized, action: #selector(selectProfile(_:)), keyEquivalent: "")
        arrow.target = self
        arrow.state = profiles.active == nil ? .on : .off
        submenu.addItem(arrow)
        for name in profiles.names {
            let item = NSMenuItem(title: name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = profiles.active == name ? .on : .off
            if #available(macOS 14.4, *), let reason = profiles.switchReason(for: name) {
                item.subtitle = Self.describe(reason)
            }
            submenu.addItem(item)
        }
        submenu.addItem(NSMenuItem.separator())
        let save = NSMenuItem(title: "Save Current Layout as Profile…".localized, action: #selector(saveProfile), keyEquivalent: "")
        save.target = self
        submenu.addItem(save)
        if !profiles.names.isEmpty {
            let delete = NSMenuItem(title: "Delete Profile".localized, action: nil, keyEquivalent: "")
            let names = NSMenu()
            for name in profiles.names {
                let item = NSMenuItem(title: name, action: #selector(deleteProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = name
                names.addItem(item)
            }
            delete.submenu = names
            submenu.addItem(delete)

            let display = NSMenuItem(title: "When a Display Is Connected".localized, action: nil, keyEquivalent: "")
            let choices = NSMenu()
            for name in [nil] + profiles.names.map(Optional.some) {
                let item = NSMenuItem(title: name ?? "Don’t Switch".localized, action: #selector(setDisplayProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = name
                item.state = profiles.displayProfile == name ? .on : .off
                choices.addItem(item)
            }
            display.submenu = choices
            submenu.addItem(display)
        }
        let item = NSMenuItem(title: "Profiles".localized, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // "When a Display Is Connected": switches to that profile while a second
    // display is attached, and back when it's unplugged.
    private func applyDisplayProfile() {
        guard menuBarEngine is ProfileApplying else { return }
        var profiles = profilesStore.profiles
        let before = profiles
        profiles.displaysChanged(external: Self.hasExternalDisplay)
        if profiles != before {
            applyProfiles(profiles)
        }
    }

    // Any display that isn't the built-in one. Counting screens missed a
    // MacBook closed at a desk (one screen, the external one).
    static var hasExternalDisplay: Bool {
        NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) == 0
        }
    }

    @objc private func setDisplayProfile(_ sender: NSMenuItem) {
        var profiles = profilesStore.profiles
        profiles.setDisplayProfile(sender.representedObject as? String)
        applyProfiles(profiles)
        applyDisplayProfile()
    }

    // Runs the schedule check now and arms the per-minute timer, or stops it
    // when no profile has a schedule.
    func updateProfileSchedule() {
        guard menuBarEngine is ProfileApplying else { return }
        applyScheduledProfile()
        profileScheduleTimer?.invalidate()
        profileScheduleTimer = nil
        NotificationCenter.default.removeObserver(self, name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .NSSystemTimeZoneDidChange, object: nil)
        guard !profilesStore.profiles.schedules.isEmpty else { return }
        let now = Date()
        let nextMinute = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        let timer = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in
            self?.applyScheduledProfile()
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        profileScheduleTimer = timer
        NotificationCenter.default.addObserver(self, selector: #selector(handleClockChange), name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleClockChange), name: .NSSystemTimeZoneDidChange, object: nil)
    }

    // The timer drifts from the minute boundary after the clock jumps.
    @objc private func handleClockChange() {
        updateProfileSchedule()
    }

    private func applyScheduledProfile() {
        guard menuBarEngine is ProfileApplying else { return }
        var profiles = profilesStore.profiles
        guard !profiles.schedules.isEmpty || profiles.scheduled != nil else { return }
        let before = profiles
        let time = Calendar.current.dateComponents([.hour, .minute], from: Date())
        profiles.timeChanged(minute: (time.hour ?? 0) * 60 + (time.minute ?? 0))
        if profiles != before {
            applyProfiles(profiles)
        }
    }

    // "While an App Is Open": the running apps decide, checked on every launch
    // and quit.
    @objc private func applyAppTriggeredProfile() {
        guard menuBarEngine is ProfileApplying else { return }
        var profiles = profilesStore.profiles
        guard !profiles.appTriggers.isEmpty || profiles.appSwitched != nil else { return }
        let before = profiles
        let running = Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
        profiles.appsChanged(running: running)
        if profiles != before {
            applyProfiles(profiles)
        }
    }

    func setAppTrigger(_ bundle: String?, forProfile name: String) {
        var profiles = profilesStore.profiles
        profiles.setAppTrigger(bundle, for: name)
        applyProfiles(profiles)
        applyAppTriggeredProfile()
    }

    // "At a Place": follows the Mac's location while any profile has a place.
    func updateProfilePlaces() {
        guard menuBarEngine is ProfileApplying else { return }
        let profiles = profilesStore.profiles
        profileLocation.onLocation = { [weak self] location in
            self?.applyPlaceProfile(location)
        }
        profileLocation.setMonitoring(!profiles.places.isEmpty || profiles.placeSwitched != nil)
    }

    private func applyPlaceProfile(_ location: CLLocation) {
        guard menuBarEngine is ProfileApplying else { return }
        var profiles = profilesStore.profiles
        let before = profiles
        profiles.locationChanged(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                 accuracy: location.horizontalAccuracy)
        if profiles != before {
            applyProfiles(profiles)
        }
    }

    // Asks for Location access the first time, then reports where the Mac is
    // now, or nil if that isn't allowed or can't be found.
    func currentLocation(_ completion: @escaping (CLLocation?) -> Void) {
        profileLocation.currentLocation(completion)
    }

    var locationAccessDenied: Bool {
        [.denied, .restricted].contains(profileLocation.authorizationStatus)
    }

    func setPlace(_ place: ProfilePlace?, forProfile name: String) {
        var profiles = profilesStore.profiles
        profiles.setPlace(place, for: name)
        applyProfiles(profiles)
        updateProfilePlaces()
        if place != nil {
            profileLocation.currentLocation { [weak self] location in
                if let location { self?.applyPlaceProfile(location) }
            }
        }
    }

    func setSchedule(_ schedule: ProfileSchedule?, forProfile name: String) {
        var profiles = profilesStore.profiles
        profiles.setSchedule(schedule, for: name)
        applyProfiles(profiles)
        updateProfileSchedule()
    }

    var activeProfileName: String? {
        menuBarEngine is ProfileApplying ? profilesStore.profiles.active : nil
    }

    private func applyProfiles(_ profiles: MenuBarProfiles) {
        profilesStore.profiles = profiles
        (menuBarEngine as? ProfileApplying)?.setProfile(profiles.activeApps)
        NotificationCenter.default.post(name: .profileChanged, object: nil)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        var profiles = profilesStore.profiles
        profiles.active = sender.representedObject as? String
        applyProfiles(profiles)
    }

    // Saves what the collapsed bar shows now under a name, and switches to it.
    @objc private func saveProfile() {
        guard let engine = menuBarEngine as? ProfileApplying else { return }
        engine.readVisibleApps { [weak self] apps in
            // Nothing read yet, or nothing visible: a profile that hides every
            // icon isn't what saving the current layout means.
            guard let self, let apps else { return NSSound.beep() }
            let alert = NSAlert()
            alert.messageText = "Name this profile".localized
            alert.informativeText = "It keeps the apps that are visible right now.".localized
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            alert.accessoryView = field
            alert.addButton(withTitle: "Save".localized)
            alert.addButton(withTitle: "Cancel".localized)
            alert.window.initialFirstResponder = field
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            var profiles = self.profilesStore.profiles
            profiles.save(name, apps: apps)
            profiles.active = name
            self.applyProfiles(profiles)
        }
    }

    @objc private func deleteProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        deleteProfile(named: name)
    }

    func deleteProfile(named name: String) {
        var profiles = profilesStore.profiles
        profiles.delete(name)
        applyProfiles(profiles)
        updateProfileSchedule()
        updateProfilePlaces()
        // A later profile with the same name shouldn't inherit the shortcut.
        var shortcuts = Preferences.profileShortcuts
        if shortcuts.removeValue(forKey: name) != nil {
            Preferences.profileShortcuts = shortcuts
            (NSApp.delegate as? AppDelegate)?.registerProfileHotKeys()
        }
    }

    // From Settings. The shortcut moves with the name.
    func renameProfile(_ name: String, to newName: String) -> Bool {
        var profiles = profilesStore.profiles
        guard profiles.rename(name, to: newName) else { return false }
        applyProfiles(profiles)
        var shortcuts = Preferences.profileShortcuts
        if name != newName, let shortcut = shortcuts.removeValue(forKey: name) {
            shortcuts[newName] = shortcut
            Preferences.profileShortcuts = shortcuts
            (NSApp.delegate as? AppDelegate)?.registerProfileHotKeys()
        }
        return true
    }

    // Replaces the profile's apps with what the collapsed bar shows now, the
    // way saving it did. Calls back with false when nothing could be read.
    func updateProfileToCurrentLayout(_ name: String, completion: @escaping (Bool) -> Void) {
        guard let engine = menuBarEngine as? ProfileApplying else { return completion(false) }
        engine.readVisibleApps { [weak self] apps in
            guard let self, let apps else { return completion(false) }
            var profiles = self.profilesStore.profiles
            profiles.setApps(apps, for: name)
            self.applyProfiles(profiles)
            completion(true)
        }
    }

    func removeApp(_ bundle: String, fromProfile name: String) {
        var profiles = profilesStore.profiles
        guard let apps = profiles.profiles[name] else { return }
        profiles.setApps(apps.filter { $0 != bundle }, for: name)
        applyProfiles(profiles)
    }

    // A profile's shortcut.
    func toggleProfile(named name: String) {
        guard menuBarEngine is ProfileApplying else { return }
        var profiles = profilesStore.profiles
        let before = profiles
        profiles.toggle(name)
        if profiles != before {
            applyProfiles(profiles)
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
            if keep {
                self.keepVisible(bundle)
            } else {
                self.newAppReporter?.resolveNewApp(bundle, keepVisible: false)
                self.removeFromActiveProfile(bundle)
            }
            // After answering, since keepVisible drops an undo for the same app.
            self.newAppAnswer = NewAppAnswerUndo(bundle: bundle, wasKeptVisible: keep, answeredAt: Date())
            self.showNextNewAppPrompt()
        }
    }

    // The undo to offer right now: still fresh, and the app still running, since
    // a decision about an app that quit can't be shown to make a difference.
    private var activeNewAppUndo: NewAppAnswerUndo? {
        guard let undo = NewAppAnswerUndo.offered(newAppAnswer, bundle: newAppAnswer?.bundle ?? "", now: Date()),
              !NSRunningApplication.runningApplications(withBundleIdentifier: undo.bundle).isEmpty else { return nil }
        return undo
    }

    @objc private func undoNewAppAnswer() {
        guard let undo = activeNewAppUndo else { return }
        if undo.undoesToKeepVisible {
            keepVisible(undo.bundle)
        } else {
            stopKeepingVisible(undo.bundle)
        }
    }

    // For Check Your Setup: how many icons the collapsed bar would hide, and
    // whether the engine can read the layout at all right now.
    var hiddenIconCountForSetupCheck: Int {
        (menuBarEngine as? HiddenSectionPeeking)?.hiddenItems.count ?? 0
    }

    // Nil before the engine's first full read: no layout yet says nothing
    // about where the icons are.
    var layoutIsReadableForSetupCheck: Bool? {
        guard let engine = menuBarEngine as? NativeVisibilityEngine else { return nil }
        return engine.layout != nil
    }

    var isArrowOnScreenForSetupCheck: Bool {
        MenuBarRescue.isReachable(arrowFrame: btnExpandCollapse.button?.window?.frame,
                                  screenFrames: NSScreen.screens.map(\.frame))
    }

    // Apps kept visible by bundle; Menu Bar Items lists them as Visible.
    var keptVisibleApps: Set<String> {
        newAppReporter?.keptVisibleApps ?? []
    }

    func stopKeepingVisible(_ bundle: String) {
        dropNewAppQuestion(bundle)
        dropNewAppUndo(bundle)
        newAppReporter?.resolveNewApp(bundle, keepVisible: false)
        removeFromActiveProfile(bundle)
    }

    private func removeFromActiveProfile(_ bundle: String) {
        var profiles = profilesStore.profiles
        guard profiles.active != nil else { return }
        profiles.removeFromActive(bundle)
        applyProfiles(profiles)
    }

    func keepVisible(_ bundle: String) {
        dropNewAppQuestion(bundle)
        dropNewAppUndo(bundle)
        newAppReporter?.resolveNewApp(bundle, keepVisible: true)
        // With a profile active, keeping an app visible has to reach the profile.
        var profiles = profilesStore.profiles
        if profiles.active != nil {
            profiles.addToActive(bundle)
            applyProfiles(profiles)
        }
    }

    // Decided again (by the undo or in Menu Bar Items), so the old answer has
    // nothing left to undo.
    private func dropNewAppUndo(_ bundle: String) {
        if newAppAnswer?.bundle == bundle {
            newAppAnswer = nil
        }
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

// Location for profiles used at a place. Updates arrive only while some
// profile has a place; a hundred meters is plenty to tell home from work, and
// asks less of the hardware than a precise fix.
final class ProfileLocationMonitor: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    private let manager = CLLocationManager()
    private var isMonitoring = false
    private var waiting: [UUID: (CLLocation?) -> Void] = [:]

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    private var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    func setMonitoring(_ monitoring: Bool) {
        isMonitoring = monitoring
        if monitoring && isAuthorized {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    func currentLocation(_ completion: @escaping (CLLocation?) -> Void) {
        // While updates already run, a stationary Mac may not report again
        // (the distance filter), so a fix from the last two minutes answers.
        if isAuthorized, let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -120 {
            return completion(recent)
        }
        let id = UUID()
        waiting[id] = completion
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestAlwaysAuthorization()
        case .denied, .restricted: finish(nil)
        default: manager.requestLocation()
        }
        // Never leave the caller waiting: no fix in 30 seconds counts as none.
        // A permission prompt still open then keeps its own answer for later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.manager.authorizationStatus != .notDetermined,
                  let late = self.waiting.removeValue(forKey: id) else { return }
            late(nil)
        }
    }

    private func finish(_ location: CLLocation?) {
        let callbacks = waiting.values
        waiting = [:]
        callbacks.forEach { $0(location) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        setMonitoring(isMonitoring)
        guard !waiting.isEmpty, manager.authorizationStatus != .notDetermined else { return }
        if isAuthorized { manager.requestLocation() } else { finish(nil) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        finish(location)
        // A cached fix from long ago, or one only good to a kilometer or more,
        // says too little about where the Mac is now.
        if isMonitoring && location.timestamp.timeIntervalSinceNow > -10 * 60
            && location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 1000 {
            onLocation?(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}
