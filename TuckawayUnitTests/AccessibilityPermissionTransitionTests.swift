import XCTest

final class AccessibilityPermissionTransitionTests: XCTestCase {
    func testOtherAppsPermissionChangesPreserveAnExpandedBar() {
        var permission = AccessibilityPermissionTransition(isTrusted: true)
        for _ in 0..<3 {
            XCTAssertFalse(permission.permissionWasRestored(isTrusted: true))
        }
    }

    func testMissingPermissionDoesNotRetryCollapse() {
        var permission = AccessibilityPermissionTransition(isTrusted: false)
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: false))
    }

    func testRestoredPermissionRetriesOnce() {
        var permission = AccessibilityPermissionTransition(isTrusted: false)
        XCTAssertTrue(permission.permissionWasRestored(isTrusted: true))
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: true))
    }

    func testRevocationThenRestorationRetriesAgain() {
        var permission = AccessibilityPermissionTransition(isTrusted: true)
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: false))
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: false))
        XCTAssertTrue(permission.permissionWasRestored(isTrusted: true))
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: true))
    }

    func testSameCertificateNeverResets() {
        XCTAssertFalse(StaleGrantReset.shouldReset(isGranted: false, certificate: "a", recordedCertificate: "a", isDeveloperID: true))
    }

    func testNewCertificateResetsAPermissionThatDoesNotWork() {
        XCTAssertTrue(StaleGrantReset.shouldReset(isGranted: false, certificate: "b", recordedCertificate: "a", isDeveloperID: true))
        XCTAssertFalse(StaleGrantReset.shouldReset(isGranted: true, certificate: "b", recordedCertificate: "a", isDeveloperID: true))
    }

    // Updating from 1.10.0 or earlier straight to a Developer ID build: nothing
    // is on record yet, so the signature decides.
    func testNothingOnRecordResetsOnlyForDeveloperID() {
        XCTAssertTrue(StaleGrantReset.shouldReset(isGranted: false, certificate: "b", recordedCertificate: nil, isDeveloperID: true))
        XCTAssertFalse(StaleGrantReset.shouldReset(isGranted: false, certificate: "a", recordedCertificate: nil, isDeveloperID: false))
    }

    func testAdHocBuildsNeverReset() {
        XCTAssertFalse(StaleGrantReset.shouldReset(isGranted: false, certificate: nil, recordedCertificate: "a", isDeveloperID: false))
    }
}
