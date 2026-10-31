//
//  GitHubRelease.swift
//  Tuckaway
//

import Foundation

// A dotted numeric version ("v1.2", "1.2.0"). Missing components compare as
// zero, so 1.2 == 1.2.0. Pre-release tags ("1.3.0-beta") are not offered:
// GitHub's /releases/latest never returns one, and parsing rejects them.
struct ReleaseVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        components = numbers
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

// The subset of GitHub's release JSON the updater needs.
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }

        static func isCompleteDownload(size actual: Int, expected: Int) -> Bool {
            return expected > 0 && actual == expected
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    var version: ReleaseVersion? { ReleaseVersion(tagName) }

    // The downloadable app. Releases ship a disk image ("Tuckaway.dmg"); a zip
    // is still accepted because v1.0.0 shipped one. Assets named after the app
    // win over other files of the same kind.
    var appPackage: Asset? {
        for suffix in [".dmg", ".zip"] {
            let matches = assets.filter { $0.name.lowercased().hasSuffix(suffix) }
            if let match = matches.first(where: { $0.name.lowercased().hasPrefix("tuckaway") }) ?? matches.first {
                return match
            }
        }
        return nil
    }

    // The release notes as plain text for the update alert: install and
    // download sections are dropped (the updater does that part), Markdown
    // markup is removed, and long notes are cut at a paragraph.
    var updateNotes: String? {
        body.flatMap { Self.updateNotes(fromMarkdown: $0) }
    }

    static func updateNotes(fromMarkdown markdown: String, limit: Int = 700) -> String? {
        let skippedHeadings: Set<String> = ["install", "installation", "download", "downloads"]
        var paragraphs: [String] = []
        var current: [String] = []
        var skipping = false
        func endParagraph() {
            if !current.isEmpty { paragraphs.append(current.joined(separator: "\n")) }
            current = []
        }
        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                endParagraph()
                let heading = plainText(String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces))
                skipping = skippedHeadings.contains(heading.lowercased())
                if !skipping && !heading.isEmpty { paragraphs.append(heading) }
            } else if line.isEmpty {
                endParagraph()
            } else if !skipping {
                current.append(plainText(line.hasPrefix("- ") || line.hasPrefix("* ") ? "• " + line.dropFirst(2) : line))
            }
        }
        endParagraph()

        var result = ""
        for paragraph in paragraphs {
            let next = result.isEmpty ? paragraph : result + "\n\n" + paragraph
            if next.count > limit {
                if result.isEmpty { result = String(paragraph.prefix(limit)) }
                return result + "…"
            }
            result = next
        }
        return result.isEmpty ? nil : result
    }

    // Links keep their text; bold and code markers go. Single * and _ stay,
    // since they also appear in ordinary text.
    private static func plainText(_ line: String) -> String {
        var text = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for marker in ["**", "__", "`"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        return text
    }

    // Whether this release should be offered to a user running `current`.
    func isUpdate(over current: ReleaseVersion) -> Bool {
        guard !draft, !prerelease, let version else { return false }
        return version > current
    }
}
