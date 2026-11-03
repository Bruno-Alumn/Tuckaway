//
//  WhatsNewWindowController.swift
//  Tuckaway
//

import AppKit

// The "What's New" window, shown once after an update. It is a plain window
// rather than an alert so the notes can be read at leisure and copied.
final class WhatsNewWindowController: NSWindowController {
    private static var sharedInstance: WhatsNewWindowController?
    private static let didShowKey = "lastSeenWhatsNewVersion"

    private let bodyView = NSScrollView()
    private let textView = NSTextView()

    private init(title: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        window.center()
        Self.sharedInstance = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Shows the notes once per version. Called at launch; the version is
    // recorded as seen even if the window is closed straight away, so it never
    // comes back for the same release.
    static func showIfNeeded(isFirstLaunch: Bool,
                             running: String? = Bundle.main.releaseVersionNumber,
                             defaults: UserDefaults = .standard) {
        let plan = WhatsNew.plan(notes: bundledNotes(), running: running,
                                 lastSeen: defaults.string(forKey: didShowKey),
                                 isFirstLaunch: isFirstLaunch)
        if let seen = plan.recordSeen {
            defaults.set(seen, forKey: didShowKey)
        }
        guard !plan.show.isEmpty else { return }
        let title = String(format: "What's New in Tuckaway %@".localized, running ?? "")
        let controller = sharedInstance ?? WhatsNewWindowController(title: title)
        controller.window?.title = title
        controller.setText(WhatsNew.plainText(plan.show))
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // The notes baked into this build; none in a Debug build.
    static func bundledNotes(bundle: Bundle = .main) -> [ReleaseNotes] {
        guard let url = bundle.url(forResource: WhatsNew.resourceName, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return WhatsNew.parse(text)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        bodyView.documentView = textView
        bodyView.hasVerticalScroller = true
        bodyView.autohidesScrollers = true
        bodyView.borderType = .noBorder
        bodyView.drawsBackground = false

        let done = NSButton(title: "Done".localized, target: self, action: #selector(closeWindow))
        done.keyEquivalent = "\r"
        done.bezelStyle = .rounded

        bodyView.translatesAutoresizingMaskIntoConstraints = false
        done.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bodyView)
        content.addSubview(done)
        NSLayoutConstraint.activate([
            bodyView.topAnchor.constraint(equalTo: content.topAnchor),
            bodyView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -10),
            done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            done.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    func setText(_ text: String) {
        textView.string = text
        textView.scrollToBeginningOfDocument(nil)
    }

    @objc private func closeWindow() {
        window?.close()
    }

    static var isVisible: Bool {
        guard let controller = sharedInstance, controller.isWindowLoaded else { return false }
        return controller.window?.isVisible ?? false
    }
}
