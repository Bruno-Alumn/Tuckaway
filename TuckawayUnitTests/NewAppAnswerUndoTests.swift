//
//  NewAppAnswerUndoTests.swift
//  TuckawayUnitTests
//

import XCTest

// The undo offered after answering the new-app question: it belongs to one app,
// it ages out, and undoing it gives the opposite answer.
final class NewAppAnswerUndoTests: XCTestCase {
    private let answered = Date(timeIntervalSince1970: 1_000_000)

    private func undo(bundle: String = "com.example.helper", kept: Bool = false) -> NewAppAnswerUndo {
        NewAppAnswerUndo(bundle: bundle, wasKeptVisible: kept, answeredAt: answered)
    }

    func testTheUndoIsOfferedForItsOwnAppRightAfterTheAnswer() {
        let offered = NewAppAnswerUndo.offered(undo(), bundle: "com.example.helper",
                                               now: answered.addingTimeInterval(5))
        XCTAssertNotNil(offered)
    }

    func testItIsNotOfferedForAnotherApp() {
        XCTAssertNil(NewAppAnswerUndo.offered(undo(), bundle: "com.example.other",
                                              now: answered.addingTimeInterval(5)))
    }

    // Five minutes is long enough to notice a mistake, short enough not to look
    // like a setting that stays.
    func testItAgesOut() {
        XCTAssertNotNil(NewAppAnswerUndo.offered(undo(), bundle: "com.example.helper",
                                                 now: answered.addingTimeInterval(NewAppAnswerUndo.lifetime - 1)))
        XCTAssertNil(NewAppAnswerUndo.offered(undo(), bundle: "com.example.helper",
                                              now: answered.addingTimeInterval(NewAppAnswerUndo.lifetime)))
        XCTAssertTrue(undo().isExpired(now: answered.addingTimeInterval(3600)))
    }

    func testNothingAnsweredOffersNothing() {
        XCTAssertNil(NewAppAnswerUndo.offered(nil, bundle: "com.example.helper", now: answered))
    }

    // Undoing Hide keeps the app visible again; undoing Keep Visible hides it.
    func testUndoingGivesTheOppositeAnswer() {
        XCTAssertTrue(undo(kept: false).undoesToKeepVisible)
        XCTAssertFalse(undo(kept: true).undoesToKeepVisible)
    }
}
