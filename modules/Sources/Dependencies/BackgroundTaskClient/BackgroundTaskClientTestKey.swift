//
//  BackgroundTaskClientTestKey.swift
//  Zashi
//

import ComposableArchitecture
import UIKit
import XCTestDynamicOverlay

extension BackgroundTaskClient: TestDependencyKey {
    public static let testValue = Self(
        beginTask: unimplemented("\(Self.self).beginTask", placeholder: .invalid),
        endTask: unimplemented("\(Self.self).endTask", placeholder: {}())
    )
}

extension BackgroundTaskClient {
    public static let noOp = Self(
        beginTask: { _ in .invalid },
        endTask: { _ in }
    )
}
