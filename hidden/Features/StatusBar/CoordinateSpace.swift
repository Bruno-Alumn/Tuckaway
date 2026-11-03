//
//  CoordinateSpace.swift
//  Tuckaway
//

import CoreGraphics

// The menu bar's two vertical origins. Accessibility and Quartz (window frames)
// measure y down from the top of the primary screen; AppKit measures it up from
// the bottom of the primary screen. Converting between them is a few lines, but
// getting the reference edge wrong moves every rectangle, so it lives here, away
// from the capture code, where it can be tested.
enum MenuBarCoordinateSpace {
    struct Conversion {
        // The primary screen's top edge in AppKit's coordinates. Quartz calls it
        // zero, so this is the one number both spaces share.
        let referenceMaxY: CGFloat

        // Before any screen has reported a frame, there is no shared top edge; the
        // caller's own value keeps the rectangle near where it already is instead
        // of flipping every coordinate.
        init(primaryScreenMaxY: CGFloat?, fallbackMaxY: CGFloat) {
            referenceMaxY = primaryScreenMaxY ?? fallbackMaxY
        }
    }

    static func appKitRect(fromQuartz rect: CGRect, in space: Conversion) -> CGRect {
        flipped(rect, in: space, edge: rect.maxY)
    }

    static func quartzRect(fromAppKit rect: CGRect, in space: Conversion) -> CGRect {
        flipped(rect, in: space, edge: rect.maxY)
    }

    static func quartzPoint(fromAppKit point: CGPoint, in space: Conversion) -> CGPoint {
        CGPoint(x: point.x, y: space.referenceMaxY - point.y)
    }

    // Both spaces put x in the same place and differ only in which end of the
    // screen y counts from, so the conversion is the same in both directions: the
    // distance of the rectangle's opposite edge from the shared top.
    private static func flipped(_ rect: CGRect, in space: Conversion, edge: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: space.referenceMaxY - edge, width: rect.width, height: rect.height)
    }
}
