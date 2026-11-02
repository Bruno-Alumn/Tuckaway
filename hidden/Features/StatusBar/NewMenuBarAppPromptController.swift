//
//  NewMenuBarAppPromptController.swift
//  Tuckaway
//

import AppKit

// Asks, under the arrow, whether a new app's menu-bar icon should stay visible.
// A panel rather than an alert: it doesn't take focus from what the user is
// doing, and it waits until they answer.
final class NewMenuBarAppPromptController: NSObject {
    private let panel: NSPanel
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var onAnswer: ((Bool) -> Void)?
    private(set) var bundleIdentifier: String?

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
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

        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        messageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.preferredMaxLayoutWidth = 220

        let hide = NSButton(title: "Hide".localized, target: self, action: #selector(hideIt))
        let keep = NSButton(title: "Keep Visible".localized, target: self, action: #selector(keepVisible))
        keep.keyEquivalent = "\r"

        let text = NSStackView(views: [titleLabel, messageLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let top = NSStackView(views: [iconView, text])
        top.alignment = .top
        top.spacing = 10
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, hide, keep])
        buttons.spacing = 8
        let content = NSStackView(views: [top, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        background.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            buttons.widthAnchor.constraint(equalTo: top.widthAnchor),
        ])
        buttons.translatesAutoresizingMaskIntoConstraints = false

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

    // `onAnswer` gets true for Keep Visible, false for Hide.
    func show(bundleIdentifier: String, below arrowFrame: CGRect, on screen: NSScreen, onAnswer: @escaping (Bool) -> Void) {
        self.onAnswer = onAnswer
        self.bundleIdentifier = bundleIdentifier
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        let name = app?.localizedName ?? bundleIdentifier
        iconView.image = app?.icon
        titleLabel.stringValue = String(format: "Keep %@ visible?".localized, name)
        messageLabel.stringValue = "Its new menu bar icon landed on the hidden side, so Tuckaway is showing it until you choose.".localized

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 300, height: 100)
        let x = min(max(arrowFrame.midX - size.width / 2, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let y = screen.visibleFrame.maxY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        onAnswer = nil
        bundleIdentifier = nil
    }

    @objc private func keepVisible() {
        answer(true)
    }

    @objc private func hideIt() {
        answer(false)
    }

    private func answer(_ keep: Bool) {
        let onAnswer = self.onAnswer
        hide()
        onAnswer?(keep)
    }
}
