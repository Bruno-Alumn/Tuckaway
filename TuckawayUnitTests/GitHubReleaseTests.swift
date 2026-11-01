//
//  GitHubReleaseTests.swift
//  TuckawayUnitTests
//

import XCTest

final class GitHubReleaseTests: XCTestCase {
    func testFailedRollbackPreservesTheOnlyBackup() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let work = root.appendingPathComponent("work")
        let destination = root.appendingPathComponent("Installed.app")
        let backup = work.appendingPathComponent("Previous.app")
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        UpdateReplacementCleanup.discardWorkDirectory(work, destination: destination, backup: backup)
        XCTAssertTrue(fileManager.fileExists(atPath: backup.path))

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        UpdateReplacementCleanup.discardWorkDirectory(work, destination: destination, backup: backup)
        XCTAssertFalse(fileManager.fileExists(atPath: work.path))

        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        try fileManager.removeItem(at: destination)
        UpdateReplacementCleanup.discardWorkDirectory(work, destination: destination, backup: backup)
        XCTAssertFalse(fileManager.fileExists(atPath: work.path))
    }

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
    func testUpdateCheckScheduleHandlesClockChanges() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(UpdateCheckSchedule.isDue(lastCheck: nil, now: now, interval: 100))
        XCTAssertFalse(UpdateCheckSchedule.isDue(lastCheck: now.addingTimeInterval(-99), now: now, interval: 100))
        XCTAssertTrue(UpdateCheckSchedule.isDue(lastCheck: now.addingTimeInterval(-100), now: now, interval: 100))
        XCTAssertTrue(UpdateCheckSchedule.isDue(lastCheck: now.addingTimeInterval(1), now: now, interval: 100))
    }

    func testUpdateRequestIsFreshAndIdentifiesTheApp() {
        let url = URL(string: "https://example.com/releases/latest")!
        let request = GitHubRelease.updateRequest(url: url, currentVersion: "1.2.0")
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.timeoutInterval, 20)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Tuckaway/1.2.0")
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

    func testUpdateNotesPreserveIssueReferencesAtLineStart() {
        let body = "#437 Native hiding\ncontinues here.\n\n## Fixed\n\n- Clock clicks."
        XCTAssertEqual(GitHubRelease.updateNotes(fromMarkdown: body),
                       "#437 Native hiding\ncontinues here.\n\nFixed\n\n• Clock clicks.")
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
