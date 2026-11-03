//
//  SetupCheckTests.swift
//  TuckawayUnitTests
//

import XCTest

// "Check Your Setup": which of the known reasons Tuckaway can't hide anything are
// present, from values the caller measured. Every reason is a value here so the
// wording and ordering are covered by tests rather than by looking at the window.
final class SetupCheckTests: XCTestCase {
    private func inputs(hidingUnavailable: Bool = false,
                        runsNativeHiding: Bool = true,
                        accessibility: Bool = true,
                        separateBar: Bool = false,
                        screenRecording: Bool = true,
                        hiddenIcons: Int = 2,
                        layoutReadable: Bool? = true,
                        arrowOnScreen: Bool = true) -> SetupCheck.Inputs {
        SetupCheck.Inputs(hidingUnavailable: hidingUnavailable, runsNativeHiding: runsNativeHiding,
                          isAccessibilityGranted: accessibility,
                          usesSeparateBar: separateBar, isScreenRecordingGranted: screenRecording,
                          hiddenIconCount: hiddenIcons, layoutIsReadable: layoutReadable,
                          isArrowOnScreen: arrowOnScreen)
    }

    func testAWorkingSetupReportsNothing() {
        XCTAssertEqual(SetupCheck.issues(inputs()), [])
        XCTAssertEqual(SetupCheck.issues(inputs(runsNativeHiding: false)), [])
    }

    // The App Store build on macOS 27 can't hide anything, so "everything looks
    // right" would be false whatever else is true.
    func testABuildThatCantHideSaysSoAndNothingElse() {
        XCTAssertEqual(SetupCheck.issues(inputs(hidingUnavailable: true, runsNativeHiding: false)),
                       [.hidingUnavailable])
        XCTAssertEqual(SetupCheck.issues(inputs(hidingUnavailable: true, runsNativeHiding: false,
                                               arrowOnScreen: false)),
                       [.hidingUnavailable])
    }

    // Without Accessibility nothing about the sections can be judged, so the
    // other hiding problems would only be noise.
    func testMissingAccessibilityStandsAlone() {
        XCTAssertEqual(SetupCheck.issues(inputs(accessibility: false, separateBar: true, screenRecording: false,
                                               hiddenIcons: 0)),
                       [.missingAccessibility])
    }

    func testTheSeparateBarNeedsScreenRecording() {
        XCTAssertEqual(SetupCheck.issues(inputs(separateBar: true, screenRecording: false)), [.missingScreenRecording])
        XCTAssertEqual(SetupCheck.issues(inputs(separateBar: false, screenRecording: false)), [],
                       "the bar is off, so the permission doesn't matter")
    }

    func testNoHiddenIconsIsReportedOnlyOnceTheLayoutCanBeRead() {
        XCTAssertEqual(SetupCheck.issues(inputs(hiddenIcons: 0)), [.nothingToHide])
        XCTAssertEqual(SetupCheck.issues(inputs(hiddenIcons: 0, layoutReadable: nil)), [],
                       "no layout read yet isn't a problem")
        XCTAssertEqual(SetupCheck.issues(inputs(hiddenIcons: 0, layoutReadable: false)), [])
    }

    func testBothSectionProblemsAreReportedTogether() {
        XCTAssertEqual(SetupCheck.issues(inputs(separateBar: true, screenRecording: false, hiddenIcons: 0)),
                       [.missingScreenRecording, .nothingToHide])
    }

    // On 13–26 hiding needs no permission and the sections aren't read; the
    // arrow is the one thing that can be lost.
    func testOlderSystemsOnlyCheckTheArrow() {
        XCTAssertEqual(SetupCheck.issues(inputs(runsNativeHiding: false, accessibility: false,
                                               separateBar: true, screenRecording: false, hiddenIcons: 0)),
                       [])
        XCTAssertEqual(SetupCheck.issues(inputs(runsNativeHiding: false, arrowOnScreen: false)), [.arrowOffScreen])
    }

    // On 27 Tuckaway's own items always show, so a stale frame there isn't
    // reported as a lost arrow.
    func testMacOS27DoesntReportTheArrow() {
        XCTAssertEqual(SetupCheck.issues(inputs(arrowOnScreen: false)), [])
    }

    func testTheArrowCountsAsReachableUntilItsBeenMeasured() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        XCTAssertTrue(MenuBarRescue.isReachable(arrowFrame: nil, screenFrames: [screen]))
        XCTAssertTrue(MenuBarRescue.isReachable(arrowFrame: CGRect(x: 0, y: 0, width: 30, height: 24),
                                                screenFrames: [screen]))
        XCTAssertTrue(MenuBarRescue.isReachable(arrowFrame: CGRect(x: 1804, y: 1145, width: 30, height: 24),
                                                screenFrames: [screen]), "a few points over the edge")
        XCTAssertFalse(MenuBarRescue.isReachable(arrowFrame: CGRect(x: -400, y: 1145, width: 30, height: 24),
                                                 screenFrames: [screen]))
    }
}
