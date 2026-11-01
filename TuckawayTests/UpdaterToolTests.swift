//
//  UpdaterToolTests.swift
//  TuckawayTests
//

import XCTest
@testable import Tuckaway

final class UpdaterToolTests: XCTestCase {
    // 1.3.0 ran /usr/bin/diskutil, which doesn't exist, so every update on
    // macOS 27 failed as "didn't contain a valid copy of Tuckaway".
    func testInstallerToolsExist() {
        for tool in Updater.Tool.all {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: tool), tool)
        }
    }
}
