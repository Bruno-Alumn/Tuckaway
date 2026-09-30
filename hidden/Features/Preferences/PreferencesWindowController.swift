//
//  PreferencesWindowController.swift
//  Hidden Bar
//
//  Created by Phuc Le Dien on 2/22/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    
    static let shared: PreferencesWindowController = {
        let wc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "MainWindow") as! PreferencesWindowController
        return wc
    }()
    
    private let preferencesVC = PreferencesViewController.initWithStoryboard()
    private let aboutVC = AboutViewController.initWithStoryboard()
    private lazy var tabs: SettingsTabViewController = {
        let controller = SettingsTabViewController()
        controller.tabStyle = .toolbar
        controller.onSelectionChange = { [weak self] in self?.preferencesVC.cancelShortcutRecording() }
        let general = NSTabViewItem(viewController: preferencesVC)
        general.label = "General".localized
        general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: general.label)
        let about = NSTabViewItem(viewController: aboutVC)
        about.label = "About".localized
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: about.label)
        controller.addTabViewItem(general)
        controller.addTabViewItem(about)
        return controller
    }()

    private var activePreferences: PreferencesViewController? {
        tabs.selectedTabViewItemIndex == 0 ? preferencesVC : nil
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }
        window.toolbar = nil
        window.styleMask.remove(.fullSizeContentView)
        window.toolbarStyle = .preference
        window.contentViewController = tabs
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
    var onSelectionChange: () -> Void = {}

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        onSelectionChange()
        super.tabView(tabView, didSelect: tabViewItem)
    }
}
