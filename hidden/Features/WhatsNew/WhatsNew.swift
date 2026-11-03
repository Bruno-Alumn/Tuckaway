//
//  WhatsNew.swift
//  Tuckaway
//

import Foundation

// "What's New" after an update: the notes for the version now running, so
// people who update automatically learn about a new feature without reading the
// release page. The notes are baked into the app bundle
// (scripts/embed-release-notes.sh), because the App Store build has no network
// access and a released app can't fetch notes for its own version later.
struct ReleaseNotes: Equatable {
    // Dotted versions, inclusive. One file can cover a run of releases so a
    // larger update doesn't pile up a window per version.
    let first: ReleaseVersion
    let last: ReleaseVersion
    // Markdown, as written in CHANGELOG.md.
    let body: String
}

enum WhatsNew {
    static let resourceName = "WhatsNew"

    // `versions: 1.8.0-1.9.0` (or a single version), a blank line, then the
    // notes. Without the header the file is refused rather than shown for every
    // version: a typo must not pop the window up on each launch.
    static func parse(_ text: String) -> ReleaseNotes? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let headerIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let header = lines[headerIndex].trimmingCharacters(in: .whitespaces)
        guard header.hasPrefix(headerPrefix) else { return nil }
        let bounds = header.dropFirst(headerPrefix.count)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = ReleaseVersion(bounds.first ?? ""),
              let last = bounds.count > 1 ? ReleaseVersion(bounds[1]) : first,
              first <= last else { return nil }
        let body = lines[(headerIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return ReleaseNotes(first: first, last: last, body: body)
    }

    private static let headerPrefix = "versions:"

    // Whether to show the notes to someone running `running`, who last saw
    // `lastSeen` (nil on a first launch). Updating from 1.8.0 straight to 2.0.0
    // still shows a file that covers both. Nothing is shown when the version
    // can't be read or the note is about another release.
    static func shouldShow(_ notes: ReleaseNotes, running: String?, lastSeen: String?) -> Bool {
        guard let running = ReleaseVersion(running ?? ""),
              running >= notes.first, running <= notes.last else { return false }
        guard let lastSeen = ReleaseVersion(lastSeen ?? "") else { return true }
        // Notes for a version already seen (or older than it) are old news.
        return running > lastSeen
    }

    // Markdown's headings and emphasis read as noise in a native window, so the
    // notes are shown as changelog text: version and section headings on their
    // own, list items with a bullet.
    static func plainText(_ markdown: String) -> String {
        // Blank lines separate sections, so they have to survive: `split` alone
        // would drop them and run the sections together.
        markdown.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                return trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("- ") {
                return "• " + trimmed.dropFirst(2)
            }
            return trimmed
        }
        .joined(separator: "\n")
        .replacingOccurrences(of: "**", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
