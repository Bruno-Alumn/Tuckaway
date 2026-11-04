import Foundation

/// A throwaway `UserDefaults` suite for one test.
///
/// cfprefsd writes an empty plist for every suite a process touched when that
/// process exits, even after `removePersistentDomain(forName:)` and deleting the
/// file in tearDown. So a test can't clean up its own file. Instead every suite
/// shares one prefix, and the first suite made in a run deletes the files earlier
/// runs left behind. At most one run's files remain.
struct TestDefaults {
    static let prefix = "TuckawayUnitTests."

    let suiteName: String
    let defaults: UserDefaults

    init(_ name: String) {
        Self.sweepEarlierRuns
        suiteName = "\(Self.prefix)\(name).\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static let preferences = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Preferences")

    // Older than any one test run, so a run going on in parallel keeps its files.
    private static let sweepEarlierRuns: Void = {
        let cutoff = Date().addingTimeInterval(-10 * 60)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: preferences, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "plist" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }()
}
