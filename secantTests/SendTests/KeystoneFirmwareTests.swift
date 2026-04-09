//
//  KeystoneFirmwareTests.swift
//  secantTests
//
//  Covers the Keystone firmware version stamp reader, the update-required
//  policy, and the SendConfirmation reducer branching on `.foundPCZT`.
//

import XCTest
import ComposableArchitecture
import SendConfirmation
@testable import secant_testnet

final class KeystoneFirmwareTests: XCTestCase {
    // MARK: - Helpers

    /// Builds a synthetic PCZT-shaped byte blob that mimics the relevant
    /// portion of `global.proprietary` as serialized by `postcard`. The
    /// scanner only cares about the literal key bytes followed by a `0x03`
    /// length byte and the 3 version bytes, so we don't need a real PCZT.
    private func stampedBlob(major: UInt8, minor: UInt8, build: UInt8) -> Data {
        var bytes = Data()
        // Magic-ish prefix + padding so the match isn't at the very start.
        bytes.append(contentsOf: [0x50, 0x43, 0x5A, 0x54, 0x01, 0x00, 0x00, 0x00])
        bytes.append(contentsOf: Array(repeating: UInt8(0xAA), count: 16))
        // "keystone:fw_version" (19 ASCII bytes) — postcard writes a varint
        // length before the string, but our scanner only matches the key
        // literal, so the preceding length byte is irrelevant. We include a
        // plausible 0x13 (19) before it to match real postcard layout.
        bytes.append(0x13)
        bytes.append(contentsOf: Data("keystone:fw_version".utf8))
        // Vec<u8> length + 3 value bytes.
        bytes.append(0x03)
        bytes.append(major)
        bytes.append(minor)
        bytes.append(build)
        // Trailing garbage to make sure the scanner doesn't over-read.
        bytes.append(contentsOf: Array(repeating: UInt8(0xCC), count: 32))
        return bytes
    }

    private func unstampedBlob() -> Data {
        // Arbitrary bytes that do not contain the key literal anywhere.
        Data(repeating: 0x55, count: 256)
    }

    // MARK: - Scanner

    func test_readKeystoneFwVersion_onStampedBlob_returnsVersion() {
        let blob = stampedBlob(major: 12, minor: 4, build: 0)
        let version = blob.readKeystoneFwVersion()
        XCTAssertEqual(version, KeystoneFirmwareVersion(major: 12, minor: 4, build: 0))
    }

    func test_readKeystoneFwVersion_onUnstampedBlob_returnsNil() {
        XCTAssertNil(unstampedBlob().readKeystoneFwVersion())
    }

    func test_readKeystoneFwVersion_onStampedBlobWithUnusualVersion_returnsVersion() {
        let blob = stampedBlob(major: 99, minor: 255, build: 1)
        XCTAssertEqual(
            blob.readKeystoneFwVersion(),
            KeystoneFirmwareVersion(major: 99, minor: 255, build: 1)
        )
    }

    func test_readKeystoneFwVersion_onTruncatedBlob_returnsNil() {
        // Key present but fewer than 3 value bytes follow the 0x03 length.
        var bytes = Data([0x13])
        bytes.append(contentsOf: Data("keystone:fw_version".utf8))
        bytes.append(contentsOf: [0x03, 0x0c, 0x04]) // only 2 of 3 bytes
        XCTAssertNil(bytes.readKeystoneFwVersion())
    }

    func test_readKeystoneFwVersion_onWrongLengthByte_returnsNil() {
        // Key present but length byte says 4, not 3.
        var bytes = Data([0x13])
        bytes.append(contentsOf: Data("keystone:fw_version".utf8))
        bytes.append(contentsOf: [0x04, 0x0c, 0x04, 0x00, 0xff])
        XCTAssertNil(bytes.readKeystoneFwVersion())
    }

    // MARK: - Version ordering

