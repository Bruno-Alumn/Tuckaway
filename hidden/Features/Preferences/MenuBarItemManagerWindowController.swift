import AppKit
import ApplicationServices

struct ManagedMenuBarItem {
    typealias Section = MenuBarSection

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

    func moved(to section: Section) -> ManagedMenuBarItem {
        ManagedMenuBarItem(id: id, element: element, appName: appName, title: title, icon: icon,
                           position: position, size: size, section: section)
    }
}

struct MenuBarManagementLayout {
    let separatorFrame: CGRect
    let expandCollapseFrame: CGRect
    // Nil while the always-hidden section is off.
    let alwaysHiddenFrame: CGRect?

    // Tuckaway's own item that bounds `section` on the right (Visible: the
    // arrow, on its left).
    func boundaryFrame(of section: MenuBarSection) -> CGRect? {
        switch section {
        case .alwaysHidden: return alwaysHiddenFrame
        case .hidden: return separatorFrame
        case .visible: return expandCollapseFrame
        }
    }
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

    private let tables = Dictionary(uniqueKeysWithValues: MenuBarSection.leftToRight.map { ($0, NSTableView()) })
    private let countLabels = Dictionary(uniqueKeysWithValues: MenuBarSection.leftToRight.map { ($0, NSTextField(labelWithString: "")) })
    private let emptyLabels = Dictionary(uniqueKeysWithValues: MenuBarSection.leftToRight.map { ($0, NSTextField(labelWithString: "")) })
    private var columnViews: [MenuBarSection: NSView] = [:]
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "Grant Access".localized, target: nil, action: nil)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private var itemsBySection: [MenuBarSection: [ManagedMenuBarItem]] = [:]
    private var layout: MenuBarManagementLayout?
    private var isScanning = false
    // Real menu-bar moves run one at a time, in drop order, off the main thread.
    private let moveQueue = DispatchQueue(label: "com.brunoalumn.tuckaway.item-moves")
    private var movesInFlight = 0

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 420))
        preferredContentSize = preferredSize
        buildUI()
    }

    // Three lists need more room than two.
    private var preferredSize: NSSize {
        NSSize(width: Preferences.alwaysHiddenSectionEnabled ? 640 : 480, height: 420)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = preferredSize
        columnViews[.alwaysHidden]?.isHidden = !Preferences.alwaysHiddenSectionEnabled
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        (NSApp.delegate as? AppDelegate)?.statusBarController.endItemManagement()
    }

    private func buildUI() {
        let contentView = view

        let help = NSTextField(wrappingLabelWithString: "Drag items within a list to reorder them, or between lists to change visibility.".localized)
        help.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        help.textColor = .secondaryLabelColor

        let headings: [MenuBarSection: (title: String, symbol: String)] = [
            .alwaysHidden: ("Always Hidden".localized, "eye.slash.circle"),
            .hidden: ("Hidden".localized, "eye.slash"),
            .visible: ("Visible".localized, "eye")
        ]
        for section in MenuBarSection.leftToRight {
            let table = tables[section]!
            configure(table: table, identifier: "\(section)")
            let header = makeHeader(title: headings[section]!.title, symbol: headings[section]!.symbol, countLabel: countLabels[section]!)
            columnViews[section] = makeColumn(header: header, table: table, emptyLabel: emptyLabels[section]!)
        }
        columnViews[.alwaysHidden]?.isHidden = !Preferences.alwaysHiddenSectionEnabled
        let columns = NSStackView(views: MenuBarSection.leftToRight.map { columnViews[$0]! })
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

    // `quiet` re-checks the real menu bar after a move without the scanning
    // status, and leaves the lists alone unless they turned out to be wrong.
    private func refresh(quiet: Bool = false) {
        guard !isScanning,
              let appDelegate = NSApp.delegate as? AppDelegate
        else { return }
        isScanning = true
        if !quiet {
            permissionButton.isHidden = AXIsProcessTrusted()
            refreshButton.isEnabled = false
            statusLabel.stringValue = "Scanning menu bar items…".localized
        }
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
                    guard let self else { return }
                    // A drop that landed while scanning makes this result stale.
                    if quiet && self.movesInFlight > 0 {
                        self.isScanning = false
                        return
                    }
                    self.apply(found: found, accessibilityTrusted: AXIsProcessTrusted(), onlyIfChanged: quiet)
                }
            }
        }
    }

    private static func scanItems(layout: MenuBarManagementLayout, apps: [AppSnapshot]) -> [ManagedMenuBarItem] {
        var perApp = [[ManagedMenuBarItem]](repeating: [], count: apps.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let found = scanItems(of: apps[index], layout: layout)
            lock.lock()
            perApp[index] = found
            lock.unlock()
        }
        return perApp.flatMap { $0 }
    }

    private static func scanItems(of app: AppSnapshot, layout: MenuBarManagementLayout) -> [ManagedMenuBarItem] {
        var found: [ManagedMenuBarItem] = []
        let axApp = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        var extrasValue: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extrasValue) == .success,
              let extras = extrasValue,
              CFGetTypeID(extras) == AXUIElementGetTypeID()
        else { return found }

        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return found }

        for (index, element) in children.enumerated() {
            guard let position = pointAttribute(kAXPositionAttribute as CFString, of: element),
                  let size = sizeAttribute(kAXSizeAttribute as CFString, of: element),
                  size.width > 2, size.height > 2
            else { continue }
            let title = stringAttribute(kAXTitleAttribute as CFString, of: element)
                ?? stringAttribute(kAXDescriptionAttribute as CFString, of: element)
                ?? ""
            let section = MenuBarSection.of(centerX: position.x + size.width / 2,
                                            hiddenBoundaryX: layout.separatorFrame.minX,
                                            alwaysHiddenBoundaryX: layout.alwaysHiddenFrame?.minX)
            found.append(ManagedMenuBarItem(
                id: "\(app.pid)-\(index)",
                element: element,
                appName: app.name,
                title: title,
                icon: app.icon,
                position: position,
                size: size,
                section: section
            ))
        }
        return found
    }

    private func apply(found: [ManagedMenuBarItem], accessibilityTrusted: Bool, onlyIfChanged: Bool = false) {
        var newItems: [MenuBarSection: [ManagedMenuBarItem]] = [:]
        for section in MenuBarSection.leftToRight {
            newItems[section] = found.filter { $0.section == section }.sorted { $0.position.x < $1.position.x }
        }
        let changed = MenuBarSection.leftToRight.contains { section in
            newItems[section, default: []].map(\.id) != itemsBySection[section, default: []].map(\.id)
        }
        // Fresh frames either way, so the next move aims at where items really are.
        itemsBySection = newItems
        if changed || !onlyIfChanged {
            tables.values.forEach { $0.reloadData() }
        }
        updateCounts()
        if found.isEmpty, !accessibilityTrusted {
            statusLabel.stringValue = "Accessibility permission is required to list and move menu bar items.".localized
            permissionButton.isHidden = false
        } else {
            // A quiet re-check keeps any message a failed move just showed.
            if !onlyIfChanged || found.isEmpty {
                statusLabel.stringValue = found.isEmpty
                    ? "No manageable menu bar items were found.".localized
                    : "Drop an item to apply the real menu bar position.".localized
            }
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

    private func section(of table: NSTableView) -> MenuBarSection {
        tables.first { $0.value === table }!.key
    }

    private func items(for table: NSTableView) -> [ManagedMenuBarItem] {
        itemsBySection[section(of: table), default: []]
    }

    private var allItems: [ManagedMenuBarItem] {
        MenuBarSection.leftToRight.flatMap { itemsBySection[$0, default: []] }
    }

    private func updateCounts() {
        for section in MenuBarSection.leftToRight {
            let count = itemsBySection[section, default: []].count
            countLabels[section]?.stringValue = "\(count)"
            emptyLabels[section]?.isHidden = count > 0
        }
    }

    // Updates the lists at once, then makes the real menu bar match in the
    // background. A quiet re-scan afterwards corrects the lists if macOS put
    // the item somewhere else.
    private func move(_ item: ManagedMenuBarItem, to table: NSTableView, row: Int) {
        let toSection = section(of: table)
        let fromTable = tables[item.section]!
        let destinationIDs = MenuBarItemMovePlan.inserting(item.id, into: items(for: table).map(\.id), aboveRow: row)
        guard let newIndex = destinationIDs.firstIndex(of: item.id) else { return }
        let oldIndex = items(for: fromTable).firstIndex { $0.id == item.id }
        if fromTable === table && oldIndex == newIndex { return }

        let movedItem = item.moved(to: toSection)
        let lookup = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let destination = destinationIDs.compactMap { $0 == item.id ? movedItem : lookup[$0] }
        let anchor = MenuBarItemMovePlan.anchor(for: item.id, in: destinationIDs)
        let anchorElement: AXUIElement? = {
            switch anchor {
            case .before(let id), .after(let id): return lookup[id]?.element
            case .emptyList: return nil
            }
        }()

        if fromTable === table {
            setItems(destination, for: table)
            if let oldIndex { table.moveRow(at: oldIndex, to: newIndex) }
        } else {
            setItems(items(for: fromTable).filter { $0.id != item.id }, for: fromTable)
            setItems(destination, for: table)
            if let oldIndex { fromTable.removeRows(at: IndexSet(integer: oldIndex), withAnimation: .effectFade) }
            table.insertRows(at: IndexSet(integer: newIndex), withAnimation: .effectGap)
        }
        updateCounts()

        movesInFlight += 1
        let element = item.element
        // An empty list has no neighbour; aim at Tuckaway's own boundary item
        // instead: the always-hidden separator for Always Hidden, the separator
        // (or, on macOS 27, the arrow) for Hidden, the arrow for Visible.
        let side: MenuBarDropSide
        switch anchor {
        case .before: side = .before
        case .after: side = .after
        case .emptyList: side = toSection.emptyListSide
        }
        moveQueue.async { [weak self] in
            let settled = MenuBarItemDragger.move(element, side, of: anchorElement) {
                DispatchQueue.main.sync {
                    let layout = (NSApp.delegate as? AppDelegate)?.statusBarController.currentManagementLayout()
                    return layout?.boundaryFrame(of: toSection)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.movesInFlight -= 1
                if !settled {
                    self.statusLabel.stringValue = String(format: "Couldn’t place %@ exactly; the lists show where it ended up.".localized, item.primaryName)
                }
                if self.movesInFlight == 0 {
                    self.refresh(quiet: true)
                }
            }
        }
    }

    private func setItems(_ items: [ManagedMenuBarItem], for table: NSTableView) {
        itemsBySection[section(of: table)] = items
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
              let item = allItems.first(where: { $0.id == id })
        else { return false }
        move(item, to: tableView, row: row)
        return true
    }
}
