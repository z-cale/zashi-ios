//
//  PIRCheckerInterface.swift
//  Zashi
//
//  Created for PIR Integration Demo
//

import Foundation
import Combine
import ComposableArchitecture
import ZcashLightClientKit

extension DependencyValues {
    public var pirCheckerClient: PIRCheckerClient {
        get { self[PIRCheckerClient.self] }
        set { self[PIRCheckerClient.self] = newValue }
    }
}

/// State of the PIR system
public enum PIRState: Equatable {
    case uninitialized
    case initializing
    case ready
    case checking(nullifier: String)
    case error(String)
}

/// Result from a PIR nullifier check
public struct PIRNullifierCheckResult: Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let nullifierHex: String
    public let isSpent: Bool
    public let spentAtHeight: BlockHeight?
    public let txIndex: UInt32?
    public let uploadBytes: UInt64
    public let downloadBytes: UInt64
    public let queryGenMs: Double
    public let decryptMs: Double
    public let totalMs: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        nullifierHex: String,
        isSpent: Bool,
        spentAtHeight: BlockHeight? = nil,
        txIndex: UInt32? = nil,
        uploadBytes: UInt64 = 0,
        downloadBytes: UInt64 = 0,
        queryGenMs: Double = 0,
        decryptMs: Double = 0,
        totalMs: Double = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.nullifierHex = nullifierHex
        self.isSpent = isSpent
        self.spentAtHeight = spentAtHeight
        self.txIndex = txIndex
        self.uploadBytes = uploadBytes
        self.downloadBytes = downloadBytes
        self.queryGenMs = queryGenMs
        self.decryptMs = decryptMs
        self.totalMs = totalMs
    }
}

/// PIR server status information
public struct PIRServerStatus: Equatable {
    public let isAvailable: Bool
    public let status: String
    public let pirDbHeight: BlockHeight
    public let numNullifiers: UInt64
    public let numBuckets: UInt64
    public let rebuildInProgress: Bool
    public let lastBuildTime: String

    public init(
        isAvailable: Bool = false,
        status: String = "unknown",
        pirDbHeight: BlockHeight = 0,
        numNullifiers: UInt64 = 0,
        numBuckets: UInt64 = 0,
        rebuildInProgress: Bool = false,
        lastBuildTime: String = ""
    ) {
        self.isAvailable = isAvailable
        self.status = status
        self.pirDbHeight = pirDbHeight
        self.numNullifiers = numNullifiers
        self.numBuckets = numBuckets
        self.rebuildInProgress = rebuildInProgress
        self.lastBuildTime = lastBuildTime
    }
}

@DependencyClient
public struct PIRCheckerClient {
    /// Stream of PIR state changes
    public var stateStream: () -> AnyPublisher<PIRState, Never> = {
        Empty().eraseToAnyPublisher()
    }

    /// Stream of PIR check results
    public var resultsStream: () -> AnyPublisher<PIRNullifierCheckResult, Never> = {
        Empty().eraseToAnyPublisher()
    }

    /// Current state of the PIR system
    public var currentState: () -> PIRState = { .uninitialized }

    /// Initialize the PIR system (fetch params, setup crypto)
    public var initialize: () async throws -> Void

    /// Check if PIR is ready for queries
    public var isReady: () -> Bool = { false }

    /// Get PIR cutoff height
    public var getCutoffHeight: () async -> BlockHeight? = { nil }

    /// Get PIR server status
    public var getServerStatus: () async throws -> PIRServerStatus

    /// Check a nullifier using PIR
    public var checkNullifier: (_ nullifierHex: String) async throws -> PIRNullifierCheckResult

    /// Check multiple nullifiers using PIR
    public var checkNullifiers: (_ nullifiers: [String]) async throws -> [PIRNullifierCheckResult]

    /// Reset the PIR system
    public var reset: () async -> Void

    /// Get recent check results for display
    public var getRecentResults: () -> [PIRNullifierCheckResult] = { [] }
}

extension PIRCheckerClient: TestDependencyKey {
    public static let testValue = PIRCheckerClient()

    public static let previewValue = PIRCheckerClient(
        stateStream: { Just(.ready).eraseToAnyPublisher() },
        resultsStream: { Empty().eraseToAnyPublisher() },
        currentState: { .ready },
        initialize: { },
        isReady: { true },
        getCutoffHeight: { BlockHeight(2_000_000) },
        getServerStatus: {
            PIRServerStatus(
                isAvailable: true,
                status: "ready",
                pirDbHeight: BlockHeight(2_500_000),
                numNullifiers: 15_000_000,
                numBuckets: 500_000,
                rebuildInProgress: false,
                lastBuildTime: "2025-01-23T10:00:00Z"
            )
        },
        checkNullifier: { nullifier in
            PIRNullifierCheckResult(
                nullifierHex: nullifier,
                isSpent: false,
                uploadBytes: 416_000,
                downloadBytes: 32_000,
                queryGenMs: 50,
                decryptMs: 10,
                totalMs: 500
            )
        },
        checkNullifiers: { nullifiers in
            nullifiers.map { nullifier in
                PIRNullifierCheckResult(
                    nullifierHex: nullifier,
                    isSpent: false,
                    uploadBytes: 416_000,
                    downloadBytes: 32_000,
                    queryGenMs: 50,
                    decryptMs: 10,
                    totalMs: 500
                )
            }
        },
        reset: { },
        getRecentResults: { [] }
    )
}
