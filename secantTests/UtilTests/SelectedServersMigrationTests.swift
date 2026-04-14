//
//  SelectedServersMigrationTests.swift
//  secantTests
//
//  Created by Adam Tucker on 2026-04-05.
//

import XCTest
import ComposableArchitecture
import ZcashLightClientKit
import UserPreferencesStorage
import Generated
@testable import ServerSetup
@testable import ZcashSDKEnvironment
@testable import secant_testnet

class SelectedServersMigrationTests: XCTestCase {

    // MARK: - Custom server user → manual mode

    func testCustomServerUser_migratesToManualMode() throws {
        let customServer = UserPreferencesStorage.ServerConfig(
            host: "my-custom-node.example.com",
            port: 9067,
            isCustom: true
        )

        var capturedSelectedServers: UserPreferencesStorage.SelectedServersConfig?

        withDependencies {
            $0.userStoredPreferences.server = { customServer }
            $0.userStoredPreferences.selectedServers = { nil }
            $0.userStoredPreferences.setSelectedServers = { config in
                capturedSelectedServers = config
            }
        } operation: {
            ZcashSDKEnvironment.initializeSelectedServersIfNeeded(for: .mainnet)
        }

        let result = try XCTUnwrap(capturedSelectedServers, "Migration should have persisted a selectedServers config")

        XCTAssertEqual(result.mode, .manual, "Custom server user should be set to manual mode")
        XCTAssertEqual(result.servers.count, 1, "Custom server user should have exactly 1 selected server")
        XCTAssertEqual(result.servers.first?.host, customServer.host)
        XCTAssertEqual(result.servers.first?.port, customServer.port)
        XCTAssertTrue(result.servers.first?.isCustom == true, "The server should be marked as custom")
    }

    func testLegacyInfraServerUser_migratesToManualMode() throws {
        let infraServer = UserPreferencesStorage.ServerConfig(
            host: "lwd1.zcash-infra.com",
            port: 443,
            isCustom: false
        )

        var capturedSelectedServers: UserPreferencesStorage.SelectedServersConfig?

        withDependencies {
            $0.userStoredPreferences.server = { infraServer }
            $0.userStoredPreferences.selectedServers = { nil }
            $0.userStoredPreferences.setSelectedServers = { config in
                capturedSelectedServers = config
            }
        } operation: {
            ZcashSDKEnvironment.initializeSelectedServersIfNeeded(for: .mainnet)
        }

        let result = try XCTUnwrap(capturedSelectedServers, "Migration should have persisted a selectedServers config")

        XCTAssertEqual(result.mode, .manual, "Legacy zcash-infra.com server should preserve manual mode")
        XCTAssertEqual(result.servers.count, 1, "Manual mode should preserve the legacy server")
        XCTAssertEqual(result.servers.first?.host, infraServer.host)
        XCTAssertEqual(result.servers.first?.port, infraServer.port)
        XCTAssertTrue(result.servers.first?.isCustom == true, "Legacy infra server should normalize to custom")
    }

    // MARK: - Known server user → automatic mode

    func testKnownServerUser_migratesToAutomaticMode() throws {
        let knownServer = UserPreferencesStorage.ServerConfig(
            host: "zec.rocks",
            port: 443,
            isCustom: false
        )

        var capturedSelectedServers: UserPreferencesStorage.SelectedServersConfig?

        withDependencies {
            $0.userStoredPreferences.server = { knownServer }
            $0.userStoredPreferences.selectedServers = { nil }
            $0.userStoredPreferences.setSelectedServers = { config in
                capturedSelectedServers = config
            }
        } operation: {
            ZcashSDKEnvironment.initializeSelectedServersIfNeeded(for: .mainnet)
        }

        let result = try XCTUnwrap(capturedSelectedServers, "Migration should have persisted a selectedServers config")

        XCTAssertEqual(result.mode, .automatic, "Known server user should be set to automatic mode")
        XCTAssertTrue(result.servers.isEmpty, "Automatic mode should have empty servers array")
    }

    // MARK: - New user → automatic mode

