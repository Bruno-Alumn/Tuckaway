//
//  UpdaterToolTests.swift
//  TuckawayTests
//

import XCTest
@testable import Tuckaway

final class UpdaterToolTests: XCTestCase {
    // 1.3.0 ran /usr/bin/diskutil, which doesn't exist, so every update on
    // macOS 27 failed as "didn't contain a valid copy of Tuckaway".
    func testInstallerToolsExist() {
        for tool in Updater.Tool.all {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: tool), tool)
        }
    }
}

final class UpdaterRelaunchScriptTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("RelaunchScriptTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // A fake `open` that counts its calls, and a fake `pgrep` that reports the
    // app running from the given call on.
    private func run(runningFromCall: Int) throws -> (opens: Int, workFolderLeft: Bool) {
        let count = folder.appendingPathComponent("count")
        let open = folder.appendingPathComponent("open")
        let pgrep = folder.appendingPathComponent("pgrep")
        let work = folder.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try "#!/bin/sh\necho x >> \"\(count.path)\"\n".write(to: open, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n[ \"$(/usr/bin/wc -l < \"\(count.path)\")\" -ge \(runningFromCall) ]\n".write(to: pgrep, atomically: true, encoding: .utf8)
        for tool in [open, pgrep] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The "old process" is one that has already exited.
        shell.arguments = ["-c", Updater.relaunchScript, "test", "999999", "/Applications/Example.app",
                           work.path, open.path, pgrep.path, "0", "0"]
        try shell.run()
        shell.waitUntilExit()
        let opens = (try? String(contentsOf: count, encoding: .utf8))?.split(separator: "\n").count ?? 0
        return (opens, FileManager.default.fileExists(atPath: work.path))
    }

    func testRetriesUntilTheAppIsRunning() throws {
        let result = try run(runningFromCall: 3)
        XCTAssertEqual(result.opens, 3)
        XCTAssertFalse(result.workFolderLeft)
    }

    func testOpensOnceWhenTheFirstTryWorks() throws {
        XCTAssertEqual(try run(runningFromCall: 1).opens, 1)
    }

    func testGivesUpAfterTenTriesAndStillCleansUp() throws {
        let result = try run(runningFromCall: 99)
        XCTAssertEqual(result.opens, 10)
        XCTAssertFalse(result.workFolderLeft)
    }
}

final class UpdaterSignatureTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("UpdaterSignatureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // A minimal Tuckaway-shaped bundle, ad-hoc signed the way codesign -s - does
    // for anyone, so it passes codesign --verify.
    private func adHocApp(_ name: String) throws -> URL {
        let app = folder.appendingPathComponent("\(name).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.brunoalumn.tuckaway", "CFBundleExecutable": "Tuckaway",
                                   "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macOS.appendingPathComponent("Tuckaway").path)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: Updater.Tool.codesign)
        sign.arguments = ["--force", "--sign", "-", app.path]
        try sign.run()
        sign.waitUntilExit()
        XCTAssertEqual(sign.terminationStatus, 0)
        return app
    }

    func testReleaseRequirementParses() {
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(Updater.releaseRequirement as CFString, [], &requirement), errSecSuccess)
    }

    // An ad-hoc running app used to accept any download that passed
    // codesign --verify, which an attacker's ad-hoc bundle does.
    func testAdHocRunningAppRefusesAnAdHocUpdate() throws {
        let running = try adHocApp("Running")
        let update = try adHocApp("Update")

        XCTAssertFalse(Updater.isSignedLikeThisApp(update, runningApp: running))
    }

    // Runs only where a release is installed (not on CI): an ad-hoc build still
    // accepts a real release, so updating a Debug build keeps working.
    func testAdHocRunningAppAcceptsARelease() throws {
        let release = URL(fileURLWithPath: "/Applications/Tuckaway.app")
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(release as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(Updater.releaseRequirement as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
        else { throw XCTSkip("No release-signed Tuckaway in /Applications") }

        XCTAssertTrue(Updater.isSignedLikeThisApp(release, runningApp: try adHocApp("Running")))
    }
}
