//
//  MenuBarItemGroupingTests.swift
//  TuckawayUnitTests
//

import XCTest

final class MenuBarItemGroupingTests: XCTestCase {
    private struct Item: Equatable {
        let name: String
        let app: String?
        let section: MenuBarSection
    }

    private func grouped(_ items: [Item]) -> [(MenuBarSection, [String])] {
        MenuBarItemGrouping.grouped(items, key: \.app, section: \.section).map { ($0.section, $0.items.map(\.name)) }
    }

    func testAnAppsIconsShareOneRow() {
        let result = grouped([
            Item(name: "dropbox-1", app: "dropbox", section: .hidden),
            Item(name: "istat", app: "istat", section: .hidden),
            Item(name: "dropbox-2", app: "dropbox", section: .hidden)
        ])
        XCTAssertEqual(result.map(\.1), [["dropbox-1", "dropbox-2"], ["istat"]])
        XCTAssertEqual(result.map(\.0), [.hidden, .hidden])
    }

    // macOS 27 keeps an app visible while any of its icons is on the visible
    // side, so the row goes in Visible.
    func testAnAppSplitAcrossTheArrowIsListedAsVisible() {
        let result = grouped([
            Item(name: "a-1", app: "a", section: .alwaysHidden),
            Item(name: "a-2", app: "a", section: .visible)
        ])
        XCTAssertEqual(result.map(\.0), [.visible])
        XCTAssertEqual(result.map(\.1), [["a-1", "a-2"]])
    }

    func testItemsWithoutAnAppStaySeparate() {
        let result = grouped([
            Item(name: "wifi", app: nil, section: .visible),
            Item(name: "battery", app: nil, section: .visible)
        ])
        XCTAssertEqual(result.map(\.1), [["wifi"], ["battery"]])
    }
}