    func test_version_ordering_isLexicographic() {
        XCTAssertLessThan(
            KeystoneFirmwareVersion(major: 12, minor: 4, build: 0),
            KeystoneFirmwareVersion(major: 12, minor: 4, build: 1)
        )
        XCTAssertLessThan(
            KeystoneFirmwareVersion(major: 12, minor: 4, build: 0),
            KeystoneFirmwareVersion(major: 12, minor: 5, build: 0)
        )
        XCTAssertLessThan(
            KeystoneFirmwareVersion(major: 12, minor: 4, build: 0),
            KeystoneFirmwareVersion(major: 13, minor: 0, build: 0)
        )
        XCTAssertEqual(
            KeystoneFirmwareVersion(major: 12, minor: 4, build: 0),
            KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)
        )
    }

    func test_version_displayString_formatsCorrectly() {
        XCTAssertEqual(
            KeystoneFirmwareVersion(major: 12, minor: 4, build: 0).displayString,
            "12.4.0"
        )
    }

    // MARK: - Policy

    func test_policy_detectedAboveRequired_returnsOk() {
        XCTAssertEqual(
            KeystoneFirmwarePolicy.evaluate(
                detected: KeystoneFirmwareVersion(major: 12, minor: 5, build: 0),
                required: KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)
            ),
            .ok
        )
    }

    func test_policy_detectedEqualToRequired_returnsOk() {
        XCTAssertEqual(
            KeystoneFirmwarePolicy.evaluate(
                detected: KeystoneFirmwareVersion(major: 12, minor: 4, build: 0),
                required: KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)
            ),
            .ok
        )
    }

    func test_policy_detectedBelowRequired_returnsUpdateRequired() {
        XCTAssertEqual(
            KeystoneFirmwarePolicy.evaluate(
                detected: KeystoneFirmwareVersion(major: 12, minor: 4, build: 0),
                required: KeystoneFirmwareVersion(major: 13, minor: 0, build: 0)
            ),
            .updateRequired
        )
    }

    func test_policy_noDetectedVersion_returnsLegacy() {
        XCTAssertEqual(
            KeystoneFirmwarePolicy.evaluate(
                detected: nil,
                required: KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)
            ),
            .legacy
        )
    }

    // MARK: - TCA reducer: `.foundPCZT` branching

    /// A PCZT whose firmware stamp meets the wallet's requirement must
    /// proceed straight into `createTransactionFromPCZT` as before.
    @MainActor
    func test_reducer_foundPCZT_okFirmware_schedulesCreateTransaction() async {
        var initialState = SendConfirmation.State.initial
        initialState.requiredKeystoneFirmware = KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)

        let store = TestStore(initialState: initialState) {
            SendConfirmation()
        }
        store.dependencies.mainQueue = .immediate

        let pczt = stampedBlob(major: 12, minor: 4, build: 0)
        await store.send(.foundPCZT(pczt)) { state in
            state.isKeystoneCodeFound = true
            state.pcztWithSigs = pczt
            state.detectedKeystoneFirmware = KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)
        }
        await store.receive(.createTransactionFromPCZT)
        // Downstream effects from createTransactionFromPCZT are outside the
        // scope of this test; cancel the store to prevent dangling work.
        await store.finish(timeout: .seconds(1))
    }

    /// A PCZT whose firmware stamp is *below* the requirement must emit
    /// `.keystoneFirmwareUpdateRequired(detected:)` and NOT proceed to
    /// broadcast.
    @MainActor
    func test_reducer_foundPCZT_tooOldFirmware_emitsUpdateRequired() async {
        var initialState = SendConfirmation.State.initial
        initialState.requiredKeystoneFirmware = KeystoneFirmwareVersion(major: 13, minor: 0, build: 0)

        let store = TestStore(initialState: initialState) {
            SendConfirmation()
        }
        store.dependencies.mainQueue = .immediate

        let pczt = stampedBlob(major: 12, minor: 4, build: 0)
        await store.send(.foundPCZT(pczt)) { state in
            state.isKeystoneCodeFound = true
            state.pcztWithSigs = pczt
            state.detectedKeystoneFirmware = KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)
        }
        await store.receive(.keystoneFirmwareUpdateRequired(
            detected: KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)
        ))
    }

    /// When minimumKeystoneFirmware is (0, 0, 0), the version check is
    /// skipped entirely — legacy and stamped firmware both proceed.
    @MainActor
    func test_reducer_foundPCZT_zeroMinVersion_skipsCheck() async {
        var initialState = SendConfirmation.State.initial
        initialState.requiredKeystoneFirmware = KeystoneFirmwareVersion(major: 0, minor: 0, build: 0)

        let store = TestStore(initialState: initialState) {
            SendConfirmation()
        }
        store.dependencies.mainQueue = .immediate

        let pczt = unstampedBlob()
        await store.send(.foundPCZT(pczt)) { state in
            state.isKeystoneCodeFound = true
            state.pcztWithSigs = pczt
        }
        await store.receive(.createTransactionFromPCZT)
        await store.finish(timeout: .seconds(1))
    }

    /// When minimumKeystoneFirmware is set to a real version, a PCZT
    /// with no firmware stamp (legacy device) emits
    /// `.keystoneFirmwareUpdateRequired`.
    @MainActor
    func test_reducer_foundPCZT_legacyFirmware_emitsUpdateRequired() async {
        var initialState = SendConfirmation.State.initial
        initialState.requiredKeystoneFirmware = KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)

        let store = TestStore(initialState: initialState) {
            SendConfirmation()
        }
        store.dependencies.mainQueue = .immediate

        let pczt = unstampedBlob()
        await store.send(.foundPCZT(pczt)) { state in
            state.isKeystoneCodeFound = true
            state.pcztWithSigs = pczt
            state.detectedKeystoneFirmware = nil
        }
        await store.receive(.keystoneFirmwareUpdateRequired(detected: nil))
    }

    /// The dismiss action clears the scanned PCZT and the detected firmware
    /// so the user can retry after updating.
    @MainActor
    func test_reducer_dismissKeystoneFirmwareUpdate_clearsScannedState() async {
        var initialState = SendConfirmation.State.initial
        initialState.isKeystoneCodeFound = true
        initialState.pcztWithSigs = stampedBlob(major: 12, minor: 4, build: 0)
        initialState.detectedKeystoneFirmware = KeystoneFirmwareVersion(major: 12, minor: 4, build: 0)

        let store = TestStore(initialState: initialState) {
            SendConfirmation()
        }

        await store.send(.dismissKeystoneFirmwareUpdate) { state in
            state.isKeystoneCodeFound = false
            state.pcztWithSigs = nil
            state.detectedKeystoneFirmware = nil
        }
    }
}
