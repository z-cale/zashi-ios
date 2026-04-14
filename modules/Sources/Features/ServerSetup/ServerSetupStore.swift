//
//  ServerSetup.swift
//  Zashi
//
//  Created by Lukáš Korba on 2024-02-07.
//

import Foundation
import ComposableArchitecture
import ZcashLightClientKit

import Generated
import SDKSynchronizer
import UserPreferencesStorage
import ZcashSDKEnvironment

extension LightWalletEndpoint: @retroactive Equatable {
    public static func == (lhs: LightWalletEndpoint, rhs: LightWalletEndpoint) -> Bool {
        lhs.host == rhs.host
        && lhs.port == rhs.port
        && lhs.streamingCallTimeoutInMillis == rhs.streamingCallTimeoutInMillis
        && lhs.singleCallTimeoutInMillis == rhs.singleCallTimeoutInMillis
        && lhs.secure == rhs.secure
    }
}

@Reducer
public struct ServerSetup {
    let streamingCallTimeoutInMillis = ZcashSDKEnvironment.ZcashSDKConstants.streamingCallTimeoutInMillis

    private enum CancelID {
        case evaluateServers
        case setServer
    }

    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action>?
        var connectionMode: UserPreferencesStorage.ConnectionMode
        var customServer: String
        var isEvaluatingServers = false
        var isUpdatingServer = false
        var activeSyncServer: String = ""
        var recommendedSyncServer: String?
        var initialConnectionMode: UserPreferencesStorage.ConnectionMode
        var initialCustomServer: String = ""
        var initialSelectedServer: String?
        var network: NetworkType = .mainnet
        var serverEvaluationRequestID = 0
        var selectedServer: String?
        var servers: [ZcashSDKEnvironment.Server]
        var topKServers: [ZcashSDKEnvironment.Server]

        public var hasChanges: Bool {
            let modeChanged = connectionMode != initialConnectionMode
            let serverChanged = selectedServer != initialSelectedServer
            let customLabel = String(localizable: .serverSetupCustom)
            let customChanged = connectionMode == .manual
                && selectedServer == customLabel
                && customServer != initialCustomServer
            return modeChanged || serverChanged || customChanged
        }

