//
//  NativeVisibilityBridge.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import CoreGraphics
import Foundation

// A held native visibility restriction. Hiding lasts until invalidate() or until
// this process exits, when macOS drops it and restores the bar by itself.
protocol NativeVisibilityAssertion: AnyObject {
    func invalidate()
}

protocol NativeVisibilityProviding: AnyObject {
    var isAvailable: Bool { get }

    // Keeps only these system items and apps visible. The completion runs on the
    // main queue.
    func activate(allowedSystemItems: [Int],
                  allowedBundleIdentifiers: [String],
                  completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void)

    // Keeps only the status items whose middle x is at one of these positions,
    // whatever apps own them. The completion runs on the main queue; systems
    // without the position API report an error.
    func activateKeepingPositions(_ itemCenters: [CGFloat],
                                  completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void)
}

final class NativeVisibilityBridge: NativeVisibilityProviding {
    var isAvailable: Bool {
        return HBNativeVisibilityIsAvailable()
    }

    func activate(allowedSystemItems: [Int],
                  allowedBundleIdentifiers: [String],
                  completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void) {
        HBNativeVisibilityActivate(allowedSystemItems.map { NSNumber(value: $0) },
                                   allowedBundleIdentifiers) { handle, error in
            if let handle = handle {
                completion(.success(Handle(raw: handle)))
            } else {
                completion(.failure(error ?? NSError(domain: "HBNativeVisibility", code: 2)))
            }
        }
    }

    func activateKeepingPositions(_ itemCenters: [CGFloat],
                                  completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void) {
        HBNativeVisibilityActivateKeepingPositions(itemCenters.map { NSNumber(value: Double($0)) }) { handle, error in
            if let handle = handle {
                completion(.success(Handle(raw: handle)))
            } else {
                completion(.failure(error ?? NSError(domain: "HBNativeVisibility", code: 2)))
            }
        }
    }

    private final class Handle: NativeVisibilityAssertion {
        private var raw: Any?

        init(raw: Any) {
            self.raw = raw
        }

        func invalidate() {
            guard let raw = raw else { return }
            self.raw = nil
            HBNativeVisibilityInvalidate(raw)
        }

        deinit {
            invalidate()
        }
    }
}
