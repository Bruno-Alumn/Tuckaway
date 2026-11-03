//
//  SetupCheckTests.swift
//  TuckawayUnitTests
//

import XCTest

// "Check Your Setup": which of the known reasons Tuckaway can't hide anything are
// present, from values the caller measured. Every reason is a value here so the
// wording and ordering are covered by tests rather than by looking at the window.
final class SetupCheckTests: XCTestCase {
    private func inputs(runsNativeHiding: Bool = true,
                        accessibility: Bool = true,
                        separateBar: Bool = false,
                        screenRecording: Bool = true,
                        hiddenIcons: Int = 2,
                        layoutReadable: Bool? = true,
                        arrowOnScreen: Bool = true,
                        loginItem: Bool = true) -> SetupCheck.Inputs {
        SetupCheck.Inputs(runsNativeHiding: runsNativeHiding, isAccessibilityGranted: accessibility,
                          usesSeparateBar: separateBar, isScreenRecordingGranted: screenRecording,
                          hiddenIconCount: hiddenIcons, layoutIsReadable: layoutReadable,
                          isArrowOnScreen: arrowOnScreen, isLoginItemOn: loginItem)
    }

    func testAWorkingSetupReportsNothing() {
        XCTAssertEqual(SetupCheck.issues(inputs()), [])
        XCTAssertEqual(SetupCheck.summary([]), .fine)
    }

    // Without Accessibility nothing about the sections can be judged, so the
    // other hiding problems would only be noise.
    func testMissingAccessibilityStandsAlone() {
        XCTAssertEqual(SetupCheck.issues(inputs(accessibility: false, separateBar: true, screenRecording: false,
                                               hiddenIcons: 0, arrowOnScreen: false, loginItem: false)),
                       [.missingAccessibility])
    }

    func testTheSeparateBarNeedsScreenRecording() {
        XCTAssertEqual(SetupCheck.issues(inputs(separateBar: true, screenRecording: false)), [.missingScreenRecording])
        XCTAssertEqual(SetupCheck.issues(inputs(separateBar: false, screenRecording: false)), [],
                       "the bar is off, so the permission doesn't matter")
    }

    // Every icon is on the visible side, which is the most common "it does
    // nothing" report.
    func testNoHiddenIconsIsReportedOnlyOnceTheLayoutCanBeRead() {
        XCTAssertEqual(SetupCheck.issues(inputs(hiddenIcons: 0)), [.nothingToHide])
        XCTAssertEqual(SetupCheck.issues(inputs(hiddenIcons: 0, layoutReadable: nil)), [],
                       "a layout that can't be read yet isn't a problem")
        XCTAssertEqual(SetupCheck.issues(inputs(hiddenIcons: 0, layoutReadable: false)), [])
    }

    func testALostArrowAndAClosedLoginItemAreBothReported() {
        XCTAssertEqual(SetupCheck.issues(inputs(arrowOnScreen: false, loginItem: false)),
                       [.arrowOffScreen, .loginItemOff])
    }

    // On 13–26 the hiding mechanism doesn't depend on the sections being
    // readable, so only the two checks that apply there are made.
    func testOlderSystemsSkipTheSectionChecks() {
        XCTAssertEqual(SetupCheck.issues(inputs(runsNativeHiding: false, accessibility: false,
                                               separateBar: true, screenRecording: false, hiddenIcons: 0)),
                       [])
        XCTAssertEqual(SetupCheck.issues(inputs(runsNativeHiding: false, loginItem: false)), [.loginItemOff])
    }

    func testASummarySaysWhetherAnythingNeedsAttention() {
        XCTAssertEqual(SetupCheck.summary(SetupCheck.issues(inputs(loginItem: false))), .needsAttention)
    }
}
