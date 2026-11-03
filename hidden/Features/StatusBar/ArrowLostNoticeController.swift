//
//  ArrowLostNoticeController.swift
//  Tuckaway
//

import AppKit

// Shown when Tuckaway's arrow has been off screen enough times that repairing it
// can't be trusted: the app is running but its only control is somewhere the user
// can't click. A panel rather than an alert, like the other notices under the
// arrow, so it appears where the arrow should have been.
final class ArrowLostNoticeController: NSObject {
    struct Actions {
        let repair: () -> Void
        let openSettings: () -> Void
        let quit: () -> Void
        let notNow: () -> Void
    }

    private let panel: NSPanel
    private var actions: Actions?

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemOrange
        let title = NSTextField(labelWithString: "Tuckaway can't be reached".localized)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let message = NSTextField(wrappingLabelWithString:
            "The menu bar left no room for the arrow, so it is off screen. Repair Menu Bar puts it back near the right side of the bar.".localized)
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth = 240

        let repair = NSButton(title: "Repair Menu Bar".localized, target: self, action: #selector(repairPressed))
        let settings = NSButton(title: "Settings…".localized, target: self, action: #selector(settingsPressed))
        let quit = NSButton(title: "Quit Tuckaway".localized, target: self, action: #selector(quitPressed))
        let notNow = NSButton(title: "Later".localized, target: self, action: #selector(notNowPressed))
        notNow.keyEquivalent = "\u{1b}"
        for button in [repair, settings, quit, notNow] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        repair.keyEquivalent = "\r"

        let text = NSStackView(views: [title, message])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        let top = NSStackView(views: [icon, text])
        top.alignment = .top
        top.spacing = 10
        let buttons = NSStackView(views: [repair, settings, quit, notNow])
        buttons.spacing = 8
        let content = NSStackView(views: [top, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        background.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
        ])

        panel.contentView = background
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
    }

    func show(below arrowFrame: CGRect, on screen: NSScreen, actions: Actions) {
        self.actions = actions
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 320, height: 120)
        let x = min(max(arrowFrame.midX - size.width / 2, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let y = screen.visibleFrame.maxY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        actions = nil
    }

    @objc private func repairPressed() {
        let repair = actions?.repair
        hide()
        repair?()
    }

    @objc private func settingsPressed() {
        let openSettings = actions?.openSettings
        hide()
        openSettings?()
    }

    @objc private func notNowPressed() {
        let notNow = actions?.notNow
        hide()
        notNow?()
    }

    @objc private func quitPressed() {
        let quit = actions?.quit
        hide()
        quit?()
    }
}
