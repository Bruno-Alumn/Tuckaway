//
//  HiddenIconSearchController.swift
//  Tuckaway
//

import AppKit

// Find Hidden Icon: a small panel under the arrow that lists the hidden icons
// by name. Typing filters the list, the arrow keys move the selection, Return
// opens the selected icon and Esc closes the panel. It shows names and app
// icons rather than captures, so it needs no Screen Recording.
final class HiddenIconSearchController: NSObject, NSSearchFieldDelegate, NSWindowDelegate {
    struct Entry {
        let name: String
        let icon: NSImage?
        // The icon's Accessibility frame, where the click goes.
        let frame: CGRect
    }

    private static let maxRows = 8
    private static let rowHeight: CGFloat = 26
    private static let width: CGFloat = 280

    private let panel: SearchPanel
    private let searchField = NSSearchField()
    private let rows = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var entries: [Entry] = []
    private var shown: [Entry] = []
    private var selection = 0
    private var onOpen: ((Entry) -> Void)?

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
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

        searchField.placeholderString = "Search hidden icons".localized
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let content = NSStackView(views: [searchField, rows, emptyLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        background.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            searchField.widthAnchor.constraint(equalToConstant: Self.width - 20),
            rows.widthAnchor.constraint(equalTo: searchField.widthAnchor),
        ])

        panel.contentView = background
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
    }

    func show(entries: [Entry], below arrowFrame: CGRect, on screen: NSScreen, onOpen: @escaping (Entry) -> Void) {
        self.entries = entries
        self.onOpen = onOpen
        searchField.stringValue = ""
        emptyLabel.stringValue = "No hidden icons".localized
        update()
        place(below: arrowFrame, on: screen)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        panel.orderOut(nil)
        onOpen = nil
    }

    private func place(below arrowFrame: CGRect, on screen: NSScreen) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: Self.width, height: 100)
        let x = min(max(arrowFrame.midX - size.width / 2, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let top = screen.visibleFrame.maxY - 6
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func update() {
        shown = Array(HiddenIconSearch.matches(entries, query: searchField.stringValue, name: \.name).prefix(Self.maxRows))
        selection = min(selection, max(shown.count - 1, 0))
        if searchField.stringValue.isEmpty == false || entries.isEmpty {
            selection = 0
        }
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, entry) in shown.enumerated() {
            rows.addArrangedSubview(row(for: entry, index: index))
        }
        emptyLabel.isHidden = !shown.isEmpty
        if !entries.isEmpty {
            emptyLabel.stringValue = "No matches".localized
        }
        // Keep the top edge under the menu bar while the list changes height.
        if panel.isVisible {
            let top = panel.frame.maxY
            panel.contentView?.layoutSubtreeIfNeeded()
            let size = panel.contentView?.fittingSize ?? panel.frame.size
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
        }
    }

    private func row(for entry: Entry, index: Int) -> NSView {
        let button = NSButton(title: entry.name, image: entry.icon ?? NSImage(), target: self, action: #selector(rowClicked(_:)))
        button.tag = index
        button.isBordered = false
        button.imagePosition = entry.icon == nil ? .noImage : .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.alignment = .left
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = index == selection ? NSColor.selectedContentBackgroundColor.cgColor : nil
        button.contentTintColor = index == selection ? .alternateSelectedControlTextColor : nil
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            button.widthAnchor.constraint(equalToConstant: Self.width - 20),
        ])
        button.image?.size = NSSize(width: 18, height: 18)
        return button
    }

    @objc private func rowClicked(_ sender: NSButton) {
        selection = sender.tag
        open()
    }

    private func open() {
        guard shown.indices.contains(selection) else { return }
        let entry = shown[selection]
        let onOpen = self.onOpen
        hide()
        onOpen?(entry)
    }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        selection = 0
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            selection = min(selection + 1, max(shown.count - 1, 0))
            update()
        case #selector(NSResponder.moveUp(_:)):
            selection = max(selection - 1, 0)
            update()
        case #selector(NSResponder.insertNewline(_:)):
            open()
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
        default:
            return false
        }
        return true
    }

    // MARK: NSWindowDelegate

    // Clicking anywhere else closes it, like a menu.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

// Borderless panels can't become key by default, and the search field needs
// the keyboard.
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
