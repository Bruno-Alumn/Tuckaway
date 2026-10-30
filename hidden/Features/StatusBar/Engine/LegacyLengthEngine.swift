//
//  LegacyLengthEngine.swift
//  Tuckaway
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// Hides icons by inflating the separator until everything to its left leaves the
// visible bar. macOS <= 26 reflows around any length, so the length only has to
// be large enough to cover the widest attached display.
final class LegacyLengthEngine: MenuBarEngine {
    private weak var items: MenuBarItemProvider?
    private let screenWidths: () -> [CGFloat]

    private let expandedLength: CGFloat = 20

    // macOS 27 gives the separator its own backing window. If inflating it grows
    // beyond the screen without displacing neighboring icons, restore the bar and
    // stop trying the old mechanism (#360).
    private var hideMechanismChecked = false
    private var hideDegraded = false

    init(items: MenuBarItemProvider,
         screenWidths: @escaping () -> [CGFloat] = { NSScreen.screens.map { $0.frame.width } }) {
        self.items = items
        self.screenWidths = screenWidths
    }

    // Derived from the live length rather than stored, and compared with > rather
    // than ==, so the state survives the collapse length being recomputed while
    // collapsed (PR #354).
    var state: MenuBarEngineState {
        guard let separator = items?.separatorItem else { return .expanded }
        return separator.length > expandedLength ? .collapsed : .expanded
    }

    private var collapsedLength: CGFloat {
        // The menubar replicates across every attached display, so the collapse
        // length must cover the WIDEST screen, not NSScreen.main (the focused one);
        // sizing from a narrower screen leaks hidden icons on wider displays.
        // frame.width, not visibleFrame: the menubar spans the full frame width.
        let screenWidth = screenWidths().max() ?? 1728
        // Keep collapse length bounded to avoid pathological layout/memory behavior;
        // macOS enforces a hard 10,000pt maximum on NSStatusItem.length (PR #354).
        return max(500, min(screenWidth * 2, 10_000))
    }

    func collapse(completion: @escaping (CollapseResult) -> Void) {
        if ProcessInfo.processInfo.isMacOS27OrLater,
           hideDegraded || UserDefaults.standard.bool(forKey: "didShowMacOS27HideUnavailableNotice") {
            degradeHideUnavailable()
            return completion(.unavailable)
        }
        items?.separatorItem.length = collapsedLength
        completion(.collapsed)
        verifyHideMechanismIfNeeded()
    }

    func expand() {
        items?.separatorItem.length = expandedLength
    }

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {
        let length: CGFloat
        if separatorHidden {
            length = enabled ? collapsedLength : 0
        } else {
            length = enabled ? expandedLength : 0
        }
        items?.alwaysHiddenItem?.length = length
    }

    // The separator is what widens, so it must sit between the hidden icons and
    // the arrow, and the always-hidden separator further out still.
    var isArrangementValid: Bool {
        return MenuBarOrder.isItem(items?.separatorItem, onHiddenSideOf: items?.toggleItem)
    }

    var isAlwaysHiddenSeparatorPlaced: Bool {
        return MenuBarOrder.isItem(items?.alwaysHiddenItem, onHiddenSideOf: items?.separatorItem)
    }

    func invalidateLayout() {
        // Each section can be hidden independently. In particular, expanding
        // the ordinary section leaves the always-hidden spacer inflated.
        // Preserve each live item's presentation when a display changes.
        let length = collapsedLength
        if let separator = items?.separatorItem, separator.length > expandedLength {
            separator.length = length
        }
        if let alwaysHidden = items?.alwaysHiddenItem, alwaysHidden.length > expandedLength {
            alwaysHidden.length = length
        }
    }

    // macOS <= 26 shares a screen-wide menu-bar window. On macOS 27, a separator
    // window wider than the screen means inflation grew only our own item and did
    // not hide its neighbors. Wait for a real window before latching the check.
    private func verifyHideMechanismIfNeeded() {
        guard !hideMechanismChecked else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.state == .collapsed, !self.hideMechanismChecked else { return }
            guard let separator = self.items?.separatorItem,
                  let separatorButton = separator.button,
                  let window = separatorButton.window else { return }
            self.hideMechanismChecked = true
            let requested = self.collapsedLength
            let windowWidth = window.frame.width
            let buttonWidth = separatorButton.frame.width
            let screenWidth = self.screenWidths().max() ?? 0
            NSLog("HideMechanism: requested=\(requested) windowWidth=\(windowWidth) buttonWidth=\(buttonWidth) length=\(separator.length) screenWidth=\(screenWidth) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
            guard ProcessInfo.processInfo.isMacOS27OrLater else { return }
            if screenWidth <= 0 || windowWidth > screenWidth * 1.1 {
                self.degradeHideUnavailable()
            }
        }
    }

    private func degradeHideUnavailable() {
        guard !hideDegraded else { return }
        hideDegraded = true
        expand()
        if UserDefaults.standard.bool(forKey: "areSeparatorsHidden") {
            items?.alwaysHiddenItem?.length = expandedLength
        }
        NSLog("HideMechanism: degraded - macOS 27 hide unavailable (#360)")
        NotificationCenter.default.post(name: Notification.Name("legacyHideUnavailable"), object: nil)
        guard !UserDefaults.standard.bool(forKey: "didShowMacOS27HideUnavailableNotice") else { return }
        UserDefaults.standard.set(true, forKey: "didShowMacOS27HideUnavailableNotice")
        presentHideUnavailableAlert()
    }

    private func presentHideUnavailableAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Menu bar hiding isn't available on macOS 27", comment: "")
        alert.informativeText = NSLocalizedString("macOS 27 changed how the menu bar works, so Tuckaway can no longer hide other apps' icons by collapsing. This is a known limitation tracked on GitHub; Tuckaway will stay out of the way until a compatible method is available.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Learn More", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "https://github.com/Bruno-Alumn/Tuckaway/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}