        public init(
            connectionMode: UserPreferencesStorage.ConnectionMode = .automatic,
            customServer: String = "",
            isEvaluatingServers: Bool = false,
            isUpdatingServer: Bool = false,
            recommendedSyncServer: String? = nil,
            network: NetworkType = .mainnet,
            serverEvaluationRequestID: Int = 0,
            selectedServer: String? = nil,
            servers: [ZcashSDKEnvironment.Server] = [],
            topKServers: [ZcashSDKEnvironment.Server] = []
        ) {
            self.connectionMode = connectionMode
            self.customServer = customServer
            self.isEvaluatingServers = isEvaluatingServers
            self.isUpdatingServer = isUpdatingServer
            self.recommendedSyncServer = recommendedSyncServer
            self.initialConnectionMode = connectionMode
            self.network = network
            self.serverEvaluationRequestID = serverEvaluationRequestID
            self.selectedServer = selectedServer
            self.servers = servers
            self.topKServers = topKServers
        }
    }

    public enum Action: Equatable, BindableAction {
        case alert(PresentationAction<Action>)
        case binding(BindingAction<State>)
        case connectionModeChanged(UserPreferencesStorage.ConnectionMode)
        case evaluatedServers(Int, [LightWalletEndpoint])
        case evaluateServers
        case onAppear
        case refreshServersTapped
        case serverSelected(String)
        case setServerTapped
        case switchFailed(ZcashError)
        case switchSucceeded(String)
    }

    public init() {}

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment
    @Dependency(\.userStoredPreferences) var userStoredPreferences

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .onAppear:
                state.network = zcashSDKEnvironment.network.networkType
                let syncConfig = zcashSDKEnvironment.serverConfig()
                state.activeSyncServer = syncConfig.serverString()
                state.recommendedSyncServer = nil

                if !state.topKServers.isEmpty {
                    let allServers = ZcashSDKEnvironment.servers(for: state.network)
                    state.servers = allServers.filter {
                        !state.topKServers.contains($0)
                    }
                } else {
                    state.servers = ZcashSDKEnvironment.servers(for: state.network)
                }

                // Load stored connection mode and selected server
                if let config = userStoredPreferences.selectedServers() {
                    state.connectionMode = config.mode
                    if config.mode == .manual, let server = config.servers.first {
                        if server.isCustom {
                            state.customServer = server.serverString()
                            state.selectedServer = String(localizable: .serverSetupCustom)
                        } else {
                            state.selectedServer = server.serverString()
                        }
                    }
                }

                state.initialConnectionMode = state.connectionMode
                state.initialSelectedServer = state.selectedServer
                state.initialCustomServer = state.customServer
                return state.topKServers.isEmpty ? .send(.evaluateServers) : .none

            case .alert(.dismiss):
                state.alert = nil
                return .none

            case .alert:
                return .none

            case .binding:
                return .none

            case .connectionModeChanged(let mode):
                state.connectionMode = mode
                if mode == .automatic {
                    state.selectedServer = state.initialSelectedServer
                    state.customServer = state.initialCustomServer
                } else if mode == .manual && state.topKServers.isEmpty {
                    return .send(.evaluateServers)
                }
                return .none

            case .evaluateServers:
                state.isEvaluatingServers = true
                state.serverEvaluationRequestID += 1
                let requestID = state.serverEvaluationRequestID
                let network = state.network
                return .run { send in
                    let kBestServers = await sdkSynchronizer.evaluateBestOf(
                        ZcashSDKEnvironment.endpoints(for: network),
                        300.0,
                        60.0,
                        100,
                        3,
                        network
                    )

                    await send(.evaluatedServers(requestID, kBestServers))
                }
                .cancellable(id: CancelID.evaluateServers, cancelInFlight: true)

            case .evaluatedServers(let requestID, let bestServers):
                guard requestID == state.serverEvaluationRequestID else {
                    return .none
                }

                state.isEvaluatingServers = false
                state.topKServers = bestServers.map {
                    if ZcashSDKEnvironment.Server.default.value(for: state.network) == $0.server() {
                        ZcashSDKEnvironment.Server.default
                    } else {
                        ZcashSDKEnvironment.Server.hardcoded("\($0.host):\($0.port)")
                    }
                }
                let allServers = ZcashSDKEnvironment.servers(for: state.network)
                state.servers = allServers.filter {
                    !state.topKServers.contains($0)
                }
                state.recommendedSyncServer = bestServers.first?.server()

                return .none

            case .refreshServersTapped:
                return .send(.evaluateServers)

            case .serverSelected(let serverString):
                state.selectedServer = serverString
                return .none

            case .setServerTapped:
                guard state.hasChanges else {
                    return .none
                }

                state.isUpdatingServer = true
                let network = state.network

                switch state.connectionMode {
                case .automatic:
                    // Use already-evaluated best server when available to avoid a redundant benchmark
                    let cachedRecommendation = state.recommendedSyncServer
                    let timeout = streamingCallTimeoutInMillis

                    return .run { send in
                        do {
                            let best: LightWalletEndpoint

                            if let cachedRecommendation,
                               let cached = UserPreferencesStorage.ServerConfig.endpoint(
                                   for: cachedRecommendation,
                                   streamingCallTimeoutInMillis: timeout
                               ) {
                                best = cached
                            } else {
                                let bestServers = await sdkSynchronizer.evaluateBestOf(
                                    ZcashSDKEnvironment.endpoints(for: network),
                                    300.0, 60.0, 100, 1, network
                                )
                                best = bestServers.first ?? ZcashSDKEnvironment.defaultEndpoint(for: network)
                            }

                            let currentEndpoint = zcashSDKEnvironment.endpoint()
                            if best.host != currentEndpoint.host || best.port != currentEndpoint.port {
                                try await sdkSynchronizer.switchToEndpoint(best)
                            }

                            let serverConfig = UserPreferencesStorage.ServerConfig(
                                host: best.host, port: best.port, isCustom: false
                            )
                            // Persist after switch succeeds. try? is intentional: the switch already
                            // happened so we don't want a persistence error to trigger switchFailed —
                            // worst case the user re-selects after a restart.
                            try? userStoredPreferences.setSelectedServers(.init(mode: .automatic, servers: []))
                            try? userStoredPreferences.setServer(serverConfig)

                            let bestServerString = "\(best.host):\(best.port)"
                            try await mainQueue.sleep(for: .seconds(1))
                            await send(.switchSucceeded(bestServerString))
                        } catch {
                            await send(.switchFailed(error.toZcashError()))
                        }
                    }
                    .cancellable(id: CancelID.setServer, cancelInFlight: true)

                case .manual:
                    // Switch to the user's selected server
                    let serverString = state.selectedServer == String(localizable: .serverSetupCustom)
                        ? state.customServer
                        : (state.selectedServer ?? "")

                    guard let endpoint = UserPreferencesStorage.ServerConfig.endpoint(
                        for: serverString,
                        streamingCallTimeoutInMillis: streamingCallTimeoutInMillis
                    ) else {
                        return .send(.switchFailed(ZcashError.synchronizerServerSwitch))
                    }

                    // Build the full config synchronously so we can write it as an intent
                    // before the async switch — this lets the Root benchmark observe manual
                    // mode immediately, and ensures a valid config even if the app is killed
                    // mid-switch.
                    let isCustom = !ZcashSDKEnvironment.isKnownEndpoint(
                        host: endpoint.host, port: endpoint.port, network: network
                    )
                    let serverConfig = UserPreferencesStorage.ServerConfig(
                        host: endpoint.host, port: endpoint.port, isCustom: isCustom
                    )
                    let previousConfig = userStoredPreferences.selectedServers()
                    try? userStoredPreferences.setSelectedServers(.init(mode: .manual, servers: [serverConfig]))

                    return .run { send in
                        do {
                            let currentEndpoint = zcashSDKEnvironment.endpoint()
                            if endpoint.host != currentEndpoint.host || endpoint.port != currentEndpoint.port {
                                try await sdkSynchronizer.switchToEndpoint(endpoint)
                            }

                            // Persist the legacy key after switch succeeds
                            try? userStoredPreferences.setServer(serverConfig)

                            let serverStr = "\(endpoint.host):\(endpoint.port)"
                            try await mainQueue.sleep(for: .seconds(1))
                            await send(.switchSucceeded(serverStr))
                        } catch {
                            // Revert the intent flag on failure
                            if let previousConfig {
                                try? userStoredPreferences.setSelectedServers(previousConfig)
                            }
                            await send(.switchFailed(error.toZcashError()))
                        }
                    }
                    .cancellable(id: CancelID.setServer, cancelInFlight: true)
                }

            case .switchFailed(let error):
                state.isUpdatingServer = false
                state.alert = AlertState.endpointSwitchFailed(error)
                return .none

            case .switchSucceeded(let bestServer):
                state.isUpdatingServer = false
                state.initialConnectionMode = state.connectionMode
                state.initialSelectedServer = state.selectedServer
                state.initialCustomServer = state.customServer
                state.activeSyncServer = bestServer
                return .none
            }
        }
    }
}

// MARK: Alerts

extension AlertState where Action == ServerSetup.Action {
    public static func endpointSwitchFailed(_ error: ZcashError) -> AlertState {
        AlertState {
            TextState(String(localizable: .serverSetupAlertFailedTitle))
        } actions: {
            ButtonState(action: .alert(.dismiss)) {
                TextState(String(localizable: .generalOk))
            }
        } message: {
            TextState(String(localizable: .serverSetupAlertFailedMessage(error.detailedMessage)))
        }
    }
}
