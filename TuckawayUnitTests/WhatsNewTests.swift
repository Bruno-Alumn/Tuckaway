//
//  WhatsNewTests.swift
//  TuckawayUnitTests
//

import XCTest

// "What's New" after an update: CHANGELOG.md's released sections baked into the
// app, shown once for the releases since the one last run.
final class WhatsNewTests: XCTestCase {
    private let changelog = """
    # Changelog

    ## Unreleased

    ### Added
    - Not released yet.

    ## v1.9.0 (2026-12-01)

    ### Added
    - **Profiles** while an app is open.

    ## v1.8.1 (2026-11-20)

    ### Fixed
    - The clock's date.

    ## v1.8.0 (2026-11-02)

    ### Added
    - Shortcuts per profile.
    """

    private var notes: [ReleaseNotes] { WhatsNew.parse(changelog) }

    // MARK: Parsing

    func testParsesEachReleasedSectionAndSkipsUnreleased() {
        XCTAssertEqual(notes.map(\.version.description), ["1.9.0", "1.8.1", "1.8.0"])
        XCTAssertEqual(notes[0].heading, "v1.9.0 (2026-12-01)")
        XCTAssertEqual(notes[0].body, "### Added\n- **Profiles** while an app is open.")
        XCTAssertFalse(notes.contains { $0.body.contains("Not released yet") })
    }

    func testStopsAtTheOlderProjectsHistory() {
        let text = changelog + "\n\n## v1.11.1 (2026-09-18)\n\n### Fixed\n- Hidden Bar's last fix."
        XCTAssertEqual(WhatsNew.parse(text).map(\.version.description), ["1.9.0", "1.8.1", "1.8.0"])
    }

    func testAFileWithoutReleasedSectionsHasNoNotes() {
        XCTAssertEqual(WhatsNew.parse(""), [])
        XCTAssertEqual(WhatsNew.parse("- Something.\n## Unreleased\n- More."), [])
        XCTAssertEqual(WhatsNew.parse("## v2.0.0\n\n   \n"), [])
    }

    // MARK: Deciding what to show

    func testAFreshInstallShowsNothingButRecordsTheVersion() {
        let plan = WhatsNew.plan(notes: notes, running: "1.9.0", lastSeen: nil, isFirstLaunch: true)
        XCTAssertEqual(plan, WhatsNew.Plan(recordSeen: "1.9.0", show: []))
    }

    func testAnUpdateFromBeforeWhatsNewShowsOnlyTheRunningRelease() {
        let plan = WhatsNew.plan(notes: notes, running: "1.9.0", lastSeen: nil, isFirstLaunch: false)
        XCTAssertEqual(plan.show.map(\.version.description), ["1.9.0"])
        XCTAssertEqual(plan.recordSeen, "1.9.0")
    }

    func testAnUpdateThatSkippedReleasesShowsEachOneNewestFirst() {
        let plan = WhatsNew.plan(notes: notes, running: "1.9.0", lastSeen: "1.8.0", isFirstLaunch: false)
        XCTAssertEqual(plan.show.map(\.version.description), ["1.9.0", "1.8.1"])
    }

    func testTheSameVersionAgainShowsNothing() {
        let plan = WhatsNew.plan(notes: notes, running: "1.9.0", lastSeen: "1.9.0", isFirstLaunch: false)
        XCTAssertEqual(plan, WhatsNew.Plan(recordSeen: nil, show: []))
    }

    func testRunningAnOlderCopyNeitherShowsNorForgetsTheNewerVersion() {
        let plan = WhatsNew.plan(notes: notes, running: "1.8.0", lastSeen: "1.9.0", isFirstLaunch: false)
        XCTAssertEqual(plan, WhatsNew.Plan(recordSeen: nil, show: []))
    }

    func testABuildWithoutNotesOrAVersionShowsNothing() {
        XCTAssertEqual(WhatsNew.plan(notes: [], running: "2.0.0", lastSeen: "1.9.0", isFirstLaunch: false).show, [])
        XCTAssertEqual(WhatsNew.plan(notes: notes, running: nil, lastSeen: "1.8.0", isFirstLaunch: false),
                       WhatsNew.Plan(recordSeen: nil, show: []))
    }

    func testALongAbsenceShowsOnlyTheNewestReleases() {
        let many = (0..<8).map {
            ReleaseNotes(version: ReleaseVersion("1.\($0).0")!, heading: "v1.\($0).0", body: "- Change \($0).")
        }
        let plan = WhatsNew.plan(notes: many, running: "1.7.0", lastSeen: "0.9.0", isFirstLaunch: false)
        XCTAssertEqual(plan.show.count, WhatsNew.maxReleases)
        XCTAssertEqual(plan.show.first?.version.description, "1.7.0")
    }

    // MARK: Text

    func testOneReleaseShowsItsNotesWithoutAHeading() {
        let text = WhatsNew.plainText([notes[0]])
        XCTAssertEqual(text, "Added\n• Profiles while an app is open.")
    }

    func testCodeMarksAreDropped() {
        XCTAssertEqual(WhatsNew.plainText("- Install with `brew install --cask tuckaway`."),
                       "• Install with brew install --cask tuckaway.")
    }

    func testSeveralReleasesEachStartWithTheirHeading() {
        let text = WhatsNew.plainText(Array(notes.prefix(2)))
        XCTAssertTrue(text.hasPrefix("v1.9.0 (2026-12-01)\n\nAdded"))
        XCTAssertTrue(text.contains("\n\nv1.8.1 (2026-11-20)\n\nFixed\n• The clock's date."))
    }
}
