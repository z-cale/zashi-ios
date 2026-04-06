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

    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action>?
        var customServer: String
        var isEvaluatingServers = false
        var isUpdatingServer = false
        var activeSyncServer: String = ""
        var initialCustomServer: String = ""
        var initialSelectedServers: Set<String> = []
        var network: NetworkType = .mainnet
        var selectedServers: Set<String> = []
        var servers: [ZcashSDKEnvironment.Server]
        var topKServers: [ZcashSDKEnvironment.Server]

        public var hasChanges: Bool {
            let customLabel = String(localizable: .serverSetupCustom)
            let customServerChanged = selectedServers.contains(customLabel) && customServer != initialCustomServer
            return selectedServers != initialSelectedServers || customServerChanged
        }

        public init(
            customServer: String = "",
            isEvaluatingServers: Bool = false,
            isUpdatingServer: Bool = false,
            network: NetworkType = .mainnet,
            selectedServers: Set<String> = [],
            servers: [ZcashSDKEnvironment.Server] = [],
            topKServers: [ZcashSDKEnvironment.Server] = []
        ) {
            self.customServer = customServer
            self.isEvaluatingServers = isEvaluatingServers
            self.isUpdatingServer = isUpdatingServer
            self.network = network
            self.selectedServers = selectedServers
            self.servers = servers
            self.topKServers = topKServers
        }
    }

    public enum Action: Equatable, BindableAction {
        case alert(PresentationAction<Action>)
        case binding(BindingAction<State>)
        case evaluatedServers([LightWalletEndpoint])
        case evaluateServers
        case onAppear
        case refreshServersTapped
        case serverToggled(String)
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

                if !state.topKServers.isEmpty {
                    let allServers = ZcashSDKEnvironment.servers(for: state.network)
                    state.servers = allServers.filter {
                        !state.topKServers.contains($0)
                    }
                } else {
                    state.servers = ZcashSDKEnvironment.servers(for: state.network)
                }

                // Load saved selected servers, filtering out stale entries that no longer
                // appear in the current server list (e.g. old custom servers stored without isCustom)
                let validServerValues = Set(
                    (state.topKServers + state.servers).map { $0.value(for: state.network) }
                )
                if let config = userStoredPreferences.selectedServers() {
                    var selected = Set<String>()
                    for server in config.servers {
                        if server.isCustom {
                            state.customServer = server.serverString()
                            selected.insert(String(localizable: .serverSetupCustom))
                        } else {
                            let serverStr = server.serverString()
                            if validServerValues.contains(serverStr) {
                                selected.insert(serverStr)
                            }
                        }
                    }
                    state.selectedServers = selected
                }

                state.initialSelectedServers = state.selectedServers
                state.initialCustomServer = state.customServer
                return state.topKServers.isEmpty ? .send(.evaluateServers) : .none

            case .alert(.dismiss):
                state.alert = nil
                return .none

            case .alert:
                return .none

            case .binding:
                return .none

            case .evaluateServers:
                state.isEvaluatingServers = true
                let network = state.network
                return .run { send in
                    let kBestServers = await sdkSynchronizer.evaluateBestOf(
                        ZcashSDKEnvironment.endpoints(for: network), // candidates
                        300.0,  // connectionTimeoutMs
                        60.0,   // evaluationTimeoutSec
                        100,    // blocksToDownload
                        3,      // topK
                        network
                    )

                    await send(.evaluatedServers(kBestServers))
                }

            case .evaluatedServers(let bestServers):
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

                return .none

            case .refreshServersTapped:
                return .send(.evaluateServers)

            case .serverToggled(let serverString):
                if state.selectedServers.contains(serverString) {
                    // Prevent deselecting the last server
                    guard state.selectedServers.count > 1 else { return .none }
                    state.selectedServers.remove(serverString)
                } else {
                    state.selectedServers.insert(serverString)
                }
                return .none

            case .setServerTapped:
                guard state.hasChanges && !state.selectedServers.isEmpty else {
                    return .none
                }

                state.isUpdatingServer = true

                // Persist selected servers
                do {
                    try self.persistSelectedServers(state: state)
                } catch {
                    state.isUpdatingServer = false
                    return .send(.switchFailed(ZcashError.unknown(error)))
                }

                // Build endpoints from selected servers
                let selectedEndpoints = state.selectedServers.compactMap { serverString -> LightWalletEndpoint? in
                    if serverString == String(localizable: .serverSetupCustom) {
                        return UserPreferencesStorage.ServerConfig.endpoint(
                            for: state.customServer,
                            streamingCallTimeoutInMillis: streamingCallTimeoutInMillis
                        )
                    }
                    return UserPreferencesStorage.ServerConfig.endpoint(
                        for: serverString,
                        streamingCallTimeoutInMillis: streamingCallTimeoutInMillis
                    )
                }

                guard !selectedEndpoints.isEmpty else {
                    return .send(.switchFailed(ZcashError.synchronizerServerSwitch))
                }

                let network = state.network

                // Benchmark selected endpoints to find the best for sync
                return .run { [selectedEndpoints] send in
                    do {
                        let bestServers = await sdkSynchronizer.evaluateBestOf(
                            selectedEndpoints, // candidates
                            300.0,  // connectionTimeoutMs
                            60.0,   // evaluationTimeoutSec
                            100,    // blocksToDownload
                            1,      // topK (best single server for sync)
                            network
                        )

                        let best = bestServers.first ?? selectedEndpoints[0]

                        // Switch sync endpoint to the best server
                        let currentEndpoint = zcashSDKEnvironment.endpoint()
                        if best.host != currentEndpoint.host || best.port != currentEndpoint.port {
                            try await sdkSynchronizer.switchToEndpoint(best)
                        }

                        // Persist the best server as the sync endpoint
                        let isCustom = !ZcashSDKEnvironment.isKnownEndpoint(
                            host: best.host,
                            port: best.port,
                            network: network
                        )
                        let serverConfig = UserPreferencesStorage.ServerConfig(
                            host: best.host,
                            port: best.port,
                            isCustom: isCustom
                        )
                        try? userStoredPreferences.setServer(serverConfig)

                        let bestServerString = "\(best.host):\(best.port)"
                        try await mainQueue.sleep(for: .seconds(1))
                        await send(.switchSucceeded(bestServerString))
                    } catch {
                        await send(.switchFailed(error.toZcashError()))
                    }
                }

            case .switchFailed(let error):
                state.isUpdatingServer = false
                state.alert = AlertState.endpoindSwitchFailed(error)
                return .none

            case .switchSucceeded(let bestServer):
                state.isUpdatingServer = false
                state.initialSelectedServers = state.selectedServers
                state.initialCustomServer = state.customServer
                state.activeSyncServer = bestServer
                return .none
            }
        }
    }
}

extension ServerSetup {
    func persistSelectedServers(state: State) throws {
        let configs = state.selectedServers.compactMap { serverString -> UserPreferencesStorage.ServerConfig? in
            let input = serverString == String(localizable: .serverSetupCustom) ? state.customServer : serverString
            return UserPreferencesStorage.ServerConfig.config(
                for: input,
                isCustom: serverString == String(localizable: .serverSetupCustom),
                streamingCallTimeoutInMillis: streamingCallTimeoutInMillis
            )
        }
        try userStoredPreferences.setSelectedServers(.init(servers: configs))
    }
}

// MARK: Alerts

extension AlertState where Action == ServerSetup.Action {
    public static func endpoindSwitchFailed(_ error: ZcashError) -> AlertState {
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
