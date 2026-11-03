//
//  NewAppAnswerUndo.swift
//  Tuckaway
//

import Foundation

// Answering the new-app question is permanent: **Hide** leaves the app's icon on
// the hidden side, and the only way back is Menu Bar Items. A reflex click there
// (or an answer given about a helper that then quit) is easy to regret.
//
// This keeps the last answer around for a few minutes so the arrow's menu can
// offer to undo it. Kept free of AppKit so the ageing-out rule is testable.
struct NewAppAnswerUndo: Equatable {
    let bundle: String
    // The answer to undo: Hide marks an app undecided again, Keep Visible hides it.
    let wasKeptVisible: Bool
    let answeredAt: Date

    // Long enough to notice, short enough that it can't be mistaken for a
    // setting.
    static let lifetime: TimeInterval = 5 * 60

    static func offered(_ undo: NewAppAnswerUndo?, bundle: String, now: Date) -> NewAppAnswerUndo? {
        guard let undo, undo.bundle == bundle, !undo.isExpired(now: now) else { return nil }
        return undo
    }

    func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(answeredAt) >= Self.lifetime
    }

    // What undoing does: the opposite of the answer that was given.
    var undoesToKeepVisible: Bool {
        !wasKeptVisible
    }
}
