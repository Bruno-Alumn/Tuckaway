import AppKit
import ApplicationServices

struct ManagedMenuBarItem {
    enum Section {
        case hidden
        case visible
    }

    let id: String
    let element: AXUIElement
    let appName: String
    let title: String
    let icon: NSImage?
    let position: CGPoint
    let size: CGSize
    let section: Section

    private var cleanedTitle: String? {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value != "-",
              !value.hasPrefix("Item-")
        else { return nil }
        return value
    }

    private var isSystemMenuExtra: Bool {
        appName == "Control Center" || appName == "SystemUIServer" || appName == "控制中心"
    }

    var primaryName: String {
        if isSystemMenuExtra, let cleanedTitle = cleanedTitle { return cleanedTitle }
        return appName
    }

    var secondaryName: String? {
        guard let cleanedTitle = cleanedTitle,
              cleanedTitle.caseInsensitiveCompare(primaryName) != .orderedSame
        else { return nil }
        return isSystemMenuExtra ? appName : cleanedTitle
    }

    var center: CGPoint {
        CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }
}

struct MenuBarManagementLayout {
    let separatorFrame: CGRect
    let expandCollapseFrame: CGRect
}

final class MenuBarItemManagerViewController: NSViewController {
    private struct AppSnapshot {
        let pid: pid_t
        let name: String
        let icon: NSImage?
    }

    private enum Drag {
        static let type = NSPasteboard.PasteboardType("com.brunoalumn.tuckaway.menu-item")
    }