    func testNewUser_defaultsToAutomaticMode() throws {
        var capturedSelectedServers: UserPreferencesStorage.SelectedServersConfig?

        withDependencies {
            $0.userStoredPreferences.server = { nil }
            $0.userStoredPreferences.selectedServers = { nil }
            $0.userStoredPreferences.setSelectedServers = { config in
                capturedSelectedServers = config
            }
        } operation: {
            ZcashSDKEnvironment.initializeSelectedServersIfNeeded(for: .mainnet)
        }

        let result = try XCTUnwrap(capturedSelectedServers, "Migration should have persisted a selectedServers config")

        XCTAssertEqual(result.mode, .automatic, "New user should default to automatic mode")
        XCTAssertTrue(result.servers.isEmpty, "Automatic mode should have empty servers array")
    }

    // MARK: - Testnet

    func testTestnetKnownServerUser_migratesToAutomaticMode() throws {
        let knownServer = ZcashSDKEnvironment.defaultEndpoint(for: .testnet).serverConfig()

        var capturedSelectedServers: UserPreferencesStorage.SelectedServersConfig?

        withDependencies {
            $0.userStoredPreferences.server = { knownServer }
            $0.userStoredPreferences.selectedServers = { nil }
            $0.userStoredPreferences.setSelectedServers = { config in
                capturedSelectedServers = config
            }
        } operation: {
            ZcashSDKEnvironment.initializeSelectedServersIfNeeded(for: .testnet)
        }

        let result = try XCTUnwrap(capturedSelectedServers, "Migration should have persisted a selectedServers config")

        XCTAssertEqual(result.mode, .automatic)
        XCTAssertTrue(result.servers.isEmpty)
    }

    func testTestnetNewUser_defaultsToAutomaticMode() throws {
        var capturedSelectedServers: UserPreferencesStorage.SelectedServersConfig?

        withDependencies {
            $0.userStoredPreferences.server = { nil }
            $0.userStoredPreferences.selectedServers = { nil }
            $0.userStoredPreferences.setSelectedServers = { config in
                capturedSelectedServers = config
            }
        } operation: {
            ZcashSDKEnvironment.initializeSelectedServersIfNeeded(for: .testnet)
        }

        let result = try XCTUnwrap(capturedSelectedServers, "Migration should have persisted a selectedServers config")

        XCTAssertEqual(result.mode, .automatic)
        XCTAssertTrue(result.servers.isEmpty)
    }

    // MARK: - Already migrated user is not re-migrated

    func testAlreadyMigratedUser_noOp() {
        let existingConfig = UserPreferencesStorage.SelectedServersConfig(
            mode: .manual,
            servers: [.init(host: "zec.rocks", port: 443, isCustom: false)]
        )

        var setSelectedServersCalled = false

        withDependencies {
            $0.userStoredPreferences.selectedServers = { existingConfig }
            $0.userStoredPreferences.setSelectedServers = { _ in
                setSelectedServersCalled = true
            }
        } operation: {
            ZcashSDKEnvironment.initializeSelectedServersIfNeeded(for: .mainnet)
        }

        XCTAssertFalse(setSelectedServersCalled, "Should not overwrite existing selectedServers config")
    }

    // MARK: - Backward compat decoding

    func testBackwardCompat_oldFormatWithCustomServer_decodesToManual() throws {
        // Simulate old JSON without "mode" field, single custom server
        let json = """
        {"servers":[{"host":"my-node.example.com","port":9067,"isCustom":true}]}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(UserPreferencesStorage.SelectedServersConfig.self, from: json)
        XCTAssertEqual(config.mode, .manual, "Single custom server should decode as manual")
        XCTAssertEqual(config.servers.count, 1)
    }

    func testBackwardCompat_oldFormatWithMultipleServers_decodesToAutomatic() throws {
        let json = """
        {"servers":[{"host":"zec.rocks","port":443,"isCustom":false},{"host":"eu.zec.rocks","port":443,"isCustom":false}]}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(UserPreferencesStorage.SelectedServersConfig.self, from: json)
        XCTAssertEqual(config.mode, .automatic, "Multiple non-custom servers should decode as automatic")
        XCTAssertEqual(config.servers.count, 2, "Both servers should be preserved in decoded config")
    }

