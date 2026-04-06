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

    // MARK: - Custom server user must NOT be auto-upgraded to multi-server

    /// A user who previously selected a custom server should only have that single
    /// custom server in their selectedServers config after migration — NOT all
    /// hardcoded servers.
    func testCustomServerUser_migratesOnlyCustomServer() throws {
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

        XCTAssertEqual(result.servers.count, 1, "Custom server user should have exactly 1 selected server")
        XCTAssertEqual(result.servers.first?.host, customServer.host)
        XCTAssertEqual(result.servers.first?.port, customServer.port)
        XCTAssertTrue(result.servers.first?.isCustom == true, "The server should be marked as custom")
    }

    // MARK: - Known server user should get all hardcoded servers

    /// A user who previously selected a known (non-custom) server should be
    /// upgraded to all hardcoded servers.
    func testKnownServerUser_migratesAllHardcodedServers() throws {
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

        let allEndpoints = ZcashSDKEnvironment.endpoints(for: .mainnet)
        XCTAssertEqual(result.servers.count, allEndpoints.count, "Known server user should have all hardcoded servers selected")
        XCTAssertTrue(result.servers.allSatisfy { !$0.isCustom }, "All servers should be non-custom")
    }

    // MARK: - New user (no server preference) should get all hardcoded servers

    func testNewUser_defaultsToAllHardcodedServers() throws {
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

        let allEndpoints = ZcashSDKEnvironment.endpoints(for: .mainnet)
        XCTAssertEqual(result.servers.count, allEndpoints.count, "New user should have all hardcoded servers selected")
    }

    // MARK: - Testnet users should only get testnet endpoints

    func testTestnetKnownServerUser_migratesOnlyTestnetEndpoint() throws {
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
        let testnetEndpoints = ZcashSDKEnvironment.endpoints(for: .testnet)

        XCTAssertEqual(result.servers.count, testnetEndpoints.count, "Testnet known server user should only have testnet servers selected")
        XCTAssertEqual(result.servers.first?.host, testnetEndpoints.first?.host)
        XCTAssertEqual(result.servers.first?.port, testnetEndpoints.first?.port)
    }

    func testTestnetNewUser_defaultsToOnlyTestnetEndpoints() throws {
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
        let testnetEndpoints = ZcashSDKEnvironment.endpoints(for: .testnet)

        XCTAssertEqual(result.servers.count, testnetEndpoints.count, "Testnet new user should only have testnet servers selected")
        XCTAssertEqual(result.servers.first?.host, testnetEndpoints.first?.host)
        XCTAssertEqual(result.servers.first?.port, testnetEndpoints.first?.port)
    }

    // MARK: - Already migrated user is not re-migrated

    func testAlreadyMigratedUser_noOp() {
        let existingConfig = UserPreferencesStorage.SelectedServersConfig(servers: [
            .init(host: "zec.rocks", port: 443, isCustom: false)
        ])

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
            initialState: ServerSetup.State(topKServers: [.default])
        ) {
            ServerSetup()
        }

        store.dependencies.zcashSDKEnvironment = .testValue
        store.dependencies.userStoredPreferences.selectedServers = {
            .init(servers: [customServer])
        }

        let customLabel = String(localizable: .serverSetupCustom)
        let originalValue = customServer.serverString()
        let updatedValue = "new-custom.example.com:9067"

        await store.send(.onAppear) { state in
            state.network = .testnet
            state.activeSyncServer = ZcashSDKEnvironment.defaultEndpoint(for: .testnet).server()
            state.customServer = originalValue
            state.initialCustomServer = originalValue
            state.selectedServers = [customLabel]
            state.initialSelectedServers = [customLabel]
            state.servers = [.custom]
        }

        XCTAssertFalse(store.state.hasChanges)

        await store.send(.binding(.set(\.customServer, updatedValue))) { state in
            state.customServer = updatedValue
        }

        XCTAssertTrue(store.state.hasChanges)
    }

    func testSwitchSucceededResetsChangeTrackingAfterCustomServerEdit() async {
        let customServer = UserPreferencesStorage.ServerConfig(
            host: "old-custom.example.com",
            port: 9067,
            isCustom: true
        )

        let store = TestStore(
            initialState: ServerSetup.State(topKServers: [.default])
        ) {
            ServerSetup()
        }

        store.dependencies.zcashSDKEnvironment = .testValue
        store.dependencies.userStoredPreferences.selectedServers = {
            .init(servers: [customServer])
        }

        let customLabel = String(localizable: .serverSetupCustom)
        let originalValue = customServer.serverString()
        let updatedValue = "new-custom.example.com:9067"

        await store.send(.onAppear) { state in
            state.network = .testnet
            state.activeSyncServer = ZcashSDKEnvironment.defaultEndpoint(for: .testnet).server()
            state.customServer = originalValue
            state.initialCustomServer = originalValue
            state.selectedServers = [customLabel]
            state.initialSelectedServers = [customLabel]
            state.servers = [.custom]
        }

        await store.send(.binding(.set(\.customServer, updatedValue))) { state in
            state.customServer = updatedValue
        }

        XCTAssertTrue(store.state.hasChanges)

        await store.send(.switchSucceeded(updatedValue)) { state in
            state.isUpdatingServer = false
            state.initialSelectedServers = state.selectedServers
            state.initialCustomServer = updatedValue
            state.activeSyncServer = updatedValue
        }

        XCTAssertFalse(store.state.hasChanges)
    }

    func testEditingCustomServerWhileCustomIsNotSelectedDoesNotMarkStateChanged() async {
        let defaultServer = ZcashSDKEnvironment.defaultEndpoint(for: .testnet).serverConfig()

        let store = TestStore(
            initialState: ServerSetup.State(topKServers: [.custom])
        ) {
            ServerSetup()
        }

        store.dependencies.zcashSDKEnvironment = .testValue
        store.dependencies.userStoredPreferences.selectedServers = {
            .init(servers: [defaultServer])
        }

        let updatedValue = "new-custom.example.com:9067"

        await store.send(.onAppear) { state in
            state.network = .testnet
            state.activeSyncServer = defaultServer.serverString()
            state.customServer = ""
            state.initialCustomServer = ""
            state.selectedServers = [defaultServer.serverString()]
            state.initialSelectedServers = [defaultServer.serverString()]
            state.servers = [.default]
        }

        XCTAssertFalse(store.state.hasChanges)

        await store.send(.binding(.set(\.customServer, updatedValue))) { state in
            state.customServer = updatedValue
        }

        XCTAssertFalse(store.state.hasChanges)
    }
}
