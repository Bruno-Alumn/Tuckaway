//
//  Updater.swift
//  Tuckaway
//

import AppKit
import Security

// Checks GitHub releases for a newer Tuckaway and installs it in place.
//
// Only the direct-download build updates itself. The App Store build is
// sandboxed without network access, and the App Store delivers its updates.
final class Updater {
    static let shared = Updater()

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/Bruno-Alumn/Tuckaway/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/Bruno-Alumn/Tuckaway/releases/latest")!

    private static let checkInterval: TimeInterval = 24 * 60 * 60

    static var isSupported: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    }

    private var isBusy = false
    private var timer: Timer?

    private init() {}

    // MARK: - Scheduling

    // Called once at launch: checks shortly after startup when a day has
    // passed since the last check, then re-evaluates every few hours.
    func start() {
        guard Self.isSupported else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.checkIfDue()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        guard Preferences.automaticallyChecksForUpdates else { return }
        if let last = Preferences.lastUpdateCheck, Date().timeIntervalSince(last) < Self.checkInterval { return }
        check(userInitiated: false)
    }

    // MARK: - Checking

    @objc func checkForUpdates() {
        check(userInitiated: true)
    }

    private var currentVersion: ReleaseVersion {
        #if DEBUG
        // Lets a dev build exercise the install path against a real release.
        if let override = ProcessInfo.processInfo.environment["TUCKAWAY_UPDATE_CURRENT_VERSION"],
           let version = ReleaseVersion(override) {
            return version
        }
        #endif
        return ReleaseVersion(Bundle.main.releaseVersionNumber ?? "") ?? ReleaseVersion("0")!
    }

    private func check(userInitiated: Bool) {
        guard Self.isSupported else {
            if userInitiated { NSWorkspace.shared.open(Self.releasesPageURL) }
            return
        }
        guard !isBusy else { return }
        isBusy = true

        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Tuckaway/\(Bundle.main.releaseVersionNumber ?? "0")", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let release: GitHubRelease?
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data {
                release = try? JSONDecoder().decode(GitHubRelease.self, from: data)
            } else {
                release = nil
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                Preferences.lastUpdateCheck = Date()
                self.handle(release: release, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handle(release: GitHubRelease?, userInitiated: Bool) {
        guard let release else {
            if userInitiated {
                showAlert(title: "Couldn’t check for updates".localized,
                          message: "Make sure you’re connected to the internet, then try again.".localized)
            }
            return
        }
        guard release.isUpdate(over: currentVersion), let version = release.version else {
            if userInitiated {
                showAlert(title: "You’re up to date".localized,
                          message: String(format: "Tuckaway %@ is the latest version.".localized, currentVersion.description))
            }
            return
        }
        if !userInitiated && Preferences.skippedUpdateVersion == version.description { return }
        offer(release, version: version)
    }

    private func offer(_ release: GitHubRelease, version: ReleaseVersion) {
        let alert = NSAlert()
        alert.messageText = String(format: "Tuckaway %@ is available".localized, version.description)
        var message = String(format: "You have version %@.".localized, currentVersion.description)
        if let notes = release.updateNotes {
            message += "\n\n" + notes
        }
        alert.informativeText = message
        let canInstall = release.appPackage != nil && installDestination != nil
        alert.addButton(withTitle: canInstall ? "Install and Relaunch".localized : "Download".localized)
        alert.addButton(withTitle: "Later".localized)
        alert.addButton(withTitle: "Skip This Version".localized)

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if canInstall, let asset = release.appPackage {
                install(asset, version: version, fallback: release.htmlURL)
            } else {
                NSWorkspace.shared.open(release.htmlURL)
            }
        case .alertThirdButtonReturn:
            Preferences.skippedUpdateVersion = version.description
        default:
            break
        }
    }

    // MARK: - Installing

    // The running bundle, when it can be replaced in place. A translocated or
    // read-only copy cannot, so the release page is opened instead.
    private var installDestination: URL? {
        let bundleURL = Bundle.main.bundleURL
        guard !bundleURL.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path)
        else { return nil }
        return bundleURL
    }

    private func install(_ asset: GitHubRelease.Asset, version: ReleaseVersion, fallback: URL) {
        guard !isBusy, let destination = installDestination else { return }
        isBusy = true

        URLSession.shared.downloadTask(with: asset.browserDownloadURL) { [weak self] location, response, error in
            let result: Result<URL, UpdateError>
            if let location, error == nil, (response as? HTTPURLResponse)?.statusCode == 200 {
                result = Result { try Self.prepare(download: location, named: asset.name, expecting: version, expectedSize: asset.size) }
                    .mapError { $0 as? UpdateError ?? .invalidArchive }
            } else {
                result = .failure(.downloadFailed)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                switch result {
                case .success(let newApp):
                    self.replace(destination, with: newApp, fallback: fallback)
                case .failure(let error):
                    self.showInstallFailure(error, fallback: fallback)
                }
            }
        }.resume()
    }

    enum UpdateError: Error {
        case downloadFailed
        case invalidArchive
        case wrongApp
        case invalidSignature
        case replaceFailed
    }

    private static let workDirectoryPrefix = "TuckawayUpdate-"

    // Copies the app out of the disk image (or zip) and checks it is a signed
    // Tuckaway of the advertised version before anything on disk is touched.
    // Everything lives in one work folder, deleted again if anything fails.
    private static func prepare(download: URL, named name: String, expecting version: ReleaseVersion,
                                expectedSize: Int) throws -> URL {
        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: download.path)
        let actualSize = (attributes[.size] as? NSNumber)?.intValue ?? -1
        guard GitHubRelease.Asset.isCompleteDownload(size: actualSize, expected: expectedSize) else {
            throw UpdateError.invalidArchive
        }
        let workDirectory = fileManager.temporaryDirectory.appendingPathComponent(workDirectoryPrefix + UUID().uuidString)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        do {
            return try unpack(download: download, named: name, expecting: version, in: workDirectory)
        } catch {
            try? fileManager.removeItem(at: workDirectory)
            throw error
        }
    }

    private static func unpack(download: URL, named name: String, expecting version: ReleaseVersion, in workDirectory: URL) throws -> URL {
        let fileManager = FileManager.default
        let isDiskImage = name.lowercased().hasSuffix(".dmg")
        let package = workDirectory.appendingPathComponent(isDiskImage ? "update.dmg" : "update.zip")
        try fileManager.moveItem(at: download, to: package)

        let extracted = workDirectory.appendingPathComponent("extracted")
        if isDiskImage {
            let mountPoint = workDirectory.appendingPathComponent("mount")
            // The detach has to be deferred from this scope, not from inside the
            // `if #available` branches, or it runs before the app is copied out.
            // `diskutil image` has no detach; ejecting the mount point detaches
            // the image (a plain unmount would leave it attached).
            let attached: Bool
            let detach: (String, [String])
            if #available(macOS 27.0, *) {
                attached = run("/usr/bin/diskutil", ["image", "attach", package.path, "--readOnly", "--nobrowse", "--mountPoint", mountPoint.path])
                detach = ("/usr/bin/diskutil", ["eject", mountPoint.path])
            } else {
                attached = run("/usr/bin/hdiutil", ["attach", package.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path])
                detach = ("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            }
            guard attached else { throw UpdateError.invalidArchive }
            defer { run(detach.0, detach.1) }
            let mounted = (try? fileManager.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)) ?? []
            guard let mountedApp = mounted.first(where: { $0.pathExtension == "app" }),
                  run("/usr/bin/ditto", [mountedApp.path, extracted.appendingPathComponent(mountedApp.lastPathComponent).path])
            else { throw UpdateError.invalidArchive }
        } else {
            guard run("/usr/bin/ditto", ["-x", "-k", package.path, extracted.path]) else { throw UpdateError.invalidArchive }
        }

        let candidates = (try? fileManager.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)) ?? []
        guard let app = candidates.first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: app)
        else { throw UpdateError.invalidArchive }

        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let bundleVersion = ReleaseVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""),
              bundleVersion == version
        else { throw UpdateError.wrongApp }

        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]),
              isSignedLikeThisApp(app)
        else { throw UpdateError.invalidSignature }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    // Whether `app` satisfies the running app's designated requirement: same
    // bundle ID, signed by the same certificate. That keeps a tampered or
    // re-signed download out, and is the same identity macOS uses to keep
    // Tuckaway's permissions across updates. An ad-hoc signed running app
    // (releases before 1.2) has no certificate to match, so it accepts the
    // update on the codesign check alone.
    private static func isSignedLikeThisApp(_ app: URL) -> Bool {
        var runningCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &runningCode) == errSecSuccess,
              let runningCode
        else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(runningCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any]
        else { return false }
        let flags = (information[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if flags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return true }

        var requirement: SecRequirement?
        var updateCode: SecStaticCode?
        guard SecCodeCopyDesignatedRequirement(runningCode, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &updateCode) == errSecSuccess,
              let updateCode
        else { return false }
        return SecStaticCodeCheckValidity(updateCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // Swaps the bundles (macOS lets a running app's bundle be moved), then
    // relaunches from a shell that waits for this process to exit first and
    // deletes the work folder (download, unpacked copy and the old app).
    private func replace(_ destination: URL, with newApp: URL, fallback: URL) {
        let fileManager = FileManager.default
        // newApp is <work folder>/extracted/Tuckaway.app.
        let workDirectory = newApp.deletingLastPathComponent().deletingLastPathComponent()
        let isOurWorkDirectory = workDirectory.lastPathComponent.hasPrefix(Self.workDirectoryPrefix)
            && workDirectory.deletingLastPathComponent().resolvingSymlinksInPath().path
                == fileManager.temporaryDirectory.resolvingSymlinksInPath().path
        let backup = workDirectory.appendingPathComponent("Previous.app")
        do {
            try fileManager.moveItem(at: destination, to: backup)
            do {
                try fileManager.moveItem(at: newApp, to: destination)
            } catch {
                try? fileManager.moveItem(at: backup, to: destination)
                throw error
            }
        } catch {
            if isOurWorkDirectory { try? fileManager.removeItem(at: workDirectory) }
            showInstallFailure(.replaceFailed, fallback: fallback)
            return
        }

        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"; /bin/rm -rf \"$3\"",
            "tuckaway-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            destination.path,
            // Only ever a folder this updater created in the temporary directory.
            isOurWorkDirectory ? workDirectory.path : backup.path
        ]
        do {
            try relaunch.run()
        } catch {
            if isOurWorkDirectory { try? fileManager.removeItem(at: workDirectory) }
            showAlert(title: "Update installed".localized,
                      message: "Quit and reopen Tuckaway to finish updating.".localized)
            return
        }
        NSApp.terminate(nil)
    }

    private func showInstallFailure(_ error: UpdateError, fallback: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The update couldn’t be installed".localized
        switch error {
        case .downloadFailed:
            alert.informativeText = "The download didn’t finish. You can download the update from GitHub instead.".localized
        case .invalidArchive, .wrongApp, .invalidSignature:
            alert.informativeText = "The downloaded file didn’t contain a valid copy of Tuckaway, so nothing was changed. You can download the update from GitHub instead.".localized
        case .replaceFailed:
            alert.informativeText = "Tuckaway couldn’t replace itself in its current folder. You can download the update from GitHub instead.".localized
        }
        alert.addButton(withTitle: "Open Release Page".localized)
        alert.addButton(withTitle: "Cancel".localized)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(fallback)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
