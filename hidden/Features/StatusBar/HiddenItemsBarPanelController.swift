//
//  HiddenItemsBarPanelController.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import ScreenCaptureKit

struct HiddenItemsBarCapture {
    let items: [HiddenItemsBarItem]
    let screen: NSScreen
    let separatorFrame: CGRect
    let menuBarOverlayFrame: CGRect
    let prefersDarkBackground: Bool
    // macOS 27 captures include the menu bar behind each icon. The panel is
    // filled with a sliver of that same capture, stretched, so the icons don't
    // look like tiles; a sampled color comes out a shade off.
    var backgroundImage: NSImage? = nil
}

struct HiddenItemsBarItem {
    let image: NSImage
    let sourceRect: CGRect
    let windowNumber: Int
    // The owning app, shown on hover and read by VoiceOver.
    var name: String? = nil
    var bundleIdentifier: String? = nil
}

final class HiddenItemsBarPanelController: NSObject {
    private let panel: NSPanel
    private let scrollView: NSScrollView
    private let contentView: HiddenItemsBarView

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        contentView = HiddenItemsBarView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        scrollView.documentView = contentView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        panel.contentView = scrollView
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = false
    }

    var frame: CGRect {
        panel.frame
    }

    // `menuProvider` builds the right-click menu for an icon; nil shows none.
    func show(capture: HiddenItemsBarCapture, menuProvider: ((HiddenItemsBarItem) -> NSMenu?)? = nil,
              clickHandler: @escaping (CGFloat) -> Void) {
        contentView.prefersDarkBackground = capture.prefersDarkBackground
        contentView.backgroundImage = capture.backgroundImage
        contentView.configure(items: capture.items, clickHandler: clickHandler)
        contentView.menuProvider = menuProvider
        contentView.startNamingHoveredIcon()

        let contentSize = contentView.preferredContentSize
        let panelWidth = max(160, min(contentSize.width, capture.screen.visibleFrame.width - 16))
        let needsHorizontalScroll = contentSize.width > panelWidth
        let scrollerHeight = needsHorizontalScroll ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay) : 0
        let panelHeight = max(28, contentSize.height + scrollerHeight)
        let screenFrame = capture.screen.frame
        let visibleFrame = capture.screen.visibleFrame
        let itemsMidX = capture.items.reduce(0) { $0 + $1.sourceRect.midX } / CGFloat(max(capture.items.count, 1))
        let centeredX = itemsMidX - panelWidth / 2
        let minX = screenFrame.minX + 8
        let maxX = screenFrame.maxX - panelWidth - 8
        let panelX = min(max(centeredX, minX), maxX)
        let panelY = max(visibleFrame.maxY - panelHeight - 4, visibleFrame.minY + 8)

        contentView.frame = NSRect(origin: .zero, size: contentSize)
        scrollView.hasHorizontalScroller = needsHorizontalScroll
        scrollView.frame = NSRect(origin: .zero, size: CGSize(width: panelWidth, height: panelHeight))
        panel.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        contentView.stopNamingHoveredIcon()
        panel.orderOut(nil)
    }
}

// Holds a still image of part of the menu bar over the real one, so the hidden
// icons macOS 27 shows for a capture or a click don't flash.
final class HiddenItemsBarFreezeController: NSObject {
    private let panel: NSPanel
    private let imageView = NSImageView(frame: .zero)

    override init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        imageView.imageScaling = .scaleAxesIndependently
        panel.contentView = imageView
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func show(_ image: CGImage, frame: CGRect) {
        imageView.image = NSImage(cgImage: image, size: frame.size)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        imageView.image = nil
    }
}

// Captures part of the menu bar. macOS 27 draws status items into the menu
// bar's own window, so per-item windows, which the older capture used, no
// longer exist.
@available(macOS 14.0, *)
enum MenuBarStripCapture {
    // `rect` is in Accessibility coordinates. Leaving out Tuckaway's own
    // windows lets the capture see past the still image covering the bar.
    // Completes on the main queue with the image and its pixels per point.
    static func image(of rect: CGRect, on display: MenuBarDisplay, excludingOwnWindows: Bool,
                      completion: @escaping (CGImage?, CGFloat) -> Void) {
        let finish = { (image: CGImage?, scale: CGFloat) in
            DispatchQueue.main.async { completion(image, scale) }
        }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let content,
                  let scDisplay = content.displays.first(where: { String($0.displayID) == display.identifier })
            else {
                NSLog("SeparateBar: no display to capture: \(error?.localizedDescription ?? "not listed")")
                return finish(nil, 1)
            }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let excluded = excludingOwnWindows ? content.applications.filter { $0.processID == ownPID } : []
            let filter = SCContentFilter(display: scDisplay, excludingApplications: excluded, exceptingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = rect.offsetBy(dx: -display.accessibilityFrame.minX, dy: -display.accessibilityFrame.minY)
            configuration.width = Int((rect.width * scale).rounded())
            configuration.height = Int((rect.height * scale).rounded())
            configuration.showsCursor = false
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let error {
                    NSLog("SeparateBar: capture failed: \(error.localizedDescription)")
                }
                finish(image, scale)
            }
        }
    }
}

