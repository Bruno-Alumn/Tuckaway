//
//  AppDelegate.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import HotKey
import ServiceManagement

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate{
    
    // Created in applicationDidFinishLaunching, once defaults are registered and
    // migrated: its init reads them, and a duplicate instance must not create
    // status items before it quits.
    private(set) var statusBarController: StatusBarController!

    var hotKey: HotKey? {
        didSet {
            guard let hotKey = hotKey else { return }

            hotKey.keyDownHandler = { [weak self] in
                self?.statusBarController.expandCollapseIfNeeded()
            }
        }
    }

    var presentationHotKey: HotKey? {
        didSet {
            presentationHotKey?.keyDownHandler = { [weak self] in
                self?.statusBarController.togglePresentationMode()
            }
        }
    }

    var findHotKey: HotKey? {
        didSet {
            findHotKey?.keyDownHandler = { [weak self] in
                self?.statusBarController.showHiddenIconSearch()
            }
        }
    }

    private var profileHotKeys: [HotKey] = []

    // Rebuilt whenever a profile's shortcut changes or a profile is deleted.
    // Releasing them all first frees the keys before any is registered again.
    func registerProfileHotKeys() {
        profileHotKeys = []
        guard StatusBarController.supportsPresentationMode else { return }
        let profiles = UserDefaultsMenuBarProfilesStore().profiles.profiles
        profileHotKeys = Preferences.profileShortcuts.compactMap { name, key in
            guard profiles[name] != nil else { return nil }
            let hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: key.keyCode, carbonModifiers: key.carbonFlags))
            hotKey.keyDownHandler = { [weak self] in
                self?.statusBarController.toggleProfile(named: name)
            }
            return hotKey
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard ensureSingleInstance() else { return }
        Preferences.migrateFromHiddenBar()
        registerDefaultValues()
        statusBarController = StatusBarController()
        setupAutoStartApp()
        setupHotKey()
        openPreferencesIfNeeded()
        // After the first-launch window: someone starting fresh has the settings
        // to read, not a list of what changed since a version they never ran.
        WhatsNewWindowController.showIfNeeded()
        detectLTRLang()
        Updater.shared.start()
    }

    /// Tuckaway is a menu bar utility with no visible window, so launching it a
    /// second time looks like a no-op while silently spawning a duplicate instance.
    /// If another instance with the same bundle ID is already running, activate it
    /// and terminate this one instead.
    private func ensureSingleInstance() -> Bool {
        let current = ProcessInfo.processInfo.processIdentifier
        // A copy that is quitting doesn't count: right after an update the
        // old copy can still be listed for a moment.
        let existing = NSWorkspace.shared.runningApplications.first {
            guard $0.bundleIdentifier == Bundle.main.bundleIdentifier,
                  $0.processIdentifier != current,
                  !$0.isTerminated,
                  kill($0.processIdentifier, 0) == 0 else { return false }
            #if DEBUG
            // Let a dev build run next to the installed copy; only dedupe
            // relaunches of the same bundle path.
            return $0.bundleURL == Bundle.main.bundleURL
            #else
            return true
            #endif
        }
        guard let existing else { return true }
        existing.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return false
    }
    
    // Settings opens on the very first launch so people can find the app, and
    // afterwards only if they ask for it: logging in and every update relaunch
    // would otherwise pop the window up.
    func openPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        let isFirstLaunch = !defaults.bool(forKey: UserDefaults.Key.hasLaunchedBefore)
        defaults.set(true, forKey: UserDefaults.Key.hasLaunchedBefore)
        if Self.opensPreferencesOnLaunch(isFirstLaunch: isFirstLaunch, showPreferencesOnLaunch: Preferences.isShowPreference) {
            Util.showPrefWindow()
        }
    }

    static func opensPreferencesOnLaunch(isFirstLaunch: Bool, showPreferencesOnLaunch: Bool) -> Bool {
        return isFirstLaunch || showPreferencesOnLaunch
    }
    
    func setupAutoStartApp() {
        removeLegacyLauncherLoginItem()
        Util.setUpAutoStart(isAutoStart: Preferences.isAutoStart)
    }

    private func removeLegacyLauncherLoginItem() {
        // Builds before the SMAppService migration registered a helper app in BTM;
        // macOS never garbage-collects that record (TN3111), so deauthorize it once.
        LegacyLoginItemMigration.migrate()
    }
    
    // A plain value, separate from the side-effecting `register(defaults:)`
    // call, so the "what are the defaults" behavior is testable without
    // spinning up an AppDelegate (which creates real status bar items).
    static let defaultPreferenceValues: [String: Any] = [
        UserDefaults.Key.isAutoStart: false,
        UserDefaults.Key.isShowPreference: false,
        UserDefaults.Key.isAutoHide: true,
        UserDefaults.Key.autoCollapseOnFocusChange: false,
        UserDefaults.Key.numberOfSecondForAutoHide: 10.0,
        UserDefaults.Key.areSeparatorsHidden: false,
        UserDefaults.Key.alwaysHiddenSectionEnabled: false,
        UserDefaults.Key.notchOverflowEnabled: true,
        UserDefaults.Key.useTransparentExpandIconEnabled: false,
        UserDefaults.Key.clickEmptyMenuBarToToggle: false,
        UserDefaults.Key.expandWhenExternalDisplayConnected: false,
        UserDefaults.Key.showHiddenItemsInSeparateBar: false,
        UserDefaults.Key.automaticallyChecksForUpdates: true
    ]

    func registerDefaultValues() {
        UserDefaults.standard.register(defaults: AppDelegate.defaultPreferenceValues)
    }
    
    func setupHotKey() {
        if let globalKey = Preferences.globalKey {
            hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: globalKey.keyCode, carbonModifiers: globalKey.carbonFlags))
        }
        if StatusBarController.supportsPresentationMode, let presentationKey = Preferences.presentationModeKey {
            presentationHotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: presentationKey.keyCode, carbonModifiers: presentationKey.carbonFlags))
        }
        if StatusBarController.supportsHiddenIconSearch, let findKey = Preferences.findHiddenIconKey {
            findHotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: findKey.keyCode, carbonModifiers: findKey.carbonFlags))
        }
        registerProfileHotKeys()
    }
    
    func detectLTRLang() {
        // Languages like Arabic uses right to left (RTL) writing direction,
        // so some behavier of the app needs to be changed in these cases
        
        Constant.isUsingLTRLanguage = (NSApplication.shared.userInterfaceLayoutDirection == .leftToRight)
    }
   
}
