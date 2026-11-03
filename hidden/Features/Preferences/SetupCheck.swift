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
        // The App Store build on macOS 27, which can't hide icons at all.
        case hidingUnavailable
        // No Device Control and Data Access (macOS 27's name for
        // Accessibility): the sections can't be read, so nothing hides.
        case missingAccessibility
        // Screen Recording is off, which the separate hidden-items bar needs.
        case missingScreenRecording
        // Icons are all on the visible side, so collapsing would hide nothing.
        case nothingToHide
        // The arrow was left off screen (macOS 13–26); repairing it puts it back.
        case arrowOffScreen
    }

    struct Inputs {
        let hidingUnavailable: Bool
        let runsNativeHiding: Bool
        let isAccessibilityGranted: Bool
        let usesSeparateBar: Bool
        let isScreenRecordingGranted: Bool
        let hiddenIconCount: Int
        // Nil when the layout can't be read yet, which is not an issue by itself.
        let layoutIsReadable: Bool?
        let isArrowOnScreen: Bool
    }

    // The issues to show, most likely to matter first. A build that can't hide,
    // or a missing permission, makes the rest meaningless, so each stands alone.
    static func issues(_ inputs: Inputs) -> [Issue] {
        guard !inputs.hidingUnavailable else { return [.hidingUnavailable] }
        // macOS 13–26: hiding needs no permission. The arrow is the one thing
        // that can go wrong; on 27 Tuckaway's own items are always shown.
        guard inputs.runsNativeHiding else {
            return inputs.isArrowOnScreen ? [] : [.arrowOffScreen]
        }
        guard inputs.isAccessibilityGranted else { return [.missingAccessibility] }
        var issues: [Issue] = []
        if inputs.usesSeparateBar && !inputs.isScreenRecordingGranted {
            issues.append(.missingScreenRecording)
        }
        if inputs.layoutIsReadable == true && inputs.hiddenIconCount == 0 {
            issues.append(.nothingToHide)
        }
        return issues
    }
}
