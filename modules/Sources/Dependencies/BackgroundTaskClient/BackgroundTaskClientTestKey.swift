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
        endTask: unimplemented("\(Self.self).endTask", placeholder: {}()),
        beginContinuedProcessing: unimplemented("\(Self.self).beginContinuedProcessing", placeholder: false),
        endContinuedProcessing: unimplemented("\(Self.self).endContinuedProcessing", placeholder: {}())
    )
}

extension BackgroundTaskClient {
    public static let noOp = Self(
        beginTask: { _ in .invalid },
        endTask: { _ in },
        beginContinuedProcessing: { _, _, _ in false },
        endContinuedProcessing: {}
    )
}
