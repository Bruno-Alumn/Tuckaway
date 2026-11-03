//
//  SetupCheck.swift
//  Tuckaway
//

import Foundation

// "Check Your Setup" in Settings: the handful of things that stop Tuckaway from
// hiding anything, checked in one place and explained in the app.
//
// Every check here is a value the caller measured (permissions, settings,
// whether the arrow is where it should be); nothing in this file asks the system
// anything, so the reasons can be tested and translated one at a time.
struct SetupCheck {
    enum Issue: Equatable {
        // No Accessibility (Device Control and Data Access on 27): the sections
        // can't be read, so nothing hides.
        case missingAccessibility
        // Screen Recording is off, which the separate hidden-items bar needs.
        case missingScreenRecording
        // Icons are all on the visible side, so collapsing would hide nothing.
        case nothingToHide
        // The arrow was left off screen; MenuBarRescue repairs it.
        case arrowOffScreen
        // The login item is off, so Tuckaway won't be there after a restart.
        case loginItemOff
    }

    struct Inputs {
        let runsNativeHiding: Bool
        let isAccessibilityGranted: Bool
        let usesSeparateBar: Bool
        let isScreenRecordingGranted: Bool
        let hiddenIconCount: Int
        // Nil when the layout can't be read yet, which is not an issue by itself.
        let layoutIsReadable: Bool?
        let isArrowOnScreen: Bool
        let isLoginItemOn: Bool
    }

    // The issues to show, most likely to matter first. An accessibility problem
    // makes the rest of the hiding checks meaningless, so it stands alone.
    static func issues(_ inputs: Inputs) -> [Issue] {
        guard inputs.runsNativeHiding else {
            return [
                inputs.isArrowOnScreen ? nil : .arrowOffScreen,
                inputs.isLoginItemOn ? nil : .loginItemOff,
            ].compactMap { $0 }
        }
        guard inputs.isAccessibilityGranted else { return [.missingAccessibility] }
        var issues: [Issue] = []
        if inputs.usesSeparateBar && !inputs.isScreenRecordingGranted {
            issues.append(.missingScreenRecording)
        }
        if inputs.layoutIsReadable == true && inputs.hiddenIconCount == 0 {
            issues.append(.nothingToHide)
        }
        if !inputs.isArrowOnScreen {
            issues.append(.arrowOffScreen)
        }
        if !inputs.isLoginItemOn {
            issues.append(.loginItemOff)
        }
        return issues
    }

    static func summary(_ issues: [Issue]) -> Summary {
        issues.isEmpty ? .fine : .needsAttention
    }

    enum Summary: Equatable {
        case fine
        case needsAttention
    }
}
