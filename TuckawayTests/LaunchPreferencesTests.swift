import XCTest
@testable import Tuckaway

// Settings opens on the first launch so a new user can find the app, and on
// later launches (logins, update relaunches) only when asked to.
final class LaunchPreferencesTests: XCTestCase {
    func testSettingsOpenOnTheFirstLaunchOnly() {
        XCTAssertTrue(AppDelegate.opensPreferencesOnLaunch(isFirstLaunch: true, showPreferencesOnLaunch: false))
        XCTAssertFalse(AppDelegate.opensPreferencesOnLaunch(isFirstLaunch: false, showPreferencesOnLaunch: false))
    }

    func testTheSettingStillOpensThemEveryLaunch() {
        XCTAssertTrue(AppDelegate.opensPreferencesOnLaunch(isFirstLaunch: false, showPreferencesOnLaunch: true))
    }

    func testShowingSettingsOnEveryLaunchIsOffByDefault() {
        XCTAssertEqual(AppDelegate.defaultPreferenceValues[UserDefaults.Key.isShowPreference] as? Bool, false)
    }
}
