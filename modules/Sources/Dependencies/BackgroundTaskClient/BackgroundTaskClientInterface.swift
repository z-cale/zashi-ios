//
//  BackgroundTaskClientInterface.swift
//  Zashi
//

import ComposableArchitecture
import UIKit

extension DependencyValues {
    public var backgroundTask: BackgroundTaskClient {
        get { self[BackgroundTaskClient.self] }
        set { self[BackgroundTaskClient.self] = newValue }
    }
}

@DependencyClient
public struct BackgroundTaskClient {
    /// Begins a UIKit background task with a proper expiration handler and disables the idle timer
    /// so the screen stays on during long-running proof generation.
    public var beginTask: @Sendable (_ name: String) async -> UIBackgroundTaskIdentifier = { _ in .invalid }
    /// Ends the background task and re-enables the idle timer.
    public var endTask: @Sendable (_ id: UIBackgroundTaskIdentifier) async -> Void
}
