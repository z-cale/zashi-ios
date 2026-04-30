import CryptoKit
import Foundation

// MARK: - Trust anchor (compiled into the wallet bundle)

/// Build-time trust anchor for round-manifest and checkpoint verification.
///
/// `manifest_signers[]` and `kRequired` are baked into the binary. Rotating
/// them is a wallet release per
/// `vote-sdk/docs/runbooks/key-rotation.md` — never a CDN push.
///
/// `chainID` pins the chain this build is for; it appears in the canonical
/// signing payload and must match what `manifest-signer sign-round`
/// passes to `--chain-id` on the operator side.
enum ManifestTrustAnchor {
    /// Cosmos chain id (matches `--chain-id` on the signer CLI).
    static let chainID = "svote-1"

    /// Minimum number of distinct valid signatures required to accept a
    /// round_signatures or checkpoint. A larger value reduces the impact of
    /// any single signer's key compromise. Bump this in lockstep with adding
    /// a new entry to `manifestSigners`.
    static let kRequired: Int = 1

    /// Pinned signer pubkeys. New entries arrive only via a wallet release.
    ///
    /// ⚠️ **POC ONLY**: `valarg-poc` is the dev key whose private half lives
    /// outside source control. Replace before mainnet — see
    /// `vote-sdk/docs/runbooks/key-rotation.md`.
    static let manifestSigners: [ManifestSigner] = [
        // valarg-poc — base64 32-byte ed25519 public key,
        // matches token-holder-voting-config/manifest-signers/valarg-poc.pub.
        ManifestSigner(id: "valarg-poc", publicKeyBase64: "eyQhDJDuqnFOj3CU2AtISt8+tUQwsi2BDth6cDXRsps=")
    ]

    /// Lookup-by-id table for verification.
    static let signersByID: [String: ManifestSigner] = {
        Dictionary(uniqueKeysWithValues: manifestSigners.map { ($0.id, $0) })
    }()
}

/// One enrolled signer pubkey. The `parsedKey` is a CryptoKit value usable
/// for `isValidSignature`; it is force-unwrapped at construction because a
/// malformed pubkey here is a build-time bug, not a runtime condition.
struct ManifestSigner: Sendable, Equatable {
    let id: String
    let publicKeyBase64: String
    let parsedKey: Curve25519.Signing.PublicKey

    init(id: String, publicKeyBase64: String) {
        self.id = id
        self.publicKeyBase64 = publicKeyBase64
        guard
            let raw = Data(base64Encoded: publicKeyBase64),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else {
            preconditionFailure("ManifestSigner \(id): pubkey \"\(publicKeyBase64)\" is not a valid 32-byte ed25519 public key. Fix the entry in ManifestTrustAnchor.manifestSigners.")
        }
        self.parsedKey = key
    }

    static func == (lhs: ManifestSigner, rhs: ManifestSigner) -> Bool {
        lhs.id == rhs.id && lhs.publicKeyBase64 == rhs.publicKeyBase64
    }
}

// MARK: - JSON shape for round_signatures

/// `round_signatures` from `voting-config.json`. Optional on the parent
/// config; Phase-2 wallets hard-fail with `manifestSignaturesMissing` when
/// absent. See vote-sdk/docs/config.md §"round_signatures schema".
struct RoundSignaturesConfig: Codable, Equatable, Sendable {
    let roundId: String
    let eaPK: String
    let valsetHash: String
    let signedPayloadHash: String?
    let signatures: [SignatureEntry]

    struct SignatureEntry: Codable, Equatable, Sendable {
        let signer: String
        let alg: String
        let signature: String
    }

    enum CodingKeys: String, CodingKey {
        case roundId = "round_id"
        case eaPK = "ea_pk"
        case valsetHash = "valset_hash"
        case signedPayloadHash = "signed_payload_hash"
        case signatures
    }
}

// MARK: - Canonical encoding

/// Domain separator for round-manifest signatures. Bumping the trailing
/// `/v1` is a breaking change requiring coordinated wallet + signer
/// releases. See vote-sdk/docs/config.md §"Versioning".
enum ManifestDomain {
    static let roundManifestV1 = "shielded-vote/round-manifest/v1"
    static let checkpointV1    = "shielded-vote/checkpoint/v1"
}

/// Encode `(domain_sep, chain_id, round_id, ea_pk, valset_hash)` to the
/// canonical bytes that the manifest signer signs over.
///
/// Each variable-length field is u16-big-endian length-prefixed. This must
/// match `vote-sdk/cmd/manifest-signer/canonical.go` byte-for-byte; the Go
/// known-answer test (`TestRoundManifestKnownAnswerSignature`) and the
/// Swift KAT (`testCanonicalRoundManifestKnownAnswer`) both pin the same
/// vector so divergence is caught immediately in either code base.
func canonicalRoundManifestPayload(
    chainID: String,
    roundID: Data,
    eaPK: Data,
    valsetHash: Data
) -> Data {
    var out = Data()
    out.append(lengthPrefixed(Data(ManifestDomain.roundManifestV1.utf8)))
    out.append(lengthPrefixed(Data(chainID.utf8)))
    out.append(lengthPrefixed(roundID))
    out.append(lengthPrefixed(eaPK))
    out.append(lengthPrefixed(valsetHash))
    return out
}

/// Sibling of `canonicalRoundManifestPayload` for checkpoints.
func canonicalCheckpointPayload(
    chainID: String,
    height: UInt64,
    headerHash: Data,
    valsetHash: Data,
    appHash: Data,
    issuedAt: UInt64
) -> Data {
    var out = Data()
    out.append(lengthPrefixed(Data(ManifestDomain.checkpointV1.utf8)))
    out.append(lengthPrefixed(Data(chainID.utf8)))
    out.append(uint64BE(height))
    out.append(lengthPrefixed(headerHash))
    out.append(lengthPrefixed(valsetHash))
    out.append(lengthPrefixed(appHash))
    out.append(uint64BE(issuedAt))
    return out
}

private func lengthPrefixed(_ data: Data) -> Data {
    precondition(data.count <= 0xFFFF, "manifest payload field exceeds u16 length cap")
    var out = Data(capacity: 2 + data.count)
    out.append(uint16BE(UInt16(data.count)))
    out.append(data)
    return out
}

private func uint16BE(_ value: UInt16) -> Data {
    Data([UInt8(value >> 8), UInt8(value & 0xFF)])
}

private func uint64BE(_ value: UInt64) -> Data {
    var bytes = [UInt8](repeating: 0, count: 8)
    var v = value
    for i in (0..<8).reversed() {
        bytes[i] = UInt8(v & 0xFF)
        v >>= 8
    }
    return Data(bytes)
}

// MARK: - Hex helper

extension Data {
    /// Decode a lowercase or uppercase hex string into bytes. Returns nil for
    /// invalid input (odd length, non-hex characters).
    init?(hex: String) {
        let normalized = hex.lowercased()
        guard normalized.count % 2 == 0 else { return nil }
        var out = Data(capacity: normalized.count / 2)
        var idx = normalized.startIndex
        while idx < normalized.endIndex {
            let next = normalized.index(idx, offsetBy: 2)
            guard let byte = UInt8(normalized[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        self = out
    }
}
