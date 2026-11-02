//
//  ViewController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa
import Carbon
import HotKey
import SwiftUI
import UniformTypeIdentifiers

// The General tab. The storyboard scene only provides the (empty) view the
// tab controller displays; the content is the SwiftUI settings view below.
class PreferencesViewController: NSViewController {

    private let model = GeneralSettingsModel()
    private var shortcutMonitor: Any?

    public var listening = false {
        didSet {
            model.isRecordingShortcut = listening
            if listening {
                startShortcutMonitor()
            } else if let shortcutMonitor {
                NSEvent.removeMonitor(shortcutMonitor)
                self.shortcutMonitor = nil
            }
        }
    }

    //MARK: - VC Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        model.onRecordShortcut = { [weak self] kind in self?.register(kind) }
        model.onClearShortcut = { [weak self] kind in self?.unregister(kind) }
        model.shortcutTitle = Preferences.globalKey?.description
        model.presentationShortcutTitle = Preferences.presentationModeKey?.description
        model.findShortcutTitle = Preferences.findHiddenIconKey?.description
        model.refreshProfiles()

        preferredContentSize = NSSize(width: 480, height: 560)
        let hostingView = NSHostingView(rootView: GeneralSettingsView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        NotificationCenter.default.addObserver(model, selector: #selector(GeneralSettingsModel.refresh), name: .prefsChanged, object: nil)
        NotificationCenter.default.addObserver(model, selector: #selector(GeneralSettingsModel.refresh), name: .accessibilityPermissionChanged, object: nil)
        NotificationCenter.default.addObserver(model, selector: #selector(GeneralSettingsModel.refresh), name: .profileChanged, object: nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        model.refresh()
    }

    deinit {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        // Balance the viewDidLoad observers (PRs #335/#346).
        NotificationCenter.default.removeObserver(model)
        NotificationCenter.default.removeObserver(self)
    }

    static func initWithStoryboard() -> PreferencesViewController {
        let vc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "prefVC") as! PreferencesViewController
        return vc
    }

    //MARK: - Global shortcut
    // Recording goes through the window controller, which forwards keyDown and
    // flagsChanged here while `listening` is set.

    private func register(_ kind: ShortcutKind) {
        model.recordingKind = kind
        listening = true
    }

    private func startShortcutMonitor() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.listening, self.view.window?.isKeyWindow == true else { return event }
            if event.type == .flagsChanged {
                self.updateModiferFlags(event)
                return event
            }
            if event.keyCode == 53 { // Escape
                self.cancelShortcutRecording()
            } else {
                self.updateGlobalShortcut(event)
            }
            return nil
        }
    }

    func cancelShortcutRecording() {
        listening = false
    }

