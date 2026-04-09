//
//  KeystoneFirmwareVersion.swift
//  Zashi
//
//  Reads the firmware version stamp that Keystone writes into every signed
//  PCZT via `global.proprietary["keystone:fw_version"]` and evaluates it
//  against the wallet's minimum-required policy.
//

import Foundation

/// Three-byte Keystone firmware version triple, matching the
/// `SOFTWARE_VERSION_{MAJOR,MINOR,BUILD}` ordering used by
/// `src/config/version.h` in the keystone3-firmware repo.
public struct KeystoneFirmwareVersion: Equatable, Comparable, Hashable {
    public let major: UInt8
    public let minor: UInt8
    public let build: UInt8

    public init(major: UInt8, minor: UInt8, build: UInt8) {
        self.major = major
        self.minor = minor
        self.build = build
    }

    public static func < (lhs: KeystoneFirmwareVersion, rhs: KeystoneFirmwareVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.build < rhs.build
    }

    /// Human-readable "M.N.B" form for UI copy.
    public var displayString: String {
        "\(major).\(minor).\(build)"
    }
}

public extension Data {
    /// Scans a signed PCZT's bytes for the Keystone firmware version stamp.
    ///
    /// The firmware stamps `global.proprietary["keystone:fw_version"] = [M, N, B]`
    /// on every signed response. Because `Pczt` is an opaque `Data` blob on
    /// the Swift side (no FFI exposes proprietary fields), we locate the ASCII
    /// key literal and read the postcard-encoded value that follows.
    ///
    /// Postcard encodes `BTreeMap<String, Vec<u8>>` entries as
    /// `varint len → utf8 bytes → varint len → value bytes`. For a 3-byte value
    /// the length byte is `0x03`, so we verify that and read the next 3 bytes.
    ///
    /// Returns `nil` if the stamp is absent (legacy firmware) or malformed.
    ///
    /// Production-quality follow-up: replace this scanner with a proper FFI
    /// helper in `zcash-swift-wallet-sdk` (see
    /// `zcashlc_pczt_requires_sapling_proofs` as a template).
    func readKeystoneFwVersion() -> KeystoneFirmwareVersion? {
        let key = Data("keystone:fw_version".utf8)
        guard let range = self.range(of: key) else { return nil }
        let valueStart = range.upperBound
        // Need at least `0x03` + 3 version bytes after the key.
        guard valueStart + 4 <= self.endIndex, self[valueStart] == 0x03 else {
            return nil
        }
        return KeystoneFirmwareVersion(
            major: self[valueStart + 1],
            minor: self[valueStart + 2],
            build: self[valueStart + 3]
        )
    }
}

/// Policy for deciding whether to broadcast a Keystone-signed transaction
/// given the detected firmware version.
public enum KeystoneFirmwarePolicy {
    public enum Outcome: Equatable {
        /// Firmware reports a version and it meets the minimum.
        case ok
        /// Firmware reports a version but it's below the minimum.
        case updateRequired
        /// Firmware did not stamp a version. Pre-negotiation (legacy) build.
        case legacy
    }

    public static func evaluate(
        detected: KeystoneFirmwareVersion?,
        required: KeystoneFirmwareVersion
    ) -> Outcome {
        guard let detected else { return .legacy }
        return detected >= required ? .ok : .updateRequired
    }
}