    private let hiddenTable = NSTableView()
    private let visibleTable = NSTableView()
    private let hiddenCountLabel = NSTextField(labelWithString: "")
    private let visibleCountLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let hiddenEmptyLabel = NSTextField(labelWithString: "")
    private let visibleEmptyLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "Grant Access".localized, target: nil, action: nil)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private var hiddenItems: [ManagedMenuBarItem] = []
    private var visibleItems: [ManagedMenuBarItem] = []
    private var layout: MenuBarManagementLayout?
    private var isScanning = false

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 420))
        preferredContentSize = view.frame.size
        buildUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }

    private func buildUI() {
        let contentView = view

        let help = NSTextField(wrappingLabelWithString: "Drag items within a list to reorder them, or between lists to change visibility.".localized)
        help.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        help.textColor = .secondaryLabelColor

        configure(table: hiddenTable, identifier: "hidden")
        configure(table: visibleTable, identifier: "visible")

        let hiddenHeader = makeHeader(title: "Hidden".localized, symbol: "eye.slash", countLabel: hiddenCountLabel)
        let visibleHeader = makeHeader(title: "Visible".localized, symbol: "eye", countLabel: visibleCountLabel)
        let hiddenColumn = makeColumn(header: hiddenHeader, table: hiddenTable, emptyLabel: hiddenEmptyLabel)
        let visibleColumn = makeColumn(header: visibleHeader, table: visibleTable, emptyLabel: visibleEmptyLabel)
        let columns = NSStackView(views: [hiddenColumn, visibleColumn])
        columns.orientation = .horizontal
        columns.spacing = 12
        columns.distribution = .fillEqually

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh".localized)
        refreshButton.toolTip = "Refresh".localized
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)
        permissionButton.controlSize = .small
        permissionButton.bezelStyle = .rounded
        permissionButton.target = self
        permissionButton.action = #selector(permissionPressed)
        permissionButton.isHidden = true
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        let footer = NSStackView(views: [statusLabel, permissionButton, refreshButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        permissionButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)

        let root = NSStackView(views: [help, columns, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        columns.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 14),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            help.widthAnchor.constraint(equalTo: root.widthAnchor),
            columns.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        columns.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func configure(table: NSTableView, identifier: String) {
        table.identifier = NSUserInterfaceItemIdentifier(identifier)
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 30
        table.backgroundColor = .clear
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([Drag.type])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
    }

    private func makeHeader(title: String, symbol: String, countLabel: NSTextField) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        countLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        let spacer = NSView()
        let stack = NSStackView(views: [icon, label, spacer, countLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return stack
    }

    // Each list sits in a rounded, grouped-form style box; an empty list shows
    // a drop hint instead of blank rows.
    private func makeColumn(header: NSView, table: NSTableView, emptyLabel: NSTextField) -> NSView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.contentViewMargins = .zero
        box.contentView = scroll

        emptyLabel.stringValue = "Drop items here".localized
        emptyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.isHidden = true

        // The hint floats above the box rather than inside it, so the box's
        // content view can never draw over it.
        let list = NSView()
        for subview in [box, emptyLabel] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            list.addSubview(subview)
        }

        let stack = NSStackView(views: [header, list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        list.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            list.widthAnchor.constraint(equalTo: stack.widthAnchor),
            list.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            box.topAnchor.constraint(equalTo: list.topAnchor),
            box.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            box.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: list.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: list.centerYAnchor)
        ])
        return stack
    }

    @objc private func refreshPressed() {
        refresh()
    }

    @objc private func permissionPressed() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(prompt)
        statusLabel.stringValue = "Enable Tuckaway in System Settings, then return and refresh.".localized
    }

    private func refresh() {
        guard !isScanning,
              let appDelegate = NSApp.delegate as? AppDelegate
        else { return }
        isScanning = true
        permissionButton.isHidden = AXIsProcessTrusted()
        refreshButton.isEnabled = false
        statusLabel.stringValue = "Scanning menu bar items…".localized
        appDelegate.statusBarController.prepareForItemManagement { [weak self] layout in
            guard let self = self else { return }
            self.layout = layout
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.processIdentifier != ownPID }
                .map {
                    AppSnapshot(
                        pid: $0.processIdentifier,
                        name: $0.localizedName ?? "Unknown".localized,
                        icon: $0.icon
                    )
                }

            DispatchQueue.global(qos: .userInitiated).async {
                let found = Self.scanItems(layout: layout, apps: apps)
                DispatchQueue.main.async { [weak self] in
                    self?.apply(found: found, accessibilityTrusted: AXIsProcessTrusted())
                }
            }
        }
    }

    private static func scanItems(layout: MenuBarManagementLayout, apps: [AppSnapshot]) -> [ManagedMenuBarItem] {
        let separatorQuartzX = layout.separatorFrame.minX
        var found: [ManagedMenuBarItem] = []

        for app in apps {
            let axApp = AXUIElementCreateApplication(app.pid)
            var extrasValue: AnyObject?
            guard AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extrasValue) == .success,
                  let extras = extrasValue
            else { continue }

            var childrenValue: AnyObject?
            guard AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement]
            else { continue }

            for (index, element) in children.enumerated() {
                guard let position = pointAttribute(kAXPositionAttribute as CFString, of: element),
                      let size = sizeAttribute(kAXSizeAttribute as CFString, of: element),
                      size.width > 2, size.height > 2
                else { continue }
                let title = stringAttribute(kAXTitleAttribute as CFString, of: element)
                    ?? stringAttribute(kAXDescriptionAttribute as CFString, of: element)
                    ?? ""
                let section: ManagedMenuBarItem.Section = position.x + size.width / 2 < separatorQuartzX ? .hidden : .visible
                found.append(ManagedMenuBarItem(
                    id: "\(app.pid)-\(index)-\(Int(position.x))",
                    element: element,
                    appName: app.name,
                    title: title,
                    icon: app.icon,
                    position: position,
                    size: size,
                    section: section
                ))
            }
        }
        return found
    }

    private func apply(found: [ManagedMenuBarItem], accessibilityTrusted: Bool) {
        hiddenItems = found.filter { $0.section == .hidden }.sorted { $0.position.x < $1.position.x }
        visibleItems = found.filter { $0.section == .visible }.sorted { $0.position.x < $1.position.x }
        hiddenTable.reloadData()
        visibleTable.reloadData()
        hiddenCountLabel.stringValue = "\(hiddenItems.count)"
        visibleCountLabel.stringValue = "\(visibleItems.count)"
        hiddenEmptyLabel.isHidden = !hiddenItems.isEmpty
        visibleEmptyLabel.isHidden = !visibleItems.isEmpty
        if found.isEmpty, !accessibilityTrusted {
            statusLabel.stringValue = "Accessibility permission is required to list and move menu bar items.".localized
            permissionButton.isHidden = false
        } else {
            statusLabel.stringValue = found.isEmpty
                ? "No manageable menu bar items were found.".localized
                : "Drop an item to apply the real menu bar position.".localized
            permissionButton.isHidden = true
        }
        isScanning = false
        refreshButton.isEnabled = true
    }

    private static func pointAttribute(_ attribute: CFString, of element: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else { return nil }
        let axValue = rawValue as! AXValue
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeAttribute(_ attribute: CFString, of element: AXUIElement) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else { return nil }
        let axValue = rawValue as! AXValue
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func items(for table: NSTableView) -> [ManagedMenuBarItem] {
        table === hiddenTable ? hiddenItems : visibleItems
    }

    private func move(_ item: ManagedMenuBarItem, to table: NSTableView, row: Int) {
        guard let layout = layout else { return }
        let destination = items(for: table).filter { $0.id != item.id }
        let clampedRow = max(0, min(row, destination.count))
        let targetX: CGFloat
        if destination.isEmpty {
            targetX = table === hiddenTable
                ? layout.separatorFrame.minX - 12
                : layout.expandCollapseFrame.maxX + 12
        } else if clampedRow == destination.count {
            targetX = destination[destination.count - 1].center.x + 8
        } else {
            targetX = destination[clampedRow].center.x - 8
        }

        statusLabel.stringValue = String(format: "Moving %@…".localized, item.primaryName)
        refreshButton.isEnabled = false
        postCommandDrag(from: item.center, to: CGPoint(x: targetX, y: item.center.y)) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self?.refresh()
            }
        }
    }

    private func postCommandDrag(from source: CGPoint, to target: CGPoint, completion: @escaping () -> Void) {
        let sourcePoint = source
        let targetPoint = target
        let events: [(CGEventType, CGPoint)] = [
            (.mouseMoved, sourcePoint),
            (.leftMouseDown, sourcePoint),
            (.leftMouseDragged, targetPoint),
            (.leftMouseUp, targetPoint)
        ]
        for (index, eventSpec) in events.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                guard let event = CGEvent(mouseEventSource: nil, mouseType: eventSpec.0, mouseCursorPosition: eventSpec.1, mouseButton: .left) else { return }
                event.flags = .maskCommand
                event.post(tap: .cghidEventTap)
                if index == events.count - 1 { completion() }
            }
        }
    }
}

extension MenuBarItemManagerViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items(for: tableView).count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items(for: tableView)[row]
        let cell = NSTableCellView()
        let imageView = NSImageView()
        imageView.image = item.icon
        imageView.imageScaling = .scaleProportionallyDown
        let label = NSTextField(labelWithString: item.primaryName)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = NSTextField(labelWithString: item.secondaryName ?? "")
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        detail.isHidden = item.secondaryName == nil
        let stack = NSStackView(views: [imageView, label, detail])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(items(for: tableView)[row].id, forType: Drag.type)
        return pasteboardItem
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let id = info.draggingPasteboard.string(forType: Drag.type),
              let item = (hiddenItems + visibleItems).first(where: { $0.id == id })
        else { return false }
        move(item, to: tableView, row: row)
        return true
    }
}