    func testBackwardCompat_oldFormatWithSingleNonCustomServer_decodesToAutomatic() throws {
        let json = """
        {"servers":[{"host":"zec.rocks","port":443,"isCustom":false}]}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(UserPreferencesStorage.SelectedServersConfig.self, from: json)
        XCTAssertEqual(config.mode, .automatic, "Single non-custom server should decode as automatic")
        XCTAssertEqual(config.servers.count, 1)
    }

    func testBackwardCompat_newFormatWithMode_decodesCorrectly() throws {
        let json = """
        {"mode":"manual","servers":[{"host":"zec.rocks","port":443,"isCustom":false}]}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(UserPreferencesStorage.SelectedServersConfig.self, from: json)
        XCTAssertEqual(config.mode, .manual)
        XCTAssertEqual(config.servers.count, 1)
    }

    func testIsKnownEndpoint_isNetworkAware() {
        let testnetEndpoint = ZcashSDKEnvironment.defaultEndpoint(for: .testnet)

        XCTAssertTrue(ZcashSDKEnvironment.isKnownEndpoint(host: "zec.rocks", port: 443, network: .mainnet))
        XCTAssertFalse(ZcashSDKEnvironment.isKnownEndpoint(host: "zec.rocks", port: 443, network: .testnet))
        XCTAssertTrue(
            ZcashSDKEnvironment.isKnownEndpoint(
                host: testnetEndpoint.host,
                port: testnetEndpoint.port,
                network: .testnet
            )
        )
    }
}

@MainActor
class ServerSetupChangeDetectionTests: XCTestCase {
    func testCustomServerEditMarksStateChangedWhenCustomIsSelected() async {
        let customServer = UserPreferencesStorage.ServerConfig(
            host: "old-custom.example.com",
            port: 9067,
            isCustom: true
        )

        let store = TestStore(
            initialState: ServerSetup.State(
                connectionMode: .manual,
                topKServers: [.default]
            )
        ) {
            ServerSetup()
        }

        store.dependencies.zcashSDKEnvironment = .testValue
        store.dependencies.userStoredPreferences.selectedServers = {
            .init(mode: .manual, servers: [customServer])
        }

        let customLabel = String(localizable: .serverSetupCustom)
        let originalValue = customServer.serverString()
        let updatedValue = "new-custom.example.com:9067"

        await store.send(.onAppear) { state in
            state.network = .testnet
            state.activeSyncServer = ZcashSDKEnvironment.defaultEndpoint(for: .testnet).server()
            state.customServer = originalValue
            state.initialCustomServer = originalValue
            state.connectionMode = .manual
            state.initialConnectionMode = .manual
            state.selectedServer = customLabel
            state.initialSelectedServer = customLabel
            state.servers = [.custom]
        }

        XCTAssertFalse(store.state.hasChanges)

        await store.send(.binding(.set(\.customServer, updatedValue))) { state in
            state.customServer = updatedValue
        }

        XCTAssertTrue(store.state.hasChanges)
    }

    func testSwitchSucceededResetsChangeTracking() async {
        let customServer = UserPreferencesStorage.ServerConfig(
            host: "old-custom.example.com",
            port: 9067,
            isCustom: true
        )

        let store = TestStore(
            initialState: ServerSetup.State(
                connectionMode: .manual,
                topKServers: [.default]
            )
        ) {
            ServerSetup()
        }

        store.dependencies.zcashSDKEnvironment = .testValue
        store.dependencies.userStoredPreferences.selectedServers = {
            .init(mode: .manual, servers: [customServer])
        }

        let customLabel = String(localizable: .serverSetupCustom)
        let originalValue = customServer.serverString()
        let updatedValue = "new-custom.example.com:9067"

        await store.send(.onAppear) { state in
            state.network = .testnet
            state.activeSyncServer = ZcashSDKEnvironment.defaultEndpoint(for: .testnet).server()
            state.customServer = originalValue
            state.initialCustomServer = originalValue
            state.connectionMode = .manual
            state.initialConnectionMode = .manual
            state.selectedServer = customLabel
            state.initialSelectedServer = customLabel
            state.servers = [.custom]
        }

        await store.send(.binding(.set(\.customServer, updatedValue))) { state in
            state.customServer = updatedValue
        }

        XCTAssertTrue(store.state.hasChanges)

        await store.send(.switchSucceeded(updatedValue)) { state in
            state.isUpdatingServer = false
            state.initialConnectionMode = .manual
            state.initialSelectedServer = customLabel
            state.initialCustomServer = updatedValue
            state.activeSyncServer = updatedValue
        }

        XCTAssertFalse(store.state.hasChanges)
    }

