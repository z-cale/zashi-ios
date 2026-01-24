//
//  RootPIR.swift
//  secant
//
//  Created for PIR Integration Demo
//

import Combine
import ComposableArchitecture
import Foundation
import ZcashLightClientKit
import Generated
import Models

/// PIR-related state and actions for the Root reducer
extension Root {
    public struct PIRState: Equatable {
        /// Whether PIR debug overlay is visible
        public var isOverlayVisible: Bool = false

        /// Current PIR system state
        public var pirState: PIRCheckerState = .uninitialized

        /// Recent PIR check results for display
        public var recentResults: [PIRCheckResultDisplay] = []

        /// Server status info
        public var serverStatus: PIRServerStatusDisplay?

        /// PIR cutoff height
        public var cutoffHeight: BlockHeight?

        /// Sample nullifier for demo testing
        public var testNullifier: String = ""

        /// Whether a check is in progress
        public var isChecking: Bool = false

        /// Wallet nullifiers fetched from database
        public var walletNullifiers: [WalletNullifier] = []

        /// Whether we're fetching nullifiers
        public var isFetchingNullifiers: Bool = false

        public init() {}
    }

    /// A nullifier from the wallet database
    public struct WalletNullifier: Equatable, Identifiable {
        public let id: String  // hex nullifier
        public let pool: String  // "sapling" or "orchard"
        public let shortHex: String  // first 16 chars for display

        public init(hex: String, pool: String) {
            self.id = hex
            self.pool = pool
            self.shortHex = String(hex.prefix(16)) + "..."
        }
    }

    /// Display-friendly PIR check result
    public struct PIRCheckResultDisplay: Equatable, Identifiable {
        public let id: UUID
        public let timestamp: Date
        public let nullifierShort: String
        public let isSpent: Bool
        public let spentAtHeight: BlockHeight?
        public let uploadKB: Double
        public let downloadKB: Double
        public let totalMs: Double

