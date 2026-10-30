import Cocoa
import SwiftUI

final class AboutViewController: NSViewController {
    static func initWithStoryboard() -> AboutViewController {
        NSStoryboard(name: "Main", bundle: nil)
            .instantiateController(withIdentifier: "aboutVC") as! AboutViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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

    private let brandPurple = Color(red: 0.55, green: 0.25, blue: 0.86)

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("Tuckaway")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text("Tidy your Mac’s menu bar.")
                    .foregroundStyle(.secondary)
                Text(verbatim: versionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(brandPurple.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 20) {
                Link("Source code".localized, destination: URL(string: "https://github.com/Bruno-Alumn/Tuckaway")!)
                Link("Report an issue".localized, destination: URL(string: "https://github.com/Bruno-Alumn/Tuckaway/issues")!)
            }
            .tint(brandPurple)
            VStack(spacing: 6) {
                Text("Independent MIT-licensed fork of Hidden Bar")
                Text("Original work © Dwarves Foundation")
                Text("Tuckaway modifications © Bruno-Alumn")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
