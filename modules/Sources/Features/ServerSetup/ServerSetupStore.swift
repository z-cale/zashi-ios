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
        var connectionMode: UserPreferencesStorage.ConnectionMode
        var customServer: String
        var isEvaluatingServers = false
        var isUpdatingServer = false
        var activeSyncServer: String = ""
        var initialConnectionMode: UserPreferencesStorage.ConnectionMode
        var initialCustomServer: String = ""
        var initialSelectedServer: String?
        var network: NetworkType = .mainnet
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
            network: NetworkType = .mainnet,
            selectedServer: String? = nil,
            servers: [ZcashSDKEnvironment.Server] = [],
            topKServers: [ZcashSDKEnvironment.Server] = []
        ) {
            self.connectionMode = connectionMode
            self.customServer = customServer
            self.isEvaluatingServers = isEvaluatingServers
            self.isUpdatingServer = isUpdatingServer
            self.initialConnectionMode = connectionMode
            self.network = network
            self.selectedServer = selectedServer
            self.servers = servers
            self.topKServers = topKServers
        }
    }

    public enum Action: Equatable, BindableAction {
        case alert(PresentationAction<Action>)
        case binding(BindingAction<State>)
        case connectionModeChanged(UserPreferencesStorage.ConnectionMode)
        case evaluatedServers([LightWalletEndpoint])
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
                if mode == .manual && state.topKServers.isEmpty {
                    return .send(.evaluateServers)
                }
                return .none

            case .evaluateServers:
                state.isEvaluatingServers = true
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

                // In automatic mode, update the displayed active sync server to the best one
                if state.connectionMode == .automatic, let best = bestServers.first {
                    state.activeSyncServer = "\(best.host):\(best.port)"
                }

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

                // Persist connection mode and selected server
                do {
                    try self.persistSelection(state: state)
                } catch {
                    state.isUpdatingServer = false
                    return .send(.switchFailed(ZcashError.unknown(error)))
                }

                let network = state.network

                switch state.connectionMode {
                case .automatic:
                    // Evaluate to find best sync server, then switch
                    return .run { send in
                        do {
                            let bestServers = await sdkSynchronizer.evaluateBestOf(
                                ZcashSDKEnvironment.endpoints(for: network),
                                300.0, 60.0, 100, 1, network
                            )

                            let best = bestServers.first ?? ZcashSDKEnvironment.defaultEndpoint(for: network)

                            let currentEndpoint = zcashSDKEnvironment.endpoint()
                            if best.host != currentEndpoint.host || best.port != currentEndpoint.port {
                                try await sdkSynchronizer.switchToEndpoint(best)
                            }

                            let serverConfig = UserPreferencesStorage.ServerConfig(
                                host: best.host, port: best.port, isCustom: false
                            )
                            try? userStoredPreferences.setServer(serverConfig)

                            let bestServerString = "\(best.host):\(best.port)"
                            try await mainQueue.sleep(for: .seconds(1))
                            await send(.switchSucceeded(bestServerString))
                        } catch {
                            await send(.switchFailed(error.toZcashError()))
                        }
                    }

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

                    return .run { send in
                        do {
                            let currentEndpoint = zcashSDKEnvironment.endpoint()
                            if endpoint.host != currentEndpoint.host || endpoint.port != currentEndpoint.port {
                                try await sdkSynchronizer.switchToEndpoint(endpoint)
                            }

                            let isCustom = !ZcashSDKEnvironment.isKnownEndpoint(
                                host: endpoint.host, port: endpoint.port, network: network
                            )
                            let serverConfig = UserPreferencesStorage.ServerConfig(
                                host: endpoint.host, port: endpoint.port, isCustom: isCustom
                            )
                            try? userStoredPreferences.setServer(serverConfig)

                            let serverStr = "\(endpoint.host):\(endpoint.port)"
                            try await mainQueue.sleep(for: .seconds(1))
                            await send(.switchSucceeded(serverStr))
                        } catch {
                            await send(.switchFailed(error.toZcashError()))
                        }
                    }
                }

            case .switchFailed(let error):
                state.isUpdatingServer = false
                state.alert = AlertState.endpoindSwitchFailed(error)
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

extension ServerSetup {
    func persistSelection(state: State) throws {
        switch state.connectionMode {
        case .automatic:
            try userStoredPreferences.setSelectedServers(.init(mode: .automatic, servers: []))

        case .manual:
            let serverString = state.selectedServer == String(localizable: .serverSetupCustom)
                ? state.customServer
                : (state.selectedServer ?? "")
            let isCustom = state.selectedServer == String(localizable: .serverSetupCustom)
            guard let config = UserPreferencesStorage.ServerConfig.config(
                for: serverString,
                isCustom: isCustom,
                streamingCallTimeoutInMillis: streamingCallTimeoutInMillis
            ) else {
                throw ZcashError.synchronizerServerSwitch
            }
            try userStoredPreferences.setSelectedServers(.init(mode: .manual, servers: [config]))
        }
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
