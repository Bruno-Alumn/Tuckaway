import Cocoa
import SwiftUI
import UniformTypeIdentifiers

final class AboutViewController: NSViewController {
    static func initWithStoryboard() -> AboutViewController {
        NSStoryboard(name: "Main", bundle: nil)
            .instantiateController(withIdentifier: "aboutVC") as! AboutViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 480, height: 330)
        let hostingView = NSHostingView(rootView: AboutSettingsView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}

private struct AboutSettingsView: View {
    private var versionText: String {
        let version = Bundle.main.releaseVersionNumber ?? ""
        let build = Bundle.main.buildVersionNumber ?? ""
        return "\("Version".localized) \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(verbatim: "Tuckaway")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 8)
            Text(verbatim: versionText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("Tidy your Mac’s menu bar.")
                .padding(.top, 10)
            HStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/Bruno-Alumn/Tuckaway")!) {
                    Label("Source code".localized, systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Text(verbatim: "·").foregroundStyle(.tertiary)
                Link(destination: URL(string: "https://github.com/Bruno-Alumn/Tuckaway/issues")!) {
                    Label("Report an issue".localized, systemImage: "exclamationmark.bubble")
                }
            }
            .labelStyle(.titleOnly)
            .padding(.top, 14)
            if Updater.isSupported {
                Button("Check for Updates…".localized) {
                    Updater.shared.checkForUpdates()
                }
                .controlSize(.small)
                .padding(.top, 12)
            }
            HStack(spacing: 8) {
                Button("Export Settings…".localized) { SettingsBackupFlow.export() }
                Button("Import Settings…".localized) { SettingsBackupFlow.importSettings() }
            }
            .controlSize(.small)
            .padding(.top, 8)
            Spacer(minLength: 16)
            VStack(spacing: 2) {
                Text("Independent MIT-licensed fork of Hidden Bar")
                Text("Original work © Dwarves Foundation · Tuckaway modifications © Bruno-Alumn")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Saves and loads SettingsBackup files. Importing relaunches Tuckaway, so
// hotkeys, sections and the login item all start from the imported values.
private enum SettingsBackupFlow {
    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tuckaway Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.data(from: SettingsBackup.export(from: .standard)).write(to: url)
        } catch {
            alert("Couldn’t export settings".localized, error.localizedDescription)
        }
    }

    static func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let values: [String: Any]
        do {
            values = try SettingsBackup.importable(SettingsBackup.values(from: Data(contentsOf: url)))
        } catch SettingsBackup.ImportError.newerFormat {
            return alert("Couldn’t import settings".localized,
                         "This file comes from a newer version of Tuckaway. Update Tuckaway, then try again.".localized)
        } catch {
            return alert("Couldn’t import settings".localized, "This file isn’t a Tuckaway settings file.".localized)
        }

        let confirm = NSAlert()
        confirm.messageText = "Replace your settings with the imported ones?".localized
        confirm.informativeText = "Tuckaway will relaunch to apply them.".localized
        confirm.addButton(withTitle: "Import".localized)
        confirm.addButton(withTitle: "Cancel".localized)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let defaults = UserDefaults.standard
        for key in SettingsBackup.keys where key != UserDefaults.Key.isAutoStart {
            defaults.set(values[key], forKey: key)
        }
        // Goes through the setter, which registers or removes the login item.
        if let autoStart = values[UserDefaults.Key.isAutoStart] as? Bool {
            Preferences.isAutoStart = autoStart
        }
        relaunch()
    }

    private static func relaunch() {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("TuckawayImport-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        shell.arguments = ["-c", Updater.relaunchScript, "tuckaway-relaunch",
                           String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path,
                           scratch.path, Updater.Tool.open, Updater.Tool.pgrep, "0.5", "1.5"]
        guard (try? shell.run()) != nil else {
            return alert("Settings imported".localized, "Quit and reopen Tuckaway to apply them.".localized)
        }
        NSApp.terminate(nil)
    }

    private static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
