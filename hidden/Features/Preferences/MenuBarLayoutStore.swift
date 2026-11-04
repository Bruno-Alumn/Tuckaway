//
//  MenuBarLayoutStore.swift
//  Tuckaway
//

import AppKit

// macOS 27's MenuBarAgent keeps the menu bar's order as a table of weights in
// its own group container: larger is further left, Clock is 0. Keys are
// "status:<app>::<autosave name>", where <app> is the bundle identifier or the
// executable name, or "module:<name>" for MenuBarAgent's own items. Writing
// the table through cfprefsd reflows the bar at once, which synthesized ⌘-drags
// can't match (about one in four is lost on 27.2, and they can't pass
// Tuckaway's own arrow). The container is protected, so the user grants it
// once by choosing it in an open panel; the grant is kept as a bookmark.
final class MenuBarLayoutStore {
    static let shared = MenuBarLayoutStore()

    private static let bookmarkKey = "menuBarLayoutBookmark"
    private static let domain = "com.apple.MenuBar" as CFString
    private static let tableKey = "TrailingItemPreferredPositions" as CFString
    static let containerURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/com.apple.MenuBar", isDirectory: true)

    // CoreFoundation's container-aware preferences calls are private; without
    // them there is no store, and moves fall back to dragging.
    private typealias CopyValue = @convention(c) (CFString, CFString, CFString, CFString, CFString) -> Unmanaged<CFPropertyList>?
    private typealias SetValue = @convention(c) (CFString, CFPropertyList?, CFString, CFString, CFString, CFString) -> Void
    private typealias Synchronize = @convention(c) (CFString, CFString, CFString, CFString) -> DarwinBoolean
    private let copyValue: CopyValue?
    private let setValue: SetValue?
    private let synchronize: Synchronize?

    private var accessedURL: URL?

    private init() {
        let handle = dlopen(nil, RTLD_NOW)
        copyValue = dlsym(handle, "_CFPreferencesCopyValueWithContainer").map { unsafeBitCast($0, to: CopyValue.self) }
        setValue = dlsym(handle, "_CFPreferencesSetValueWithContainer").map { unsafeBitCast($0, to: SetValue.self) }
        synchronize = dlsym(handle, "_CFPreferencesSynchronizeWithContainer").map { unsafeBitCast($0, to: Synchronize.self) }
    }

    // Only the direct build on macOS 27 has a MenuBarAgent to write to.
    var isSupported: Bool {
        MenuBarEngineFactory.usesNativeVisibility && copyValue != nil && setValue != nil && synchronize != nil
    }

    // Whether the table can be read right now, resuming a saved grant first.
    var hasAccess: Bool {
        guard isSupported else { return false }
        if table() != nil { return true }
        resumeSavedAccess()
        return table() != nil
    }

    // Shows an open panel aimed at the container; macOS only lets an app into
    // it once the user has chosen it there.
    func requestAccess(for window: NSWindow?, completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.message = "Choose the “com.apple.MenuBar” folder to let Tuckaway arrange your menu bar.".localized
        panel.prompt = "Allow".localized
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Self.containerURL
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return completion(false) }
            completion(self.adopt(url))
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) } else { handle(panel.runModal()) }
    }

    // The table, or nil without access.
    func table() -> [String: Double]? {
        guard let copyValue else { return nil }
        let value = copyValue(Self.tableKey, Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost,
                              Self.containerURL.path as CFString)?.takeRetainedValue()
        guard let dictionary = value as? [String: Any], !dictionary.isEmpty else { return nil }
        return dictionary.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    // Merges `weights` into the table. MenuBarAgent applies it as cfprefsd
    // delivers it, unless a visibility restriction is held.
    func write(_ weights: [String: Double]) -> Bool {
        guard let setValue, let synchronize, var table = table() else { return false }
        table.merge(weights) { _, new in new }
        let container = Self.containerURL.path as CFString
        setValue(Self.tableKey, table as CFDictionary, Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)
        return synchronize(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container).boolValue
    }

    // MARK: - Access

    private func adopt(_ url: URL) -> Bool {
        guard url.standardizedFileURL.path.hasPrefix(Self.containerURL.standardizedFileURL.path) else { return false }
        startAccessing(url)
        guard table() != nil else { return false }
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        }
        return true
    }

    private func resumeSavedAccess() {
        guard accessedURL == nil, let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale)
        else { return }
        startAccessing(url)
    }

    private func startAccessing(_ url: URL) {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = url.startAccessingSecurityScopedResource() ? url : nil
    }
}
