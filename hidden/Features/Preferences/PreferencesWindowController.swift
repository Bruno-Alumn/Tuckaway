//
//  PreferencesWindowController.swift
//  Hidden Bar
//
//  Created by Phuc Le Dien on 2/22/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    
    private static var sharedInstance: PreferencesWindowController?

    static let shared: PreferencesWindowController = {
        let wc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "MainWindow") as! PreferencesWindowController
        sharedInstance = wc
        return wc
    }()

    // Checking auto-hide must not instantiate the storyboard or its view
    // controllers for a window the user has never opened.
    static var isVisible: Bool {
        guard let controller = sharedInstance, controller.isWindowLoaded else { return false }
        return controller.window?.isVisible ?? false
    }
    
    private lazy var preferencesVC = PreferencesViewController.initWithStoryboard()
    private lazy var itemManagerVC = MenuBarItemManagerViewController()
    private lazy var aboutVC = AboutViewController.initWithStoryboard()

    enum Tab: Int {
        case general, items, about
    }

    // Native settings tabs: icons in the toolbar, the window titled after the
    // selected tab and resized to that tab's preferredContentSize.
    private lazy var tabs: SettingsTabViewController = {
        let controller = SettingsTabViewController()
        controller.tabStyle = .toolbar
        controller.canPropagateSelectedChildViewControllerTitle = true
        controller.onSelectionChange = { [weak self] _ in
            self?.preferencesVC.cancelShortcutRecording()
        }
        controller.addTabViewItem(tabItem(preferencesVC, label: "General", symbol: "gearshape"))
        controller.addTabViewItem(tabItem(itemManagerVC, label: "Menu Bar Items", symbol: "menubar.rectangle"))
        controller.addTabViewItem(tabItem(aboutVC, label: "About", symbol: "info.circle"))
        return controller
    }()

    private func tabItem(_ viewController: NSViewController, label: String, symbol: String) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: viewController)
        item.label = label.localized
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.label)
        viewController.title = item.label
        return item
    }

    func show(tab: Tab) {
        _ = window
        tabs.selectedTabViewItemIndex = tab.rawValue
        window?.bringToFront()
    }

    private var activePreferences: PreferencesViewController? {
        tabs.selectedTabViewItemIndex == Tab.general.rawValue ? preferencesVC : nil
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .preference
        window.contentViewController = tabs
        window.center()
    }

    func windowWillClose(_ notification: Notification) {
        preferencesVC.cancelShortcutRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        preferencesVC.cancelShortcutRecording()
    }

    override func keyDown(with event: NSEvent) {
        if let vc = activePreferences, vc.listening {
            if event.keyCode == 53 { // Escape cancels without clearing the saved shortcut.
                vc.cancelShortcutRecording()
            } else {
                vc.updateGlobalShortcut(event)
            }
            return
        }
        super.keyDown(with: event)
    }

    // Cmd+W closes the prefs window. The main menu has no File > Close item, so
    // the key equivalent falls through to the responder chain. While the
    // shortcut recorder is listening it keeps the event, so the user can still
    // bind Cmd+W as the global hotkey.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let vc = activePreferences, vc.listening {
            if event.keyCode == 53 {
                vc.cancelShortcutRecording()
            } else {
                vc.updateGlobalShortcut(event)
            }
            return true
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.isSubset(of: [.command, .shift]),
           mods.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            window?.performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if let vc = activePreferences, vc.listening {
            vc.updateModiferFlags(event)
        }
    }
    
}

private final class SettingsTabViewController: NSTabViewController {
    var onSelectionChange: (Int) -> Void = { _ in }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if let tabViewItem {
            onSelectionChange(tabView.indexOfTabViewItem(tabViewItem))
        }
        super.tabView(tabView, didSelect: tabViewItem)
    }
}
