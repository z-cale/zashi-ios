//
//  ZcashSDKEnvironmentLiveKey.swift
//  Zashi
//
//  Created by Lukáš Korba on 13.11.2022.
//

import ComposableArchitecture
import ZcashLightClientKit

import UserPreferencesStorage
import UserDefaults
import Utils

extension ZcashSDKEnvironment {
    public static func live(network: ZcashNetwork) -> Self {
        Self(
            latestCheckpoint: BlockHeight.ofLatestCheckpoint(network: network),
            endpoint: {
                ZcashSDKEnvironment.serverConfig(
                    for: network.networkType
                ).endpoint(streamingCallTimeoutInMillis: ZcashSDKConstants.streamingCallTimeoutInMillis)
            },
            exchangeRateIPRateLimit: 120,
            exchangeRateStaleLimit: 15 * 60,
            memoCharLimit: MemoBytes.capacity,
            mnemonicWordsMaxCount: ZcashSDKConstants.mnemonicWordsMaxCount,
            network: network,
            requiredTransactionConfirmations: ZcashSDKConstants.requiredTransactionConfirmations,
            sdkVersion: "0.18.1-beta",
            serverConfig: { ZcashSDKEnvironment.serverConfig(for: network.networkType) },
            servers: ZcashSDKEnvironment.servers(for: network.networkType),
            shieldingThreshold: Zatoshi(100_000),
            tokenName: network.networkType == .testnet ? "TAZ" : "ZEC"
        )
    }
}

extension ZcashSDKEnvironment {
    public static func serverConfig(for network: NetworkType) -> UserPreferencesStorage.ServerConfig {
        migrateVersion1IfNeeded()
        initializeSelectedServersIfNeeded(for: network)

        guard let serverConfig = storedServerConfig() else {
            // Fall back to first selected server (manual mode) or default endpoint (automatic mode)
            @Dependency(\.userStoredPreferences) var userStoredPreferences
            if let selected = userStoredPreferences.selectedServers() {
                if selected.mode == .manual, let first = selected.servers.first {
                    return first
                }
            }
            return defaultEndpoint(for: network).serverConfig()
        }
        
        // Migrate lwdX.zcash-infra.com servers to custom
        if serverConfig.host.hasSuffix(".zcash-infra.com") {
            return UserPreferencesStorage.ServerConfig(host: serverConfig.host, port: serverConfig.port, isCustom: true)
        }
        
        return serverConfig
    }
    
    static func migrateVersion1IfNeeded() {
        @Dependency(\.userStoredPreferences) var userStoredPreferences
        @Dependency(\.userDefaults) var userDefaults

        let streamingCallTimeoutInMillis = ZcashSDKConstants.streamingCallTimeoutInMillis
        let udServerKey = "zashi_udServerKey"
        let udCustomServerKey = "zashi_udCustomServerKey"

        // only if there's no ServerConfig stored
        guard userStoredPreferences.server() == nil else {
            userDefaults.remove(udServerKey)
            userDefaults.remove(udCustomServerKey)
            return
        }
        
        // get server key
        guard let storedKey = userDefaults.objectForKey(udServerKey) as? String else {
            userDefaults.remove(udServerKey)
            userDefaults.remove(udCustomServerKey)
            return
        }
        
        // ensure custom server is preserved
        if storedKey == "custom" {
            if let customValue = userDefaults.objectForKey(udCustomServerKey) as? String {
                if let serverConfig = UserPreferencesStorage.ServerConfig.endpoint(
                    for: customValue,
                    streamingCallTimeoutInMillis: streamingCallTimeoutInMillis)?.serverConfig(
                        isCustom: true
                    ) 
                {
                    try? userStoredPreferences.setServer(serverConfig)
                }
            }
        } else if storedKey == "mainnet" {
            let serverConfig = UserPreferencesStorage.ServerConfig(host: "mainnet.lightwalletd.com", port: 9067, isCustom: true)
            try? userStoredPreferences.setServer(serverConfig)
        } else {
            // some of the lwd servers
            let serverConfig = UserPreferencesStorage.ServerConfig(host: "\(storedKey.dropLast(2)).lightwalletd.com", port: 443, isCustom: true)
            try? userStoredPreferences.setServer(serverConfig)
        }
    }
    
    /// On first launch (no selected servers config), initialize based on existing server preference:
    /// - Custom server users: manual mode with their custom server (privacy)
    /// - Known server users / new users: automatic mode (sends to all servers)
    static func initializeSelectedServersIfNeeded(for network: NetworkType) {
        @Dependency(\.userStoredPreferences) var userStoredPreferences

        guard userStoredPreferences.selectedServers() == nil else { return }

        if let existing = userStoredPreferences.server(), existing.isCustom {
            do {
                try userStoredPreferences.setSelectedServers(.init(mode: .manual, servers: [existing]))
            } catch {
                LoggerProxy.error("[Migration] Failed to persist custom server selection: \(error)")
            }
            return
        }

        do {
            try userStoredPreferences.setSelectedServers(.init(mode: .automatic, servers: []))
        } catch {
            LoggerProxy.error("[Migration] Failed to persist default server selection: \(error)")
        }
    }

    static func storedServerConfig() -> UserPreferencesStorage.ServerConfig? {
        @Dependency(\.userStoredPreferences) var userStoredPreferences
        return userStoredPreferences.server()
    }
}
