//
//  LocalizationTests.swift
//  TuckawayUnitTests
//

import XCTest

// Every language must translate exactly the English strings, with the same
// placeholders, so a new string can't ship English-only by accident.
final class LocalizationTests: XCTestCase {
    // The source files, found next to this test, so it runs without the app bundle.
    private let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("hidden")

    private var languages: [String] {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? []
        return folders.filter { $0.hasSuffix(".lproj") && $0 != "Base.lproj" && $0 != "en.lproj" }
            .map { String($0.dropLast(".lproj".count)) }
    }

    private func strings(_ language: String) throws -> [String: String] {
        let url = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(language) doesn't parse")
    }

    private func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%[@d]")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { (text as NSString).substring(with: $0.range) }
    }

    func testEveryLanguageHasExactlyTheEnglishStrings() throws {
        let english = try strings("en")
        XCTAssertEqual(languages.count, 12, "languages: \(languages)")

        for language in languages {
            let translated = try strings(language)
            XCTAssertEqual(Set(translated.keys).subtracting(english.keys), [], "\(language) has unused strings")
            XCTAssertEqual(Set(english.keys).subtracting(translated.keys), [], "\(language) is missing strings")
            for (key, value) in english {
                guard let translation = translated[key] else { continue }
                XCTAssertEqual(placeholders(translation), placeholders(value), "\(language): \(key)")
                XCTAssertFalse(translation.isEmpty, "\(language): \(key)")
            }
        }
    }

    // A literal looked up with `.localized` that isn't in the English table
    // shows its key to every user, and the check above can't see it.
    func testEveryLocalizedLiteralIsInTheEnglishStrings() throws {
        let english = try strings("en")
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)"\.localized"#)
        var missing: [String] = []
        let files = FileManager.default.enumerator(at: resources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in literal.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let key = (source as NSString).substring(with: match.range(at: 1))
                    .replacingOccurrences(of: "\\\"", with: "\"")
                if english[key] == nil {
                    missing.append("\(file.lastPathComponent): \(key)")
                }
            }
        }
        XCTAssertEqual(missing, [], "add these to en.lproj/Localizable.strings and the other languages")
    }
}
