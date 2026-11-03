//
//  WhatsNewTests.swift
//  TuckawayUnitTests
//

import XCTest

// "What's New" after an update: one notes file per release (or per range of
// releases) baked into the app, shown once for the version that is running.
final class WhatsNewTests: XCTestCase {
    private let sample = """
    versions: 1.8.0-1.9.0

    ### Added
    - **Profiles** while an app is open.
    - Shortcuts per profile.

    ### Fixed
    - The clock's date.
    """

    // MARK: Parsing

    func testParsesAVersionRangeAndItsBody() throws {
        let notes = try XCTUnwrap(WhatsNew.parse(sample))
        XCTAssertEqual(notes.first, ReleaseVersion("1.8.0"))
        XCTAssertEqual(notes.last, ReleaseVersion("1.9.0"))
        XCTAssertTrue(notes.body.hasPrefix("### Added"))
        XCTAssertTrue(notes.body.hasSuffix("The clock's date."))
    }

    func testASingleVersionCoversJustThatVersion() throws {
        let notes = try XCTUnwrap(WhatsNew.parse("versions: 2.0.1\n\n- One thing."))
        XCTAssertEqual(notes.first, ReleaseVersion("2.0.1"))
        XCTAssertEqual(notes.last, ReleaseVersion("2.0.1"))
        XCTAssertEqual(notes.body, "- One thing.")
    }

    func testAMissingHeaderIsRefusedRatherThanShownEverywhere() {
        XCTAssertNil(WhatsNew.parse("- **Added** something.\n- And more."))
        XCTAssertNil(WhatsNew.parse(""))
    }

    func testAnEmptyBodyOrABackwardsRangeIsRefused() {
        XCTAssertNil(WhatsNew.parse("versions: 1.9.0\n\n"))
        XCTAssertNil(WhatsNew.parse("versions: 1.9.0\n\n   \n\n"))
        XCTAssertNil(WhatsNew.parse("versions: 1.9.0-1.8.0\n\n- Something."))
        XCTAssertNil(WhatsNew.parse("versions: \n\n- Something."))
    }

    func testAFileWithLeadingBlankLinesStillParses() throws {
        let notes = try XCTUnwrap(WhatsNew.parse("\n\nversions: 1.8.0\n\n- Something."))
        XCTAssertEqual(notes.body, "- Something.")
    }

    // MARK: Deciding whether to show them

    func testShowsNotesForTheRunningVersion() throws {
        let notes = try XCTUnwrap(WhatsNew.parse(sample))
        XCTAssertTrue(WhatsNew.shouldShow(notes, running: "1.9.0", lastSeen: "1.8.0"))
    }

    // Updating from 1.8.0 (or 1.7.0) straight to 1.9.0 shows the whole range.
    func testShowsNotesCoveringAMultiVersionJump() throws {
        let notes = try XCTUnwrap(WhatsNew.parse(sample))
        XCTAssertTrue(WhatsNew.shouldShow(notes, running: "1.9.0", lastSeen: "1.6.1"))
        XCTAssertTrue(WhatsNew.shouldShow(notes, running: "1.8.0", lastSeen: nil))
    }

    func testDoesNotShowNotesForAReleaseAlreadySeen() throws {
        let notes = try XCTUnwrap(WhatsNew.parse(sample))
        XCTAssertFalse(WhatsNew.shouldShow(notes, running: "1.9.0", lastSeen: "1.9.0"))
        XCTAssertFalse(WhatsNew.shouldShow(notes, running: "1.8.0", lastSeen: "1.9.0"))
    }

    func testDoesNotShowNotesForAnotherRelease() throws {
        let notes = try XCTUnwrap(WhatsNew.parse(sample))
        XCTAssertFalse(WhatsNew.shouldShow(notes, running: "2.0.0", lastSeen: "1.8.0"))
        XCTAssertFalse(WhatsNew.shouldShow(notes, running: "1.7.0", lastSeen: "1.6.0"))
        XCTAssertFalse(WhatsNew.shouldShow(notes, running: nil, lastSeen: "1.6.0"))
        XCTAssertFalse(WhatsNew.shouldShow(notes, running: "", lastSeen: nil))
    }

    // The version string comes from the bundle; a nonsense one must not pop a
    // window up.
    func testAnUnreadableRunningVersionShowsNothing() throws {
        let notes = try XCTUnwrap(WhatsNew.parse(sample))
        XCTAssertFalse(WhatsNew.shouldShow(notes, running: "one point nine", lastSeen: nil))
    }

    // A last-seen value that can't be parsed (hand-edited defaults) is treated
    // as a first launch.
    func testAnUnreadableLastSeenCountsAsFirstLaunch() throws {
        let notes = try XCTUnwrap(WhatsNew.parse(sample))
        XCTAssertTrue(WhatsNew.shouldShow(notes, running: "1.9.0", lastSeen: "banana"))
    }

    // 1.10 is newer than 1.9, which a plain string comparison gets wrong.
    func testVersionOrderIsNumeric() throws {
        let notes = try XCTUnwrap(WhatsNew.parse("versions: 1.10.0\n\n- Something."))
        XCTAssertTrue(WhatsNew.shouldShow(notes, running: "1.10.0", lastSeen: "1.9.0"))
        XCTAssertFalse(WhatsNew.shouldShow(notes, running: "1.10.0", lastSeen: "1.10.0"))
    }

    // MARK: What the window shows

    func testMarkdownBecomesReadableChangelogText() {
        let text = WhatsNew.plainText("### Added\n- **Profiles** while an app is open.\n\n### Fixed\n- The clock's date.")
        XCTAssertEqual(text, "Added\n• Profiles while an app is open.\n\nFixed\n• The clock's date.")
    }

    // A heading with no items under it is still a body: it is what a release
    // with a single empty section would carry.
    func testAHeadingAloneIsABody() throws {
        let notes = try XCTUnwrap(WhatsNew.parse("versions: 1.9.0\n\n### Added"))
        XCTAssertEqual(notes.body, "### Added")
    }

    func testPlainTextLeavesOrdinaryLinesAlone() {
        XCTAssertEqual(WhatsNew.plainText("One line.\nAnother line."), "One line.\nAnother line.")
    }
}
