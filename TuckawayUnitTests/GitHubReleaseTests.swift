//
//  GitHubReleaseTests.swift
//  TuckawayUnitTests
//

import XCTest

final class GitHubReleaseTests: XCTestCase {
    func testParsesTagsWithAndWithoutPrefix() {
        XCTAssertEqual(ReleaseVersion("v1.2.3")?.components, [1, 2, 3])
        XCTAssertEqual(ReleaseVersion("1.0")?.components, [1, 0])
        XCTAssertEqual(ReleaseVersion(" V2 ")?.components, [2])
    }

    func testRejectsNonNumericAndPrereleaseVersions() {
        XCTAssertNil(ReleaseVersion(""))
        XCTAssertNil(ReleaseVersion("v"))
        XCTAssertNil(ReleaseVersion("1.3.0-beta"))
        XCTAssertNil(ReleaseVersion("1..2"))
        XCTAssertNil(ReleaseVersion("latest"))
    }

    func testComparesNumericallyAndPadsMissingComponents() {
        XCTAssertLessThan(ReleaseVersion("1.9")!, ReleaseVersion("1.10")!)
        XCTAssertLessThan(ReleaseVersion("1.0.0")!, ReleaseVersion("1.0.1")!)
        XCTAssertEqual(ReleaseVersion("1.2")!, ReleaseVersion("1.2.0")!)
        XCTAssertFalse(ReleaseVersion("2.0")! < ReleaseVersion("1.99.99")!)
    }

    func testDecodesGitHubPayloadAndPicksAppArchive() throws {
        let json = """
        {
          "tag_name": "v1.1.0",
          "name": "Tuckaway 1.1.0",
          "body": "Notes",
          "html_url": "https://github.com/Bruno-Alumn/Tuckaway/releases/tag/v1.1.0",
          "draft": false,
          "prerelease": false,
          "assets": [
            {"name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt", "size": 10},
            {"name": "Other.zip", "browser_download_url": "https://example.com/Other.zip", "size": 20},
            {"name": "Tuckaway.zip", "browser_download_url": "https://example.com/Tuckaway.zip", "size": 30}
          ]
        }
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, ReleaseVersion("1.1.0"))
        XCTAssertEqual(release.appPackage?.name, "Tuckaway.zip")
        XCTAssertTrue(release.isUpdate(over: ReleaseVersion("1.0.0")!))
        XCTAssertFalse(release.isUpdate(over: ReleaseVersion("1.1")!))
        XCTAssertFalse(release.isUpdate(over: ReleaseVersion("1.2.0")!))
    }

    func testPrefersDiskImageOverZip() throws {
        let json = """
        {"tag_name": "v1.2.0", "name": null, "body": null,
         "html_url": "https://github.com/Bruno-Alumn/Tuckaway/releases/tag/v1.2.0",
         "draft": false, "prerelease": false, "assets": [
            {"name": "Tuckaway.zip", "browser_download_url": "https://example.com/Tuckaway.zip", "size": 30},
            {"name": "Other.dmg", "browser_download_url": "https://example.com/Other.dmg", "size": 40},
            {"name": "Tuckaway.dmg", "browser_download_url": "https://example.com/Tuckaway.dmg", "size": 50}
         ]}
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.appPackage?.name, "Tuckaway.dmg")
    }

    func testIgnoresDraftsAndPrereleases() throws {
        let json = """
        {"tag_name": "v9.0.0", "name": null, "body": null,
         "html_url": "https://github.com/Bruno-Alumn/Tuckaway/releases/tag/v9.0.0",
         "draft": false, "prerelease": true, "assets": []}
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertFalse(release.isUpdate(over: ReleaseVersion("1.0.0")!))
        XCTAssertNil(release.appPackage)
    }

    func testDownloadSizeMustMatchReleaseMetadata() {
        XCTAssertTrue(GitHubRelease.Asset.isCompleteDownload(size: 4_194_304, expected: 4_194_304))
        XCTAssertFalse(GitHubRelease.Asset.isCompleteDownload(size: 1_024, expected: 4_194_304))
        XCTAssertFalse(GitHubRelease.Asset.isCompleteDownload(size: 4_194_305, expected: 4_194_304))
        XCTAssertFalse(GitHubRelease.Asset.isCompleteDownload(size: 0, expected: 0))
    }
    func testUpdateNotesDropInstallSectionsAndMarkdown() {
        let body = """
        ## Install

        Download **Tuckaway.dmg** below and drag it into Applications.

        ## Fixes

        - **Rearranging icons is smoother.** See the [changelog](https://example.com).
        - `Updater` cleans up.
        """
        XCTAssertEqual(GitHubRelease.updateNotes(fromMarkdown: body),
                       "Fixes\n\n• Rearranging icons is smoother. See the changelog.\n• Updater cleans up.")
    }

    func testUpdateNotesCutAtAParagraph() {
        let body = "First paragraph.\n\nSecond paragraph that does not fit."
        XCTAssertEqual(GitHubRelease.updateNotes(fromMarkdown: body, limit: 30), "First paragraph.…")
        XCTAssertEqual(GitHubRelease.updateNotes(fromMarkdown: "A very long single paragraph", limit: 6), "A very…")
    }

    func testUpdateNotesAreNilWhenNothingIsLeft() {
        XCTAssertNil(GitHubRelease.updateNotes(fromMarkdown: ""))
        XCTAssertNil(GitHubRelease.updateNotes(fromMarkdown: "## Download\n\nGet the DMG."))
    }
}
