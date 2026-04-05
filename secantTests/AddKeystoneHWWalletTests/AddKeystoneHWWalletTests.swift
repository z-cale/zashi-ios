//
//  AddKeystoneHWWalletTests.swift
//  secantTests
//
//  Created by Adam Tucker on 2026-04-04.
//

import XCTest
import ComposableArchitecture
import KeystoneSDK
import ZcashLightClientKit
import AddKeystoneHWWallet
import CoordFlows
import WalletBirthday
@testable import secant_testnet

@MainActor
final class AddKeystoneHWWalletTests: XCTestCase {

    private func makeZcashAccounts() throws -> ZcashAccounts {
        let json = """
        {
            "seedFingerprint": "aabb",
            "accounts": [{"ufvk": "utest1fakefvk", "index": 0, "name": "Test"}]
        }
        """
        return try JSONDecoder().decode(ZcashAccounts.self, from: Data(json.utf8))
    }

    // Verifies that .unlockTapped produces no state changes or effects in the reducer.
    // The coordinator intercepts this action to navigate to the birthday picker instead.
    func testUnlockTapped_isNoOp() async throws {
        let store = TestStore(
            initialState: .initial
        ) {
            AddKeystoneHWWallet()
        }

        store.dependencies.keystoneHandler = .noOp

        await store.send(.unlockTapped)

        await store.finish()
    }

    // Verifies that when .importAccount is called with a specific birthday height,
    // that exact value is forwarded to sdkSynchronizer.importAccount as the walletBirthday parameter.
    func testImportAccount_withBirthday_forwardsBirthdayToSDK() async throws {
        let expectedBirthday = BlockHeight(1_700_000)
        let capturedBirthday = ActorIsolated<BlockHeight?>(nil)

        var state = AddKeystoneHWWallet.State.initial
        state.zcashAccounts = try makeZcashAccounts()

        let store = TestStore(
            initialState: state
        ) {
            AddKeystoneHWWallet()
        }

        store.dependencies.keystoneHandler = .noOp
        store.dependencies.sdkSynchronizer = .mocked(
            importAccount: { _, _, _, _, _, _, birthday in
                await capturedBirthday.setValue(birthday)
                return nil
            }
        )

        await store.send(.importAccount(expectedBirthday))

        await store.finish()

        let captured = await capturedBirthday.value
        XCTAssertEqual(captured, expectedBirthday, "Birthday should be forwarded to sdkSynchronizer.importAccount")
    }

    // Verifies that when .importAccount is called with a nil birthday,
    // nil is forwarded to sdkSynchronizer.importAccount (letting the SDK use its default).
    func testImportAccount_withNilBirthday_forwardsNilToSDK() async throws {
        let capturedBirthday = ActorIsolated<BlockHeight?>(BlockHeight(999))

        var state = AddKeystoneHWWallet.State.initial
        state.zcashAccounts = try makeZcashAccounts()

        let store = TestStore(
            initialState: state
        ) {
            AddKeystoneHWWallet()
        }

        store.dependencies.keystoneHandler = .noOp
        store.dependencies.sdkSynchronizer = .mocked(
            importAccount: { _, _, _, _, _, _, birthday in
                await capturedBirthday.setValue(birthday)
                return nil
            }
        )

        await store.send(.importAccount(nil))

        await store.finish()

        let captured = await capturedBirthday.value
        XCTAssertNil(captured, "Nil birthday should be forwarded as nil to sdkSynchronizer.importAccount")
    }

    // Verifies the guard clause: when no zcashAccounts are set on state,
    // .importAccount produces no effects and does not call the SDK.
    func testImportAccount_withNoAccounts_isNoOp() async throws {
        let store = TestStore(
            initialState: .initial
        ) {
            AddKeystoneHWWallet()
        }

        store.dependencies.keystoneHandler = .noOp

        await store.send(.importAccount(BlockHeight(1_700_000)))

        await store.finish()
    }

    // End-to-end coordinator test: simulates the full birthday picker flow.
    // Sets up the navigation path with an account selection and a wallet birthday (estimatedHeight = 1_700_000),
    // then sends .restoreTapped. Verifies the coordinator reads the birthday from the path,
    // calls performKeystoneImport, and the birthday value reaches sdkSynchronizer.importAccount.
    func testCoordinator_restoreTapped_forwardsBirthdayToImportAccount() async throws {
        let expectedBirthday = BlockHeight(1_700_000)
        let capturedBirthday = ActorIsolated<BlockHeight?>(nil)

        var accountSelectionState = AddKeystoneHWWallet.State.initial
        accountSelectionState.zcashAccounts = try makeZcashAccounts()

        var walletBirthdayState = WalletBirthday.State.initial
        walletBirthdayState.estimatedHeight = expectedBirthday

        var state = AddKeystoneHWWalletCoordFlow.State()
        state.path.append(.accountHWWalletSelection(accountSelectionState))
        state.path.append(.walletBirthday(walletBirthdayState))

        let walletBirthdayID = state.path.ids.last!

        let store = Store(
            initialState: state
        ) {
            AddKeystoneHWWalletCoordFlow()
        } withDependencies: {
            $0.keystoneHandler = .noOp
            $0.sdkSynchronizer = .mocked(
                importAccount: { _, _, _, _, _, _, birthday in
                    await capturedBirthday.setValue(birthday)
                    return nil
                }
            )
        }

        await store.send(.path(.element(id: walletBirthdayID, action: .walletBirthday(.restoreTapped))))

        // Give the effect time to run
        try await Task.sleep(nanoseconds: 200_000_000)

        let captured = await capturedBirthday.value
        XCTAssertEqual(captured, expectedBirthday, "Coordinator should forward birthday into account import")
    }
}
