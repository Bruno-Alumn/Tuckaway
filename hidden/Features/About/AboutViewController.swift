import Cocoa
import SwiftUI

final class AboutViewController: NSViewController {
    static func initWithStoryboard() -> AboutViewController {
        NSStoryboard(name: "Main", bundle: nil)
            .instantiateController(withIdentifier: "aboutVC") as! AboutViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 480, height: 300)
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