    func testConnectionModeChangeMarksStateChanged() async {
        let store = TestStore(
            initialState: ServerSetup.State(
                connectionMode: .automatic,
                topKServers: [.default]
            )
        ) {
            ServerSetup()
        }

        store.dependencies.zcashSDKEnvironment = .testValue
        store.dependencies.userStoredPreferences.selectedServers = {
            .init(mode: .automatic, servers: [])
        }

        await store.send(.onAppear) { state in
            state.network = .testnet
            state.activeSyncServer = ZcashSDKEnvironment.defaultEndpoint(for: .testnet).server()
            state.connectionMode = .automatic
            state.initialConnectionMode = .automatic
            state.servers = [.custom]
        }

        XCTAssertFalse(store.state.hasChanges)

        await store.send(.connectionModeChanged(.manual)) { state in
            state.connectionMode = .manual
        }

        XCTAssertTrue(store.state.hasChanges)
    }

    func testAutomaticEvaluationKeepsActiveSyncServerTruthful() async {
        let store = TestStore(
            initialState: ServerSetup.State(
                connectionMode: .automatic,
                topKServers: [.default]
            )
        ) {
            ServerSetup()
        }

        store.dependencies.zcashSDKEnvironment = .testValue

        await store.send(.onAppear) { state in
            state.network = .testnet
            state.activeSyncServer = ZcashSDKEnvironment.defaultEndpoint(for: .testnet).server()
            state.connectionMode = .automatic
            state.initialConnectionMode = .automatic
            state.servers = [.custom]
        }

        let evaluatedEndpoint = LightWalletEndpoint(
            address: "faster.example.com",
            port: 443,
            secure: true,
            streamingCallTimeoutInMillis: ZcashSDKEnvironment.ZcashSDKConstants.streamingCallTimeoutInMillis
        )

        await store.send(.evaluatedServers(0, [evaluatedEndpoint])) { state in
            state.isEvaluatingServers = false
            state.topKServers = [.hardcoded("faster.example.com:443")]
            state.servers = [.default, .custom]
            state.recommendedSyncServer = "faster.example.com:443"
        }

        XCTAssertEqual(
            store.state.activeSyncServer,
            ZcashSDKEnvironment.defaultEndpoint(for: .testnet).server(),
            "Benchmarking should not relabel the active sync endpoint before an actual switch"
        )
        XCTAssertEqual(store.state.recommendedSyncServer, "faster.example.com:443")
    }

    func testStaleEvaluatedServersResultIsIgnored() async {
        let store = TestStore(
            initialState: ServerSetup.State(
                connectionMode: .automatic,
                isEvaluatingServers: true,
                serverEvaluationRequestID: 2
            )
        ) {
            ServerSetup()
        }

        store.dependencies.zcashSDKEnvironment = .testValue

        let staleEndpoint = LightWalletEndpoint(
            address: "stale.example.com",
            port: 443,
            secure: true,
            streamingCallTimeoutInMillis: ZcashSDKEnvironment.ZcashSDKConstants.streamingCallTimeoutInMillis
        )

        await store.send(.evaluatedServers(1, [staleEndpoint]))

        XCTAssertTrue(store.state.isEvaluatingServers, "Older evaluation should not finish the latest request")
        XCTAssertTrue(store.state.topKServers.isEmpty, "Stale evaluation results should be ignored")
        XCTAssertNil(store.state.recommendedSyncServer, "Ignored stale results should not update recommendations")
    }
}
