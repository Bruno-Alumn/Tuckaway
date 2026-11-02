import XCTest
@testable import Tuckaway

final class GlobalShortcutTests: XCTestCase {
    private func shortcut(keyCode: UInt32 = 0, flags: UInt32 = 0,
                          function: Bool = false, capsLock: Bool = false) -> GlobalKeybindPreferences {
        GlobalKeybindPreferences(function: function, control: false, command: false,
                                shift: false, option: false, capsLock: capsLock,
                                carbonFlags: flags, characters: "a", keyCode: keyCode)
    }

    func testOrdinaryTypingModifiersAreRejected() {
        XCTAssertFalse(shortcut().isValidGlobalShortcut)
        XCTAssertFalse(shortcut(flags: 1 << 9).isValidGlobalShortcut)
        XCTAssertFalse(shortcut(flags: 1 << 10, capsLock: true).isValidGlobalShortcut)
        XCTAssertFalse(shortcut(function: true).isValidGlobalShortcut)
    }

    func testCarbonShortcutModifiersAreAccepted() {
        for flags: UInt32 in [1 << 8, 1 << 11, 1 << 12, (1 << 8) | (1 << 9)] {
            XCTAssertTrue(shortcut(flags: flags).isValidGlobalShortcut)
        }
    }

    func testStandaloneFunctionKeyIsAccepted() {
        XCTAssertTrue(shortcut(keyCode: 79).isValidGlobalShortcut)
    }

    func testInvalidSavedShortcutIsIgnored() {
        let previous = Preferences.globalKey
        defer { Preferences.globalKey = previous }
        Preferences.globalKey = shortcut(flags: 1 << 9)
        XCTAssertNil(Preferences.globalKey)
    }

    func testInvalidRecordingPreservesSavedShortcut() {
        let previous = Preferences.globalKey
        defer { Preferences.globalKey = previous }
        let saved = shortcut(flags: 1 << 8)
        Preferences.globalKey = saved
        let controller = PreferencesViewController()
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: "a", charactersIgnoringModifiers: "a",
                                     isARepeat: false, keyCode: 0)!
        controller.updateGlobalShortcut(event)
        let shifted = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       characters: "A", charactersIgnoringModifiers: "a",
                                       isARepeat: false, keyCode: 0)!
        controller.updateGlobalShortcut(shifted)
        XCTAssertEqual(Preferences.globalKey?.carbonFlags, saved.carbonFlags)
        XCTAssertEqual(Preferences.globalKey?.keyCode, saved.keyCode)
    }

    func testSameComboIgnoresCharacters() {
        let commandH = shortcut(keyCode: 4, flags: 1 << 8)
        let sameKeys = GlobalKeybindPreferences(function: false, control: false, command: true, shift: false, option: false,
                                                capsLock: false, carbonFlags: 1 << 8, characters: "H", keyCode: 4)
        XCTAssertTrue(commandH.isSameCombo(as: sameKeys))
        XCTAssertFalse(commandH.isSameCombo(as: shortcut(keyCode: 4, flags: (1 << 8) | (1 << 9))))
        XCTAssertFalse(commandH.isSameCombo(as: shortcut(keyCode: 5, flags: 1 << 8)))
    }
}
