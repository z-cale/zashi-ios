//
//  PIRCheckerLiveKey.swift
//  Zashi
//
//  Created for PIR Integration Demo
//

import Foundation
import Combine
import ComposableArchitecture
import ZcashLightClientKit

extension PIRCheckerClient: DependencyKey {
    public static let liveValue: PIRCheckerClient = {
        let impl = PIRCheckerClientImpl()
        return PIRCheckerClient(
            stateStream: { impl.stateStream },
            resultsStream: { impl.resultsStream },
            currentState: { impl.currentState },
            initialize: { try await impl.initialize() },
            isReady: { impl.isReady },
            getCutoffHeight: { await impl.getCutoffHeight() },
            getServerStatus: { try await impl.getServerStatus() },
            checkNullifier: { try await impl.checkNullifier($0) },
            checkNullifiers: { try await impl.checkNullifiers($0) },
            reset: { await impl.reset() },
            getRecentResults: { impl.recentResults }
        )
    }()
}

/// Actor implementation for thread-safe PIR operations
actor PIRCheckerClientImpl {
    private var pirChecker: PIRChecker?
    private var _currentState: PIRState = .uninitialized
    private var _recentResults: [PIRNullifierCheckResult] = []
    private let maxRecentResults = 50

    private let stateSubject = CurrentValueSubject<PIRState, Never>(.uninitialized)
    private let resultsSubject = PassthroughSubject<PIRNullifierCheckResult, Never>()

    nonisolated var stateStream: AnyPublisher<PIRState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    nonisolated var resultsStream: AnyPublisher<PIRNullifierCheckResult, Never> {
        resultsSubject.eraseToAnyPublisher()
    }

    nonisolated var currentState: PIRState {
        stateSubject.value
    }

    nonisolated var isReady: Bool {
        stateSubject.value == .ready
    }

    nonisolated var recentResults: [PIRNullifierCheckResult] {
        // Note: This is simplified; in production you'd want proper synchronization
        []
    }

    func initialize() async throws {
        updateState(.initializing)

        @Dependency(\.sdkSynchronizer) var sdkSynchronizer

        // Get the synchronizer and create PIR checker
        // Note: This is a simplified implementation. In production, you'd need
        // to get the actual SDKSynchronizer instance from somewhere.

        // For now, we'll simulate initialization
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        updateState(.ready)
    }

    func getCutoffHeight() async -> BlockHeight? {
        // Return simulated cutoff height for demo
        return BlockHeight(2_000_000)
    }

    func getServerStatus() async throws -> PIRServerStatus {
        @Dependency(\.sdkSynchronizer) var sdkSynchronizer

        do {
            let status = try await sdkSynchronizer.latestState().latestBlockHeight

            // For demo, return simulated status based on actual chain height
            return PIRServerStatus(
                isAvailable: true,
                status: "ready",
                pirDbHeight: status,
                numNullifiers: 15_000_000,
                numBuckets: 500_000,
                rebuildInProgress: false,
                lastBuildTime: ISO8601DateFormatter().string(from: Date())
            )
        } catch {
            return PIRServerStatus(
                isAvailable: false,
                status: "error: \(error.localizedDescription)",
                pirDbHeight: 0,
                numNullifiers: 0,
                numBuckets: 0,
                rebuildInProgress: false,
                lastBuildTime: ""
            )
        }
    }

    func checkNullifier(_ nullifierHex: String) async throws -> PIRNullifierCheckResult {
        guard isReady else {
            throw PIRCheckerClientError.notInitialized
        }

        updateState(.checking(nullifier: nullifierHex))

        let startTime = Date()

        // Simulate PIR query for demo
        // In production, this would call the actual PIRChecker
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second simulated query time

        let totalMs = Date().timeIntervalSince(startTime) * 1000

        let result = PIRNullifierCheckResult(
            nullifierHex: nullifierHex,
            isSpent: false, // Simulated result
            spentAtHeight: nil,
            txIndex: nil,
            uploadBytes: 416_000, // Typical InsPIRe query size
            downloadBytes: 32_000,
            queryGenMs: 50,
            decryptMs: 10,
            totalMs: totalMs
        )

        addResult(result)
        updateState(.ready)

        return result
    }

    func checkNullifiers(_ nullifiers: [String]) async throws -> [PIRNullifierCheckResult] {
        var results: [PIRNullifierCheckResult] = []

        for nullifier in nullifiers {
            let result = try await checkNullifier(nullifier)
            results.append(result)
        }

        return results
    }

    func reset() async {
        pirChecker = nil
        _recentResults.removeAll()
        updateState(.uninitialized)
    }

    private func updateState(_ newState: PIRState) {
        _currentState = newState
        stateSubject.send(newState)
    }

    private func addResult(_ result: PIRNullifierCheckResult) {
        _recentResults.insert(result, at: 0)
        if _recentResults.count > maxRecentResults {
            _recentResults.removeLast()
        }
        resultsSubject.send(result)
    }
}

// MARK: - Errors

public enum PIRCheckerClientError: Error, LocalizedError {
    case notInitialized
    case queryFailed(String)
    case serverUnavailable

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "PIR checker is not initialized. Call initialize() first."
        case .queryFailed(let message):
            return "PIR query failed: \(message)"
        case .serverUnavailable:
            return "PIR server is not available."
        }
    }
}