    // Clear the shortcut and tell AppDelegate to stop listening to the previous keybind.
    private func unregister(_ kind: ShortcutKind) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        listening = false
        switch kind {
        case .toggle:
            appDelegate.hotKey = nil
            model.shortcutTitle = nil
            Preferences.globalKey = nil
        case .presentation:
            appDelegate.presentationHotKey = nil
            model.presentationShortcutTitle = nil
            Preferences.presentationModeKey = nil
        case .find:
            appDelegate.findHotKey = nil
            model.findShortcutTitle = nil
            Preferences.findHiddenIconKey = nil
        case .profile(let name):
            Preferences.profileShortcuts[name] = nil
            appDelegate.registerProfileHotKeys()
            model.refreshProfiles()
        }
    }

    public func updateGlobalShortcut(_ event: NSEvent) {
        self.listening = false

        guard let characters = event.charactersIgnoringModifiers else {return}

        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: event.modifierFlags.carbonFlags,
            characters: characters,
            keyCode: uint32(event.keyCode))

        // Reject unmodified typing without deleting the existing shortcut.
        // Function keys are valid standalone global shortcuts.
        guard newGlobalKeybind.isValidGlobalShortcut else { return }

        // Two of Tuckaway's shortcuts on the same keys: only one would fire.
        if ShortcutKind.conflicts(newGlobalKeybind, recording: model.recordingKind, with: ShortcutKind.saved) {
            NSSound.beep()
            return
        }

        // Release the old hotkey first: registering the same keys again while
        // it's still held can fail, and the shortcut would then be dead.
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        let combo = KeyCombo(carbonKeyCode: UInt32(event.keyCode), carbonModifiers: event.modifierFlags.carbonFlags)
        switch model.recordingKind {
        case .toggle:
            appDelegate.hotKey = nil
            Preferences.globalKey = newGlobalKeybind
            model.shortcutTitle = newGlobalKeybind.description
            appDelegate.hotKey = HotKey(keyCombo: combo)
        case .presentation:
            appDelegate.presentationHotKey = nil
            Preferences.presentationModeKey = newGlobalKeybind
            model.presentationShortcutTitle = newGlobalKeybind.description
            appDelegate.presentationHotKey = HotKey(keyCombo: combo)
        case .find:
            appDelegate.findHotKey = nil
            Preferences.findHiddenIconKey = newGlobalKeybind
            model.findShortcutTitle = newGlobalKeybind.description
            appDelegate.findHotKey = HotKey(keyCombo: combo)
        case .profile(let name):
            Preferences.profileShortcuts[name] = newGlobalKeybind
            appDelegate.registerProfileHotKeys()
            model.refreshProfiles()
        }
    }

    // Shows the modifiers held so far while recording.
    public func updateModiferFlags(_ event: NSEvent) {
        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: 0,
            characters: nil,
            keyCode: uint32(event.keyCode))

        model.recordingPreview = newGlobalKeybind.description
    }
}

//MARK: - Model

// Reads straight from Preferences, so a change made elsewhere (the context
// menu's auto-collapse toggle, a failed login-item update) shows up on refresh.
enum ShortcutKind: Equatable {
    case toggle, presentation, find
    case profile(String)

    // Every shortcut Tuckaway has saved, profiles' included.
    static var saved: [(ShortcutKind, GlobalKeybindPreferences)] {
        let fixed: [(ShortcutKind, GlobalKeybindPreferences?)] = [
            (.toggle, Preferences.globalKey), (.presentation, Preferences.presentationModeKey), (.find, Preferences.findHiddenIconKey),
        ]
        return fixed.compactMap { kind, key in key.map { (kind, $0) } }
            + Preferences.profileShortcuts.map { (.profile($0.key), $0.value) }
    }

    // Whether `shortcut` is already another one's keys. Re-recording the same
    // shortcut onto its own keys is fine.
    static func conflicts(_ shortcut: GlobalKeybindPreferences, recording: ShortcutKind,
                          with saved: [(ShortcutKind, GlobalKeybindPreferences)]) -> Bool {
        saved.contains { $0.0 != recording && $0.1.isSameCombo(as: shortcut) }
    }
}

final class GeneralSettingsModel: ObservableObject {
    @Published var isRecordingShortcut = false {
        didSet { if !isRecordingShortcut { recordingPreview = "" } }
    }
    // Which of the two shortcuts is being recorded.
    @Published var recordingKind = ShortcutKind.toggle
    @Published var recordingPreview = ""
    @Published var shortcutTitle: String?
    @Published var presentationShortcutTitle: String?
    @Published var findShortcutTitle: String?
    // Profile names in menu order, and each one's shortcut.
    @Published private(set) var profileNames: [String] = []
    @Published private(set) var profileShortcutTitles: [String: String] = [:]
    @Published private(set) var profileApps: [String: [String]] = [:]
    @Published private(set) var profileSchedules: [String: ProfileSchedule] = [:]
    @Published private(set) var profileAppTriggers: [String: String] = [:]
    @Published private(set) var isAccessibilityPermissionMissing = Util.isAccessibilityPermissionMissing
    @Published private(set) var clockDropsDate = GeneralSettingsModel.readClockDropsDate()

    var onRecordShortcut: (ShortcutKind) -> Void = { _ in }
    var onClearShortcut: (ShortcutKind) -> Void = { _ in }

