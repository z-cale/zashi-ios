//
//  BackgroundTaskClientLiveKey.swift
//  Zashi
//

import ComposableArchitecture
import UIKit
import os

private let logger = Logger(subsystem: "co.zodl", category: "BackgroundTaskClient")

extension BackgroundTaskClient: DependencyKey {
    public static let liveValue = Self(
        beginTask: { name in
            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = true
                var taskId: UIBackgroundTaskIdentifier = .invalid
                taskId = UIApplication.shared.beginBackgroundTask(withName: name) {
                    logger.warning("Background task '\(name)' expired by iOS — ending task")
                    UIApplication.shared.endBackgroundTask(taskId)
                    taskId = .invalid
                }
                return taskId
            }
        },
        endTask: { id in
            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = false
                guard id != .invalid else { return }
                UIApplication.shared.endBackgroundTask(id)
            }
        }
    )
}
