//
//  VisualSeparator.swift
//  Tuckaway
//

import CoreGraphics

// The `|` people know from Hidden Bar, on systems that don't need it.
//
// macOS 27 hides by the arrow, so the separator has nothing to hide behind and
// Tuckaway takes it out of the bar. Users still expect the mark that says where
// the hidden section ends, and Menu Bar Items still shows one, so on 27 the
// separator becomes an ordinary decorative item that sits left of the arrow.
//
// The arithmetic is kept here so the rules (when there is one, how wide it is)
// can be tested without a menu bar.
enum VisualSeparator {
    // What the item should look like, given the settings that matter.
    struct Appearance: Equatable {
        let isShown: Bool
        let length: CGFloat
    }

    // The width the old separator had when the bar was expanded.
    static let width: CGFloat = 20

    static func appearance(usesNativeHiding: Bool, isEnabled: Bool, isArrowOnScreen: Bool) -> Appearance {
        // Without native hiding the engine still owns the real separator, and
        // showing a second one would double it.
        guard usesNativeHiding else { return Appearance(isShown: false, length: 0) }
        // Nothing to anchor to before the first layout.
        guard isArrowOnScreen else { return Appearance(isShown: false, length: 0) }
        return isEnabled ? Appearance(isShown: true, length: width) : Appearance(isShown: false, length: 0)
    }
}