    @objc func refresh() {
        isAccessibilityPermissionMissing = Util.isAccessibilityPermissionMissing
        clockDropsDate = Self.readClockDropsDate()
        refreshProfiles()
        objectWillChange.send()
    }

    private static func readClockDropsDate() -> Bool {
        ClockDateSetting.dropsDateWhileCollapsed(hidesWithSeparator: !MenuBarEngineFactory.usesNativeVisibility)
    }

    func refreshProfiles() {
        let profiles = StatusBarController.supportsPresentationMode ? UserDefaultsMenuBarProfilesStore().profiles : MenuBarProfiles()
        profileNames = profiles.names
        profileApps = profiles.profiles
        profileSchedules = profiles.schedules
        profileAppTriggers = profiles.appTriggers
        profileShortcutTitles = Preferences.profileShortcuts.mapValues(\.description)
    }

    private var statusBarController: StatusBarController? {
        (NSApp.delegate as? AppDelegate)?.statusBarController
    }

    func renameProfile(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "Rename this profile".localized
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = name
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename".localized)
        alert.addButton(withTitle: "Cancel".localized)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != name else { return }
        if statusBarController?.renameProfile(name, to: newName) != true {
            Self.inform(String(format: "A profile named “%@” already exists.".localized, newName))
        }
    }

    func updateProfileToCurrentLayout(_ name: String) {
        statusBarController?.updateProfileToCurrentLayout(name) { updated in
            if !updated { NSSound.beep() }
        }
    }

