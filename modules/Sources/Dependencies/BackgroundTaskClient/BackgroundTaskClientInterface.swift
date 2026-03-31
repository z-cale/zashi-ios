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

    /// Begin a continued processing task (iOS 26+). Returns true if the system accepted the
    /// request. On older iOS this is a no-op returning false — callers should always also
    /// use beginTask as a fallback.
    public var beginContinuedProcessing: @Sendable (
        _ identifier: String, _ title: String, _ subtitle: String
    ) async -> Bool = { _, _, _ in false }

    /// End the continued processing task.
    public var endContinuedProcessing: @Sendable () async -> Void = {}
}