final class HiddenItemsBarCaptureShieldController: NSObject {
    private let panel: NSPanel

    override init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
    }

    func show(on screen: NSScreen, near expandCollapseFrame: CGRect, covering hiddenSectionFrame: CGRect?) {
        let menuBarHeight = max(22, screen.frame.maxY - screen.visibleFrame.maxY)
        let shieldPadding: CGFloat = 12
        let fallbackWidth: CGFloat = 360
        let shieldFrame: CGRect

        if Constant.isUsingLTRLanguage {
            let minX = max(screen.frame.minX, hiddenSectionFrame?.minX ?? expandCollapseFrame.minX - fallbackWidth)
            shieldFrame = CGRect(
                x: minX,
                y: screen.frame.maxY - menuBarHeight,
                width: max(0, expandCollapseFrame.minX - minX + shieldPadding),
                height: menuBarHeight
            )
        } else {
            let maxX = min(screen.frame.maxX, hiddenSectionFrame?.maxX ?? expandCollapseFrame.maxX + fallbackWidth)
            shieldFrame = CGRect(
                x: expandCollapseFrame.maxX - shieldPadding,
                y: screen.frame.maxY - menuBarHeight,
                width: max(0, maxX - expandCollapseFrame.maxX + shieldPadding),
                height: menuBarHeight
            )
        }

        guard shieldFrame.width > 1 && shieldFrame.height > 1 else { return }
        panel.setFrame(shieldFrame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

final class HiddenItemsBarSeparatorOverlayController: NSObject {
    private let panel: NSPanel
    private let contentView: HiddenItemsBarSeparatorOverlayView

    override init() {
        contentView = HiddenItemsBarSeparatorOverlayView(frame: .zero)
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.contentView = contentView
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
    }

    func show(frame: CGRect, separatorFrame: CGRect, prefersDarkBackground: Bool) {
        guard frame.width > 1 && frame.height > 1 else {
            hide()
            return
        }

        contentView.frame = NSRect(origin: .zero, size: frame.size)
        contentView.separatorFrame = separatorFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        contentView.prefersDarkBackground = prefersDarkBackground
        contentView.needsDisplay = true
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

final class HiddenItemsBarSeparatorOverlayView: NSView {
    var separatorFrame: CGRect = .zero
    var prefersDarkBackground = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        overlayBackgroundColor.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: separatorColor,
            .font: NSFont.systemFont(ofSize: 18)
        ]
        let text = "|"
        let size = text.size(withAttributes: attributes)
        let targetFrame = separatorFrame.isEmpty ? bounds : separatorFrame
        text.draw(
            at: NSPoint(x: targetFrame.midX - size.width / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    private var overlayBackgroundColor: NSColor {
        prefersDarkBackground || isDarkAppearance ? NSColor.black : NSColor.windowBackgroundColor
    }

    private var separatorColor: NSColor {
        prefersDarkBackground || isDarkAppearance ? NSColor.white : NSColor.labelColor
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

final class HiddenItemsBarView: NSView {
    private enum Metrics {
        static let paddingX: CGFloat = 12
        static let paddingY: CGFloat = 5
        static let spacing: CGFloat = 2
        static let minItemHeight: CGFloat = 18
    }

    private var items: [HiddenItemsBarItem] = []
    private var itemRects: [CGRect] = []
    private var clickHandler: ((CGFloat) -> Void)?
    var menuProvider: ((HiddenItemsBarItem) -> NSMenu?)?
    var prefersDarkBackground = false
    var backgroundImage: NSImage?
    private let nameLabel = HiddenItemsBarNameLabel()
    private var hoveredIndex: Int?
    private var hoverTimer: Timer?
    // Kept for as long as the items: VoiceOver reads them after this returns.
    private var accessibilityItems: [HiddenItemsBarAccessibilityItem]?

    var preferredContentSize: CGSize {
        let itemWidth = items.reduce(CGFloat(0)) { $0 + max($1.image.size.width, 1) }
        let spacingWidth = CGFloat(max(items.count - 1, 0)) * Metrics.spacing
        let itemHeight = items.map { max($0.image.size.height, Metrics.minItemHeight) }.max() ?? Metrics.minItemHeight
        return CGSize(
            width: itemWidth + spacingWidth + Metrics.paddingX * 2,
            height: itemHeight + Metrics.paddingY * 2
        )
    }

    func configure(items: [HiddenItemsBarItem], clickHandler: @escaping (CGFloat) -> Void) {
        self.items = items
        itemRects = []
        self.clickHandler = clickHandler
        accessibilityItems = nil
        hideName()
        needsDisplay = true
    }

    // The panel never becomes active, so AppKit tooltips wouldn't show, and it
    // didn't get mouse-moved events either (measured on 27.2); the pointer is
    // polled while the row is open and the name goes in a label of its own.
    func startNamingHoveredIcon() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateHoveredIcon()
        }
    }

    func stopNamingHoveredIcon() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hideName()
    }

    private func updateHoveredIcon() {
        guard let window else { return hideName() }
        let location = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let rects = itemRects.isEmpty ? layoutItemRects() : itemRects
        let index = rects.firstIndex { $0.contains(location) }
        guard index != hoveredIndex else { return }
        hoveredIndex = index
        guard let index, let name = items[index].name else { return nameLabel.hide() }
        let iconOnScreen = window.convertToScreen(convert(rects[index], to: nil))
        nameLabel.show(name, below: CGRect(x: iconOnScreen.minX, y: window.frame.minY, width: iconOnScreen.width, height: 0))
    }

    func hideName() {
        hoveredIndex = nil
        nameLabel.hide()
    }

    override func rightMouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let rects = itemRects.isEmpty ? layoutItemRects() : itemRects
        guard let index = rects.firstIndex(where: { $0.contains(location) }),
              let menu = menuProvider?(items[index]) else { return }
        hideName()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // Each icon is a button for VoiceOver, named after its app.
    override func isAccessibilityElement() -> Bool {
        false
    }

    override func accessibilityChildren() -> [Any]? {
        if let accessibilityItems { return accessibilityItems }
        let rects = itemRects.isEmpty ? layoutItemRects() : itemRects
        let built = items.indices.compactMap { index -> HiddenItemsBarAccessibilityItem? in
            guard rects.indices.contains(index) else { return nil }
            let element = HiddenItemsBarAccessibilityItem()
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(items[index].name ?? "Hidden item".localized)
            element.setAccessibilityFrameInParentSpace(rects[index])
            let sourceX = items[index].sourceRect.midX
            element.press = { [weak self] in
                self?.clickHandler?(sourceX)
                return true
            }
            return element
        }
        accessibilityItems = built
        return built
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        if let backgroundImage {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            backgroundImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            panelBackgroundColor.setFill()
            path.fill()
        }

        let strokeColor = prefersDarkBackground ? NSColor.white.withAlphaComponent(0.28) : NSColor.separatorColor
        strokeColor.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()

        guard !items.isEmpty else {
            drawEmptyState()
            return
        }

        itemRects = layoutItemRects()
        for (index, item) in items.enumerated() {
            guard itemRects.indices.contains(index) else { continue }
            item.image.draw(in: itemRects[index], from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !items.isEmpty else { return }

        let location = convert(event.locationInWindow, from: nil)
        let rects = itemRects.isEmpty ? layoutItemRects() : itemRects
        guard let index = rects.firstIndex(where: { $0.contains(location) }) else { return }
        clickHandler?(items[index].sourceRect.midX)
    }

    private func layoutItemRects() -> [CGRect] {
        let contentSize = preferredContentSize
        var currentX = (bounds.width - (contentSize.width - Metrics.paddingX * 2)) / 2
        let itemHeight = contentSize.height - Metrics.paddingY * 2
        let originY = (bounds.height - itemHeight) / 2

        return items.map { item in
            let size = item.image.size
            let rect = CGRect(
                x: currentX,
                y: originY + (itemHeight - size.height) / 2,
                width: size.width,
                height: size.height
            )
            currentX += size.width + Metrics.spacing
            return rect
        }
    }

    private func drawEmptyState() {
        let text = "Hidden items unavailable".localized
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: prefersDarkBackground ? NSColor.white.withAlphaComponent(0.72) : NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    private var panelBackgroundColor: NSColor {
        if prefersDarkBackground {
            return NSColor.black.withAlphaComponent(0.88)
        }

        return NSColor.windowBackgroundColor.withAlphaComponent(0.92)
    }
}

private final class HiddenItemsBarAccessibilityItem: NSAccessibilityElement {
    var press: (() -> Bool)?

    override func accessibilityPerformPress() -> Bool {
        press?() ?? false
    }
}

// A small label, like a tooltip, under an icon in the hidden-items row.
private final class HiddenItemsBarNameLabel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 5
        background.layer?.masksToBounds = true
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        background.addSubview(label)
        panel.contentView = background
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func show(_ text: String, below anchor: CGRect) {
        label.stringValue = text
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 12, height: label.frame.height + 6)
        label.setFrameOrigin(NSPoint(x: 6, y: 3))
        panel.setFrame(NSRect(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 4,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