        public init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            nullifierShort: String,
            isSpent: Bool,
            spentAtHeight: BlockHeight? = nil,
            uploadKB: Double = 0,
            downloadKB: Double = 0,
            totalMs: Double = 0
        ) {
            self.id = id
            self.timestamp = timestamp
            self.nullifierShort = nullifierShort
            self.isSpent = isSpent
            self.spentAtHeight = spentAtHeight
            self.uploadKB = uploadKB
            self.downloadKB = downloadKB
            self.totalMs = totalMs
        }
    }

    /// Display-friendly PIR server status
    public struct PIRServerStatusDisplay: Equatable {
        public let isAvailable: Bool
        public let status: String
        public let pirDbHeight: BlockHeight
        public let numNullifiers: String
        public let numBuckets: String
        public let rebuildInProgress: Bool
        public let pendingBlocks: Int

        public init(
            isAvailable: Bool = false,
            status: String = "unknown",
            pirDbHeight: BlockHeight = 0,
            numNullifiers: String = "0",
            numBuckets: String = "0",
            rebuildInProgress: Bool = false,
            pendingBlocks: Int = 0
        ) {
            self.isAvailable = isAvailable
            self.status = status
            self.pirDbHeight = pirDbHeight
            self.numNullifiers = numNullifiers
            self.numBuckets = numBuckets
            self.rebuildInProgress = rebuildInProgress
            self.pendingBlocks = pendingBlocks
        }
    }

    /// PIR checker state (simplified for display)
    public enum PIRCheckerState: Equatable {
        case uninitialized
        case initializing
        case ready
        case checking(nullifier: String)
        case error(String)

        public var displayText: String {
            switch self {
            case .uninitialized: return "Not Initialized"
            case .initializing: return "Initializing..."
            case .ready: return "Ready"
            case .checking(let nf): return "Checking \(nf.prefix(8))..."
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    public indirect enum PIRAction {
        case toggleOverlay
        case initializePIR
        case pirInitialized
        case paramsReceived(PirParamsResponse)
        case pirInitializationFailed(String)
        case fetchStatus
        case statusFetched(PIRServerStatusDisplay)
        case setTestNullifier(String)
        case checkNullifier
        case checkResult(PIRCheckResultDisplay)
        case checkFailed(String)
        case clearResults
        case reset
        case fetchWalletNullifiers
        case walletNullifiersFetched([WalletNullifier])
        case selectWalletNullifier(WalletNullifier)
    }

    public func pirReduce() -> Reduce<Root.State, Root.Action> {
        Reduce { state, action in
            switch action {
            case .pir(.toggleOverlay):
                state.pirState.isOverlayVisible.toggle()
                if state.pirState.isOverlayVisible && state.pirState.pirState == .uninitialized {
                    return .send(.pir(.initializePIR))
                }
                return .none

            case .pir(.initializePIR):
                state.pirState.pirState = .initializing
                return .run { send in
                    // Fetch real PIR params from server
                    let params = try await sdkSynchronizer.getPIRParams()
                    if params.pirReady {
                        await send(.pir(.pirInitialized))
                        await send(.pir(.paramsReceived(params)))
                        await send(.pir(.fetchStatus))
                        await send(.pir(.fetchWalletNullifiers))
                    } else {
                        await send(.pir(.pirInitializationFailed("PIR service not ready on server")))
                    }
                } catch: { error, send in
                    await send(.pir(.pirInitializationFailed(error.localizedDescription)))
                }

            case .pir(.pirInitialized):
                state.pirState.pirState = .ready
                return .none

            case .pir(.paramsReceived(let params)):
                state.pirState.cutoffHeight = BlockHeight(params.pirCutoffHeight)
                return .none

            case .pir(.pirInitializationFailed(let message)):
                state.pirState.pirState = .error(message)
                return .none

            case .pir(.fetchStatus):
                return .run { send in
                    // Fetch real status from server
                    let serverStatus = try await sdkSynchronizer.getPIRStatus()
                    let status = PIRServerStatusDisplay(
                        isAvailable: serverStatus.available,
                        status: serverStatus.status,
                        pirDbHeight: BlockHeight(serverStatus.pirDbHeight),
                        numNullifiers: formatNumber(Int(serverStatus.numNullifiers)),
                        numBuckets: formatNumber(Int(serverStatus.numBuckets)),
                        rebuildInProgress: serverStatus.rebuildInProgress,
                        pendingBlocks: Int(serverStatus.pendingBlocks)
                    )
                    await send(.pir(.statusFetched(status)))
                } catch: { error, send in
                    let status = PIRServerStatusDisplay(
                        isAvailable: false,
                        status: "error: \(error.localizedDescription)",
                        pirDbHeight: 0,
                        numNullifiers: "0",
                        numBuckets: "0"
                    )
                    await send(.pir(.statusFetched(status)))
                }

            case .pir(.statusFetched(let status)):
                state.pirState.serverStatus = status
                return .none

            case .pir(.setTestNullifier(let nullifier)):
                state.pirState.testNullifier = nullifier
                return .none

            case .pir(.checkNullifier):
                guard !state.pirState.testNullifier.isEmpty else { return .none }
                guard state.pirState.pirState == .ready else { return .none }

                let nullifier = state.pirState.testNullifier
                state.pirState.pirState = .checking(nullifier: nullifier)
                state.pirState.isChecking = true

                return .run { send in
                    // Simulate PIR query
                    try await Task.sleep(nanoseconds: 800_000_000)

                    let result = PIRCheckResultDisplay(
                        nullifierShort: String(nullifier.prefix(16)) + "...",
                        isSpent: Bool.random(),
                        spentAtHeight: Bool.random() ? BlockHeight.random(in: 1_500_000...2_400_000) : nil,
                        uploadKB: 416.0,
                        downloadKB: 32.0,
                        totalMs: Double.random(in: 400...800)
                    )
                    await send(.pir(.checkResult(result)))
                } catch: { error, send in
                    await send(.pir(.checkFailed(error.localizedDescription)))
                }

            case .pir(.checkResult(let result)):
                state.pirState.pirState = .ready
                state.pirState.isChecking = false
                state.pirState.recentResults.insert(result, at: 0)
                if state.pirState.recentResults.count > 10 {
                    state.pirState.recentResults.removeLast()
                }
                return .none

            case .pir(.checkFailed(let message)):
                state.pirState.pirState = .error(message)
                state.pirState.isChecking = false
                return .none

            case .pir(.clearResults):
                state.pirState.recentResults.removeAll()
                return .none

            case .pir(.reset):
                state.pirState = PIRState()
                return .none

            case .pir(.fetchWalletNullifiers):
                state.pirState.isFetchingNullifiers = true
                return .run { send in
                    var nullifiers: [WalletNullifier] = []

                    // Query sapling nullifiers
                    let saplingQuery = """
                        SELECT hex(nf) as nullifier FROM sapling_received_notes
                        WHERE nf IS NOT NULL
                        ORDER BY id DESC
                        LIMIT 20
                        """
                    let saplingResult = sdkSynchronizer.debugDatabaseSql(saplingQuery)

                    // Parse sapling results (format: "nullifier\n64charhex\n64charhex...")
                    let saplingLines = saplingResult.split(separator: "\n").dropFirst()
                    for line in saplingLines {
                        let hex = String(line).trimmingCharacters(in: .whitespaces)
                        if hex.count == 64 {
                            nullifiers.append(WalletNullifier(hex: hex, pool: "sapling"))
                        }
                    }

                    // Query orchard nullifiers
                    let orchardQuery = """
                        SELECT hex(nf) as nullifier FROM orchard_received_notes
                        WHERE nf IS NOT NULL
                        ORDER BY id DESC
                        LIMIT 20
                        """
                    let orchardResult = sdkSynchronizer.debugDatabaseSql(orchardQuery)

                    // Parse orchard results
                    let orchardLines = orchardResult.split(separator: "\n").dropFirst()
                    for line in orchardLines {
                        let hex = String(line).trimmingCharacters(in: .whitespaces)
                        if hex.count == 64 {
                            nullifiers.append(WalletNullifier(hex: hex, pool: "orchard"))
                        }
                    }

                    await send(.pir(.walletNullifiersFetched(nullifiers)))
                }

            case .pir(.walletNullifiersFetched(let nullifiers)):
                state.pirState.isFetchingNullifiers = false
                state.pirState.walletNullifiers = nullifiers
                return .none

            case .pir(.selectWalletNullifier(let nullifier)):
                state.pirState.testNullifier = nullifier.id
                return .none

            default:
                return .none
            }
        }
    }
}

// MARK: - Helpers

/// Format large numbers with K/M suffixes for display
private func formatNumber(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    } else if value >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

// MARK: - Placeholders

extension Root.PIRState {
    public static var initial: Self {
        .init()
    }
}