    // An alert with a checkbox and two time pickers. Turning the checkbox off
    // removes the schedule.
    func scheduleProfile(_ name: String) {
        let current = profileSchedules[name]
        let alert = NSAlert()
        alert.messageText = String(format: "Use “%@” at set times".localized, name)
        alert.informativeText = "Tuckaway switches to this profile when the time starts, and back to the one you were using when it ends. A profile you pick in between stays.".localized
        let enabled = NSButton(checkboxWithTitle: "Switch automatically".localized, target: nil, action: nil)
        enabled.state = current == nil ? .off : .on
        let from = Self.timePicker(minute: current?.start ?? 9 * 60)
        let to = Self.timePicker(minute: current?.end ?? 17 * 60)
        let times = NSStackView(views: [NSTextField(labelWithString: "From".localized), from,
                                        NSTextField(labelWithString: "To".localized), to])
        times.spacing = 6
        let stack = NSStackView(views: [enabled, times])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 56)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Save".localized)
        alert.addButton(withTitle: "Cancel".localized)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let schedule = enabled.state == .on ? ProfileSchedule(start: Self.minute(of: from), end: Self.minute(of: to)) : nil
        statusBarController?.setSchedule(schedule, forProfile: name)
    }

    // Picks the app whose being open switches to this profile.
    func chooseTriggerApp(_ name: String) {
        let panel = NSOpenPanel()
        panel.message = String(format: "Choose an app. While it's open, Tuckaway uses “%@”.".localized, name)
        panel.prompt = "Choose".localized
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url)?.bundleIdentifier else { return NSSound.beep() }
        statusBarController?.setAppTrigger(bundle, forProfile: name)
    }

    func clearTriggerApp(_ name: String) {
        statusBarController?.setAppTrigger(nil, forProfile: name)
    }

    private static func timePicker(minute: Int) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerElements = .hourMinute
        picker.datePickerStyle = .textFieldAndStepper
        picker.dateValue = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return picker
    }

    private static func minute(of picker: NSDatePicker) -> Int {
        let time = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
        return (time.hour ?? 0) * 60 + (time.minute ?? 0)
    }

    // "9:00 AM – 5:00 PM" in the user's time format.
    static func describe(_ schedule: ProfileSchedule) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = { (minute: Int) in
            Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()).map(formatter.string(from:)) ?? ""
        }
        return "\(time(schedule.start)) – \(time(schedule.end))"
    }

    func removeApp(_ bundle: String, fromProfile name: String) {
        statusBarController?.removeApp(bundle, fromProfile: name)
    }

    func deleteProfile(_ name: String) {
        let confirm = NSAlert()
        confirm.messageText = String(format: "Delete the profile “%@”?".localized, name)
        confirm.addButton(withTitle: "Delete".localized)
        confirm.addButton(withTitle: "Cancel".localized)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        statusBarController?.deleteProfile(named: name)
    }

    // An app's name as Finder shows it, or its bundle ID if it isn't installed.
    static func appName(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func binding(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        return Binding(get: get, set: { [weak self] value in
            set(value)
            self?.objectWillChange.send()
        })
    }

    var autoStart: Binding<Bool> {
        return binding({ Preferences.isAutoStart }) { wanted in
            Preferences.isAutoStart = wanted
            // On failure the pref reverts; tell the user why instead of swallowing the error.
            if Preferences.isAutoStart != wanted {
                let alert = NSAlert()
                alert.messageText = "Could not update the login item".localized
                alert.informativeText = "Check System Settings > General > Login Items and make sure Tuckaway is allowed.".localized
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    var showPreferencesOnLaunch: Binding<Bool> {
        return binding({ Preferences.isShowPreference }) { Preferences.isShowPreference = $0 }
    }

    var autoHide: Binding<Bool> {
        return binding({ Preferences.isAutoHide }) { Preferences.isAutoHide = $0 }
    }

    var showHiddenIconCount: Binding<Bool> {
        return binding({ Preferences.showHiddenIconCount }) { Preferences.showHiddenIconCount = $0 }
    }

    var collapseWhenLocked: Binding<Bool> {
        return binding({ Preferences.collapseWhenLocked }) { Preferences.collapseWhenLocked = $0 }
    }

    var autoCollapseOnFocusChange: Binding<Bool> {
        return binding({ Preferences.autoCollapseOnFocusChange }) { Preferences.autoCollapseOnFocusChange = $0 }
    }

    var autoHideDelay: Binding<Int> {
        return Binding(get: { SelectedSecond.secondToPossition(seconds: Preferences.numberOfSecondForAutoHide) },
                       set: { [weak self] index in
                           if let seconds = SelectedSecond(rawValue: index)?.toSeconds() {
                               Preferences.numberOfSecondForAutoHide = seconds
                           }
                           self?.objectWillChange.send()
                       })
    }

    var showActiveAppIcon: Binding<Bool> {
        return binding({ Preferences.showActiveAppIcon }) { Preferences.showActiveAppIcon = $0 }
    }

    var hoverToExpand: Binding<Bool> {
        return binding({ Preferences.hoverToExpand }) { Preferences.hoverToExpand = $0 }
    }

    var clickEmptyMenuBarToToggle: Binding<Bool> {
        return binding({ Preferences.clickEmptyMenuBarToToggle }) { Preferences.clickEmptyMenuBarToToggle = $0 }
    }

    var expandWhenExternalDisplayConnected: Binding<Bool> {
        return binding({ Preferences.expandWhenExternalDisplayConnected }) { Preferences.expandWhenExternalDisplayConnected = $0 }
    }

    var useFullMenuBar: Binding<Bool> {
        return binding({ Preferences.useFullStatusBarOnExpandEnabled }) { Preferences.useFullStatusBarOnExpandEnabled = $0 }
    }

    var alwaysHiddenSection: Binding<Bool> {
        return binding({ Preferences.alwaysHiddenSectionEnabled }) { Preferences.alwaysHiddenSectionEnabled = $0 }
    }

    var notchOverflow: Binding<Bool> {
        return binding({ Preferences.notchOverflowEnabled }) { Preferences.notchOverflowEnabled = $0 }
    }

    var expandIconStyle: Binding<ExpandIconStyle> {
        return Binding(get: { Preferences.expandIconStyle }, set: { [weak self] value in
            Preferences.expandIconStyle = value
            self?.objectWillChange.send()
        })
    }

    // Read from the system each time, so a change made in Terminal shows up.
    var iconSpacing: Binding<MenuBarItemSpacing> {
        return Binding(get: { MenuBarItemSpacing.current() }, set: { [weak self] level in
            MenuBarItemSpacing.apply(level)
            self?.objectWillChange.send()
        })
    }

    var revealUpdatedApps: Binding<Bool> {
        return binding({ Preferences.revealUpdatedApps }) { Preferences.revealUpdatedApps = $0 }
    }

    var revealIconsOnActivity: Binding<Bool> {
        return binding({ Preferences.revealIconsOnActivity }) { Preferences.revealIconsOnActivity = $0 }
    }

    var spacerCount: Binding<Int> {
        return Binding(get: { Preferences.spacerCount },
                       set: { [weak self] in Preferences.spacerCount = $0; self?.objectWillChange.send() })
    }

    var spacerWidth: Binding<MenuBarSpacers.Width> {
        return Binding(get: { Preferences.spacerWidth },
                       set: { [weak self] in Preferences.spacerWidth = $0; self?.objectWillChange.send() })
    }

    var iconSpacingChoices: [MenuBarItemSpacing] {
        MenuBarItemSpacing.current() == .custom ? MenuBarItemSpacing.choices + [.custom] : MenuBarItemSpacing.choices
    }

    @Published private(set) var isRestartingApps = false
    private var restarter: MenuBarAppRestarter?

    // Apps read the spacing once, at launch, so this restarts the ones with
    // menu bar icons after asking. Finding them needs Accessibility.
    func restartMenuBarApps() {
        isRestartingApps = true
        AccessibilityMenuBarInventory().snapshot { [weak self] items in
            guard let self else { return }
            let apps = MenuBarAppRestartPlan.apps(owning: items, running: MenuBarAppRestarter.runningApps(),
                                                  ownBundleIdentifier: Bundle.main.bundleIdentifier)
            guard !apps.isEmpty else {
                self.isRestartingApps = false
                Self.inform("No other apps have menu bar icons to restart.".localized)
                return
            }
            let confirm = NSAlert()
            confirm.messageText = "Restart apps with menu bar icons?".localized
            confirm.informativeText = String(format: "These apps will quit and reopen so they use the new spacing: %@. An app with unsaved work may ask you first.".localized,
                                             Self.list(apps))
            confirm.addButton(withTitle: "Restart Apps".localized)
            confirm.addButton(withTitle: "Cancel".localized)
            guard confirm.runModal() == .alertFirstButtonReturn else {
                self.isRestartingApps = false
                return
            }
            let restarter = MenuBarAppRestarter()
            self.restarter = restarter
            restarter.restart(apps) { [weak self] didNotQuit in
                self?.restarter = nil
                self?.isRestartingApps = false
                if !didNotQuit.isEmpty {
                    Self.inform(String(format: "Some apps didn't quit: %@. Quit and reopen them yourself to use the new spacing.".localized,
                                       Self.list(didNotQuit)))
                }
            }
        }
    }

    private static func list(_ apps: [RestartableApp]) -> String {
        ListFormatter.localizedString(byJoining: apps.map(\.name))
    }

    private static func inform(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    var automaticallyChecksForUpdates: Binding<Bool> {
        return binding({ Preferences.automaticallyChecksForUpdates }) { Preferences.automaticallyChecksForUpdates = $0 }
    }

    var separateHiddenItemsBar: Binding<Bool> {
        return binding({ Preferences.showHiddenItemsInSeparateBar }) { enabled in
            if enabled && !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            Preferences.showHiddenItemsInSeparateBar = enabled
        }
    }
}

//MARK: - Views

struct GeneralSettingsView: View {
    @ObservedObject var model: GeneralSettingsModel

    // Strings shared with the old storyboard layout, trimmed of the punctuation
    // that only made sense there, so existing translations keep working.
    private static func label(_ key: String) -> String {
        return key.localized.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    }

    private let autoHideDelays = ["5 seconds", "10 seconds", "15 seconds", "30 seconds", "1 minute"]

    var body: some View {
        Form {
            if model.isAccessibilityPermissionMissing {
                Section { accessibilityNotice }
            }
            Section { tutorial }
            if model.clockDropsDate {
                Section { clockDateNotice }
            }

            Section(Self.label("Hiding")) {
                settingsToggle("Auto-collapse", isOn: model.autoHide)
                if model.autoHide.wrappedValue {
                    Picker(Self.label("Automatically hide icon after: "), selection: model.autoHideDelay) {
                        ForEach(autoHideDelays.indices, id: \.self) { index in
                            Text(verbatim: autoHideDelays[index].localized).tag(index)
                        }
                    }
                }
                settingsToggle("Collapse when another app becomes active", isOn: model.autoCollapseOnFocusChange)
                settingsToggle("Collapse when the Mac locks or sleeps", isOn: model.collapseWhenLocked)
            }

            Section(Self.label("Revealing")) {
                settingsToggle("Expand by hovering over the menu bar", isOn: model.hoverToExpand)
                settingsToggle("Click empty menu bar to show or hide icons", isOn: model.clickEmptyMenuBarToToggle)
                settingsToggle("Expand when an external display is connected", isOn: model.expandWhenExternalDisplayConnected)
                if StatusBarController.supportsPresentationMode {
                    settingsToggle("Show the icon of the app you're using", isOn: model.showActiveAppIcon)
                    settingsToggle("Show hidden icons briefly when they change", isOn: model.revealIconsOnActivity)
                    settingsToggle("Show an app's hidden icon for a moment after it updates", isOn: model.revealUpdatedApps)
                }
                LabeledContent(Self.label("Shortcut")) { shortcutRecorder(.toggle) }
                if StatusBarController.supportsPresentationMode {
                    LabeledContent(Self.label("Presentation Mode")) { shortcutRecorder(.presentation) }
                }
                if StatusBarController.supportsHiddenIconSearch {
                    LabeledContent(Self.label("Find Hidden Icon")) { shortcutRecorder(.find) }
                }
            }

            if !model.profileNames.isEmpty {
                Section {
                    ForEach(model.profileNames, id: \.self) { name in
                        LabeledContent {
                            HStack(spacing: 6) {
                                shortcutRecorder(.profile(name))
                                profileMenu(name)
                            }
                        } label: {
                            Text(verbatim: name)
                            Text(verbatim: profileAppsSummary(name))
                        }
                    }
                } header: {
                    Text(verbatim: Self.label("Profiles"))
                } footer: {
                    Text(verbatim: "Press a profile's shortcut to switch to it, and press it again to go back to the arrow.".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(Self.label("Appearance")) {
                Picker(Self.label("Expand icon"), selection: model.expandIconStyle) {
                    ForEach(ExpandIconStyle.allCases, id: \.self) { style in
                        Text(verbatim: style.rawValue.capitalized.localized).tag(style)
                    }
                }
                settingsToggle("Show hidden items in separate bar", isOn: model.separateHiddenItemsBar)
                if StatusBarController.supportsPresentationMode {
                    settingsToggle("Show how many icons are hidden", isOn: model.showHiddenIconCount)
                }
                settingsToggle("Use the full MenuBar on expanding", isOn: model.useFullMenuBar)
                Text(verbatim: "While expanded, Tuckaway comes to the front, so the current app's menus leave the menu bar and icons get its whole width. They come back when it collapses.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker(Self.label("Spacers"), selection: model.spacerCount) {
                    Text(verbatim: "None".localized).tag(0)
                    ForEach(1...MenuBarSpacers.maxCount, id: \.self) { count in
                        Text(verbatim: "\(count)").tag(count)
                    }
                }
                if model.spacerCount.wrappedValue > 0 {
                    Picker(Self.label("Spacer width"), selection: model.spacerWidth) {
                        Text(verbatim: "Narrow".localized).tag(MenuBarSpacers.Width.narrow)
                        Text(verbatim: "Medium".localized).tag(MenuBarSpacers.Width.medium)
                        Text(verbatim: "Wide".localized).tag(MenuBarSpacers.Width.wide)
                    }
                    Text(verbatim: "Hold ⌘ and drag a spacer between icons to group them.".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if MenuBarItemSpacing.isSupported {
                Section {
                    Picker(Self.label("Menu bar icon spacing"), selection: model.iconSpacing) {
                        ForEach(model.iconSpacingChoices, id: \.self) { level in
                            Text(verbatim: Self.title(of: level)).tag(level)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Restart Menu Bar Apps…".localized) { model.restartMenuBarApps() }
                            .controlSize(.small)
                            .disabled(model.isAccessibilityPermissionMissing || model.isRestartingApps)
                    }
                } footer: {
                    Text(verbatim: "Changes the space between all menu bar icons, not only Tuckaway's. Each app uses the new spacing the next time it opens; log out and back in to apply it everywhere.".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                settingsToggle("Enable always hidden section", isOn: model.alwaysHiddenSection)
                if NotchOverflowController.hasNotch {
                    settingsToggle("Enable Notch Overflow (right-click ‹ to access hidden icons)", isOn: model.notchOverflow)
                }
            } header: {
                Text(verbatim: Self.label("Extra Sections"))
            } footer: {
                Text(verbatim: MenuBarEngineFactory.usesNativeVisibility
                     ? "Place the always-hidden separator to the left of the arrow, then ⌘-drag icons to its left. Option-click the arrow to hide or reveal that section.".localized
                     : "Place the always-hidden separator to the left of the regular separator, then ⌘-drag icons to its left. Option-click the arrow to hide or reveal that section.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(Self.label("Startup")) {
                settingsToggle("Start Tuckaway when I log in", isOn: model.autoStart)
                settingsToggle("Show preferences on launch", isOn: model.showPreferencesOnLaunch)
            }

            if Updater.isSupported {
                Section(Self.label("Updates")) {
                    settingsToggle("Check for updates automatically", isOn: model.automaticallyChecksForUpdates)
                    LabeledContent(String(format: "Version %@".localized, Bundle.main.releaseVersionNumber ?? "")) {
                        Button("Check Now".localized) {
                            Updater.shared.checkForUpdates()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static func title(of level: MenuBarItemSpacing) -> String {
        switch level {
        case .standard: return "Default".localized
        case .compact: return "Compact".localized
        case .tight: return "Tight".localized
        case .custom: return "Custom".localized
        }
    }

    private func settingsToggle(_ key: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(verbatim: Self.label(key))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var tutorial: some View {
        VStack(spacing: 8) {
            MenuBarPreview(alwaysHidden: model.alwaysHiddenSection.wrappedValue)
                .frame(maxWidth: .infinity)
            Text(verbatim: MenuBarEngineFactory.usesNativeVisibility
                 ? "Hold ⌘ and drag icons to the left of the arrow to hide them.".localized
                 : Self.label("In your Mac's menu bar, hold ⌘ and drag icons\nbetween sections to configure Tuckaway.").replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var accessibilityNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(verbatim: "Tuckaway needs Accessibility access to hide icons.".localized)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Open Settings…".localized) {
                Util.requestAccessibilityPermission()
            }
            .controlSize(.small)
        }
    }

    private var clockDateNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
            Text(verbatim: "While icons are hidden, macOS drops the date from the clock because the menu bar looks full. To keep it, set Show Date to Always in Clock Options.".localized)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Clock Options…".localized) {
                ClockDateSetting.openClockSettings()
            }
            .controlSize(.small)
        }
    }

    private func profileMenu(_ name: String) -> some View {
        Menu {
            Button("Rename…".localized) { model.renameProfile(name) }
            Button("Use Current Layout".localized) { model.updateProfileToCurrentLayout(name) }
            Button("Schedule…".localized) { model.scheduleProfile(name) }
            Button("Use While an App Is Open…".localized) { model.chooseTriggerApp(name) }
            if let bundle = model.profileAppTriggers[name] {
                Button(String(format: "Stop Following %@".localized, GeneralSettingsModel.appName(bundle))) {
                    model.clearTriggerApp(name)
                }
            }
            Menu("Remove App".localized) {
                ForEach(model.profileApps[name] ?? [], id: \.self) { bundle in
                    Button(GeneralSettingsModel.appName(bundle)) { model.removeApp(bundle, fromProfile: name) }
                }
            }
            .disabled((model.profileApps[name] ?? []).isEmpty)
            Divider()
            Button("Delete Profile…".localized) { model.deleteProfile(name) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(String(format: "Edit %@".localized, name))
        .help("Edit Profile".localized)
    }

    // "Slack, Calendar and 2 more", or "No apps", after the schedule if any.
    private func profileAppsSummary(_ name: String) -> String {
        let names = (model.profileApps[name] ?? []).map(GeneralSettingsModel.appName)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let apps: String
        if names.isEmpty {
            apps = "No apps".localized
        } else if names.count > 3 {
            apps = String(format: "%@ and %d more".localized, names.prefix(2).joined(separator: ", "), names.count - 2)
        } else {
            apps = ListFormatter.localizedString(byJoining: names)
        }
        var parts: [String] = []
        if let bundle = model.profileAppTriggers[name] {
            parts.append(String(format: "While %@ is open".localized, GeneralSettingsModel.appName(bundle)))
        }
        if let schedule = model.profileSchedules[name] {
            parts.append(GeneralSettingsModel.describe(schedule))
        }
        return (parts + [apps]).joined(separator: " · ")
    }

    private func shortcutRecorder(_ kind: ShortcutKind) -> some View {
        let title: String? = {
            switch kind {
            case .toggle: return model.shortcutTitle
            case .presentation: return model.presentationShortcutTitle
            case .find: return model.findShortcutTitle
            case .profile(let name): return model.profileShortcutTitles[name]
            }
        }()
        let isRecording = model.isRecordingShortcut && model.recordingKind == kind
        return HStack(spacing: 6) {
            if title != nil && !isRecording {
                Button {
                    model.onClearShortcut(kind)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear".localized)
                .help("Clear".localized)
            }
            Button {
                model.onRecordShortcut(kind)
            } label: {
                Text(verbatim: shortcutButtonTitle(title: title, isRecording: isRecording))
                    .frame(minWidth: 80)
            }
            .controlSize(.small)
        }
    }

    private func shortcutButtonTitle(title: String?, isRecording: Bool) -> String {
        if isRecording {
            return model.recordingPreview.isEmpty ? "Type Shortcut…".localized : model.recordingPreview
        }
        return title ?? "Set Shortcut".localized
    }
}

// A miniature menu bar: the icons left of the boundary are the hidden section.
// On macOS 27 the arrow is the boundary; before that it is the separator.
private struct MenuBarPreview: View {
    let alwaysHidden: Bool

    private let showsSeparator = !MenuBarEngineFactory.usesNativeVisibility

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if alwaysHidden {
                section(["cloud", "headphones"], title: GeneralSettingsView.labelAlwaysHidden, style: .tertiary)
                onIconRow(icon("seprated_1").foregroundStyle(.secondary))
            }
            section(alwaysHidden ? ["gamecontroller", "battery.100"] : ["cloud", "headphones", "gamecontroller"], title: "Hidden".localized, style: .secondary)
            if showsSeparator {
                onIconRow(icon("seprated"))
            }
            onIconRow(icon("ico_collapse")
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 5)))
            section(["wifi", "magnifyingglass", "switch.2"], title: "Shown".localized, style: .primary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // Keeps an uncaptioned item on the icons' row, above the section captions.
    private func onIconRow<V: View>(_ content: V) -> some View {
        content.frame(height: 20)
    }

    private func icon(_ name: String) -> some View {
        let image = ["ico_collapse", "seprated", "seprated_1"].contains(name)
            ? Image(name) : Image(systemName: name)
        return image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }

    private func section<S: ShapeStyle>(_ icons: [String], title: String, style: S) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 9) {
                ForEach(icons, id: \.self) { icon($0) }
            }
            .foregroundStyle(style)
            .frame(height: 20)
            Text(verbatim: title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private extension GeneralSettingsView {
    static var labelAlwaysHidden: String {
        return "⭐️Always Hidden".localized.replacingOccurrences(of: "⭐️", with: "")
    }
}
