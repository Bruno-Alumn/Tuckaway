//
//  WhatsNew.swift
//  Tuckaway
//

import Foundation

// "What's New" after an update: the notes for the releases since the one last
// run, so people who update automatically learn about a new feature without
// reading the release page. CHANGELOG.md's released sections are baked into the
// app bundle (scripts/embed-release-notes.sh), because the App Store build has no
// network access and a released app can't fetch notes for its own version later.
struct ReleaseNotes: Equatable {
    let version: ReleaseVersion
    // The changelog heading without its `## `, e.g. "v1.8.0 (2026-11-02)".
    let heading: String
    // Markdown, as written in CHANGELOG.md.
    let body: String
}

enum WhatsNew {
    static let resourceName = "WhatsNew"

    // An update after a long time away shouldn't open a wall of text; the
    // newest releases say the most about what the app does now.
    static let maxReleases = 5

    // CHANGELOG.md's `## v1.8.0 (…)` sections, newest first. Anything else (the
    // title, `## Unreleased`) is skipped, so a malformed file shows nothing
    // rather than the wrong thing. Reading stops where the versions stop
    // going down: below Tuckaway's v1.0.0 the changelog keeps Hidden Bar's
    // history (v1.11.1 and older), which must never read as a newer release.
    static func parse(_ text: String) -> [ReleaseNotes] {
        var notes: [ReleaseNotes] = []
        var current: (version: ReleaseVersion, heading: String)?
        var lines: [Substring] = []

        func finishSection() {
            guard let current else { return }
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                notes.append(ReleaseNotes(version: current.version, heading: current.heading, body: body))
            }
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                finishSection()
                let heading = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                let name = heading.split(separator: " ").first.map(String.init) ?? ""
                current = ReleaseVersion(name).map { ($0, heading) }
                lines = []
                if let version = current?.version, let previous = notes.last?.version, version >= previous {
                    return notes
                }
            } else if current != nil {
                lines.append(line)
            }
        }
        finishSection()
        return notes
    }

    struct Plan: Equatable {
        // The version to remember as seen, if it changes.
        let recordSeen: String?
        let show: [ReleaseNotes]
    }

    // What to do at launch. `lastSeen` is nil both for a fresh install and for
    // someone updating from a version older than What's New, so the first
    // launch is passed in to tell them apart: a fresh install has the settings
    // to read, not a list of changes since a version it never ran.
    static func plan(notes: [ReleaseNotes], running: String?, lastSeen: String?,
                     isFirstLaunch: Bool) -> Plan {
        guard let running = ReleaseVersion(running ?? "") else { return Plan(recordSeen: nil, show: []) }
        let seen = ReleaseVersion(lastSeen ?? "")
        // Never record an older version: running an old copy once must not
        // bring back notes already read when the newer one returns.
        let isNewer = seen.map { running > $0 } ?? true
        let record = isNewer ? running.description : nil
        guard !isFirstLaunch else { return Plan(recordSeen: record, show: []) }
        let shown = notes.filter { note in
            guard note.version <= running else { return false }
            if let seen { return note.version > seen }
            return note.version == running
        }
        return Plan(recordSeen: record,
                    show: Array(shown.sorted { $0.version > $1.version }.prefix(maxReleases)))
    }

    // Markdown's headings, emphasis and code marks read as noise in a native
    // window, so the notes are shown as changelog text: headings on their own
    // line, list items with a bullet. With more than one release, each starts
    // with its heading.
    static func plainText(_ notes: [ReleaseNotes]) -> String {
        let sections = notes.map { note in
            notes.count > 1 ? note.heading + "\n\n" + note.body : note.body
        }
        return plainText(sections.joined(separator: "\n\n"))
    }

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
        .replacingOccurrences(of: "`", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
