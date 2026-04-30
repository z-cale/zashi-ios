import XCTest
import CryptoKit
@testable import VotingModels

// Tests for canonical encoding (RoundManifest.swift) and the
// `VotingServiceConfig.verifyRoundSignatures` Phase 2 hard-fail path.
//
// The known-answer vector pinned here mirrors
// `vote-sdk/cmd/manifest-signer/canonical_test.go::TestRoundManifestKnownAnswerSignature`
// — both implementations MUST produce the same canonical bytes and accept
// the same signature for the same key/inputs, byte-for-byte. If this drifts,
// every wallet build after the drift will fail to verify every round_signatures
// produced by the Go signer (and vice-versa).
//
// swiftlint:disable line_length

final class RoundManifestCanonicalTests: XCTestCase {

    // MARK: - Canonical encoding

    /// Must produce the same 144-byte payload as the Go reference.
    func testCanonicalRoundManifestKnownAnswer() throws {
        let roundID    = try XCTUnwrap(Data(hex: "6823028ccc36f2fffc5a6d9af3e62a918a33913a8f37c2d3efe962a0357aa03f"))
        let eaPK       = try XCTUnwrap(Data(hex: "01020304050607080910111213141516171819202122232425262728293031aa"))
        let valsetHash = try XCTUnwrap(Data(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))

        let payload = canonicalRoundManifestPayload(
            chainID: "svote-1",
            roundID: roundID,
            eaPK: eaPK,
            valsetHash: valsetHash
        )

        XCTAssertEqual(payload.count, 144)
        // Pinned hex from the Go KAT (canonical_test.go).
        let expected = try XCTUnwrap(Data(hex: "001f736869656c6465642d766f74652f726f756e642d6d616e69666573742f7631000773766f74652d3100206823028ccc36f2fffc5a6d9af3e62a918a33913a8f37c2d3efe962a0357aa03f002001020304050607080910111213141516171819202122232425262728293031aa0020aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
        XCTAssertEqual(payload, expected)
    }

    /// Verifies the deterministic ed25519 signature pinned by the Go KAT
    /// against an all-zero seed key. Signing is platform-independent, so this
    /// pin is the strongest available "your encoding matches mine" signal.
    func testRoundManifestKnownAnswerSignatureVerifies() throws {
        // Pubkey derived from RFC 8032 §7.1 zero-seed (also pinned by Go test).
        let pubB64 = "O2onvM62pC1io6jQKm8Nc2UyFXcd4kOmOsBIoYtZ2ik="
        let sigB64 = "vge064r69glI/HQ+ZJPM8n+RcUarjddpjQIHqwyl+SXEfOE8khWJsCuQvCew3/mImqmhP2f8EMFNT4RCIipzCg=="

        let pubBytes = try XCTUnwrap(Data(base64Encoded: pubB64))
        let sigBytes = try XCTUnwrap(Data(base64Encoded: sigB64))
        let pub = try Curve25519.Signing.PublicKey(rawRepresentation: pubBytes)

        let roundID    = try XCTUnwrap(Data(hex: "6823028ccc36f2fffc5a6d9af3e62a918a33913a8f37c2d3efe962a0357aa03f"))
        let eaPK       = try XCTUnwrap(Data(hex: "01020304050607080910111213141516171819202122232425262728293031aa"))
        let valsetHash = try XCTUnwrap(Data(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))

        let payload = canonicalRoundManifestPayload(
            chainID: "svote-1",
            roundID: roundID,
            eaPK: eaPK,
            valsetHash: valsetHash
        )
        XCTAssertTrue(pub.isValidSignature(sigBytes, for: payload), "Swift canonical encoding diverged from Go reference; this would brick all Phase 2 wallets.")

        // Tamper with one byte of the payload — signature must reject.
        var tampered = payload
        tampered[tampered.count - 1] ^= 0x01
        XCTAssertFalse(pub.isValidSignature(sigBytes, for: tampered))
    }

    /// The example signature shipped in token-holder-voting-config/voting-config.example.json.
    /// Pinned so a wallet built against the trust anchor in
    /// `ManifestTrustAnchor.manifestSigners` can verify the example end-to-end
    /// without going through the network.
    func testExampleConfigVerifiesAgainstPinnedTrustAnchor() throws {
        let roundID    = try XCTUnwrap(Data(hex: "6823028ccc36f2fffc5a6d9af3e62a918a33913a8f37c2d3efe962a0357aa03f"))
        let eaPK       = try XCTUnwrap(Data(base64Encoded: "AQIDBAUGBwgJEBESExQVFhcYGSAhIiMkJSYnKCkwMao="))
        let valsetHash = try XCTUnwrap(Data(hex: "4f3e0c2c1d8b1a3e7f2c5b8a9d6e0f1c2a3b4c5d6e7f8090a1b2c3d4e5f60718"))
        let signature  = try XCTUnwrap(Data(base64Encoded: "AYG0pos6UKxAttul6scJJyuyi6TT6O8RcJRgC+MbVdkzvsBHiJyA/ulaqXmpL1EzVxN2N8ukRObZqccCgbh/Aw=="))

        let payload = canonicalRoundManifestPayload(
            chainID: ManifestTrustAnchor.chainID,
            roundID: roundID,
            eaPK: eaPK,
            valsetHash: valsetHash
        )
        let signer = try XCTUnwrap(ManifestTrustAnchor.signersByID["valarg-poc"])
        XCTAssertTrue(signer.parsedKey.isValidSignature(signature, for: payload))
    }
}

// swiftlint:enable line_length

// MARK: - VotingServiceConfig.verifyRoundSignatures

final class VerifyRoundSignaturesTests: XCTestCase {

    // Use a fresh ed25519 keypair per test so we never rely on any external
    // signing service. The trust anchor passed into `verifyRoundSignatures`
    // is constructed from this keypair.
    private struct Fixture {
        let signer: ManifestSigner
        let trustAnchor: [String: ManifestSigner]
        let privateKey: Curve25519.Signing.PrivateKey
        let chainID: String
        let roundIDHex: String
        let roundIDBytes: Data
        let eaPK: Data
        let valsetHash: Data
        let valsetHashHex: String
        let signature: Data

        static func make() throws -> Fixture {
            let priv = Curve25519.Signing.PrivateKey()
            let pubB64 = priv.publicKey.rawRepresentation.base64EncodedString()
            let signer = ManifestSigner(id: "test-signer", publicKeyBase64: pubB64)
            let chainID = "svote-1"
            let roundIDHex = String(repeating: "0a", count: 32)
            let roundIDBytes = try XCTUnwrap(Data(hex: roundIDHex))
            let eaPK = Data((0..<32).map { UInt8($0 + 1) })
            let valsetHashHex = String(repeating: "bb", count: 32)
            let valsetHash = try XCTUnwrap(Data(hex: valsetHashHex))

            let payload = canonicalRoundManifestPayload(
                chainID: chainID,
                roundID: roundIDBytes,
                eaPK: eaPK,
                valsetHash: valsetHash
            )
            let signature = try priv.signature(for: payload)

            return Fixture(
                signer: signer,
                trustAnchor: [signer.id: signer],
                privateKey: priv,
                chainID: chainID,
                roundIDHex: roundIDHex,
                roundIDBytes: roundIDBytes,
                eaPK: eaPK,
                valsetHash: valsetHash,
                valsetHashHex: valsetHashHex,
                signature: signature
            )
        }

        func makeConfig(
            voteRoundId: String? = nil,
            roundSignatures: RoundSignaturesConfig? = nil
        ) -> VotingServiceConfig {
            VotingServiceConfig(
                configVersion: 1,
                voteRoundId: voteRoundId ?? roundIDHex,
                voteServers: [.init(url: "https://x", label: "a")],
                pirEndpoints: [.init(url: "https://y", label: "b")],
                snapshotHeight: 1,
                voteEndTime: 1,
                supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v0", voteServer: "v1"),
                roundSignatures: roundSignatures ?? makeSignatures()
            )
        }

        func makeSignatures(
            roundId: String? = nil,
            eaPKOverride: String? = nil,
            signatures: [RoundSignaturesConfig.SignatureEntry]? = nil
        ) -> RoundSignaturesConfig {
            RoundSignaturesConfig(
                roundId: roundId ?? roundIDHex,
                eaPK: eaPKOverride ?? eaPK.base64EncodedString(),
                valsetHash: valsetHashHex,
                signedPayloadHash: nil,
                signatures: signatures ?? [
                    .init(signer: signer.id, alg: "ed25519", signature: signature.base64EncodedString())
                ]
            )
        }
    }

    func testVerifySucceedsOnGoldenInput() throws {
        let f = try Fixture.make()
        let cfg = f.makeConfig()
        let returned = try cfg.verifyRoundSignatures(
            serverEaPK: f.eaPK,
            signers: f.trustAnchor,
            kRequired: 1,
            chainID: f.chainID
        )
        XCTAssertEqual(returned, f.eaPK)
    }

    func testVerifyHardFailsWhenRoundSignaturesMissing() throws {
        let f = try Fixture.make()
        let cfg = f.makeConfig(roundSignatures: nil) // explicit
        // makeConfig(roundSignatures: nil) currently substitutes makeSignatures(),
        // so build manually for this case.
        let bare = VotingServiceConfig(
            configVersion: 1,
            voteRoundId: f.roundIDHex,
            voteServers: cfg.voteServers,
            pirEndpoints: cfg.pirEndpoints,
            snapshotHeight: 1,
            voteEndTime: 1,
            supportedVersions: cfg.supportedVersions,
            roundSignatures: nil
        )
        XCTAssertThrowsError(
            try bare.verifyRoundSignatures(
                serverEaPK: f.eaPK,
                signers: f.trustAnchor,
                kRequired: 1,
                chainID: f.chainID
            )
        ) { error in
            XCTAssertEqual(error as? VotingConfigError, .manifestSignaturesMissing)
        }
    }

    func testVerifyHardFailsOnRoundIdMismatch() throws {
        let f = try Fixture.make()
        let cfg = f.makeConfig(
            voteRoundId: String(repeating: "ff", count: 32),
            roundSignatures: f.makeSignatures(roundId: f.roundIDHex)
        )
        XCTAssertThrowsError(
            try cfg.verifyRoundSignatures(
                serverEaPK: f.eaPK,
                signers: f.trustAnchor,
                kRequired: 1,
                chainID: f.chainID
            )
        ) { error in
            guard case VotingConfigError.manifestRoundIdMismatch = error else {
                return XCTFail("expected manifestRoundIdMismatch, got \(error)")
            }
        }
    }

    func testVerifyHardFailsOnEaPKMismatch() throws {
        let f = try Fixture.make()
        let cfg = f.makeConfig()
        let serverEaPK = Data(repeating: 0x55, count: 32) // different from manifest's
        XCTAssertThrowsError(
            try cfg.verifyRoundSignatures(
                serverEaPK: serverEaPK,
                signers: f.trustAnchor,
                kRequired: 1,
                chainID: f.chainID
            )
        ) { error in
            guard case VotingConfigError.eaPKMismatch = error else {
                return XCTFail("expected eaPKMismatch, got \(error)")
            }
        }
    }

    func testVerifyHardFailsOnTamperedSignature() throws {
        let f = try Fixture.make()
        var tamperedSig = f.signature
        tamperedSig[0] ^= 0xFF
        let cfg = f.makeConfig(
            roundSignatures: f.makeSignatures(
                signatures: [.init(signer: f.signer.id, alg: "ed25519", signature: tamperedSig.base64EncodedString())]
            )
        )
        XCTAssertThrowsError(
            try cfg.verifyRoundSignatures(
                serverEaPK: f.eaPK,
                signers: f.trustAnchor,
                kRequired: 1,
                chainID: f.chainID
            )
        ) { error in
            guard case VotingConfigError.manifestSignatureInvalid(let matched, let required) = error else {
                return XCTFail("expected manifestSignatureInvalid, got \(error)")
            }
            XCTAssertEqual(matched, 0)
            XCTAssertEqual(required, 1)
        }
    }

    func testVerifyHardFailsWhenSignerIsUnknownToWallet() throws {
        let f = try Fixture.make()
        // Same payload, different signer id that is NOT in the wallet's trust anchor.
        let cfg = f.makeConfig(
            roundSignatures: f.makeSignatures(
                signatures: [.init(signer: "unrecognized-signer", alg: "ed25519", signature: f.signature.base64EncodedString())]
            )
        )
        XCTAssertThrowsError(
            try cfg.verifyRoundSignatures(
                serverEaPK: f.eaPK,
                signers: f.trustAnchor,
                kRequired: 1,
                chainID: f.chainID
            )
        ) { error in
            guard case VotingConfigError.manifestSignatureInvalid = error else {
                return XCTFail("expected manifestSignatureInvalid, got \(error)")
            }
        }
    }

    func testVerifyRequiresKRequiredDistinctSigners() throws {
        let f1 = try Fixture.make()
        // A second independent signer signs the same payload.
        let priv2 = Curve25519.Signing.PrivateKey()
        let signer2 = ManifestSigner(id: "second", publicKeyBase64: priv2.publicKey.rawRepresentation.base64EncodedString())
        let payload = canonicalRoundManifestPayload(
            chainID: f1.chainID,
            roundID: f1.roundIDBytes,
            eaPK: f1.eaPK,
            valsetHash: f1.valsetHash
        )
        let sig2 = try priv2.signature(for: payload)

        let trustAnchor: [String: ManifestSigner] = [
            f1.signer.id: f1.signer,
            signer2.id: signer2
        ]
        let cfg = f1.makeConfig(
            roundSignatures: f1.makeSignatures(signatures: [
                .init(signer: f1.signer.id, alg: "ed25519", signature: f1.signature.base64EncodedString()),
                .init(signer: signer2.id, alg: "ed25519", signature: sig2.base64EncodedString())
            ])
        )

        // k_required = 2 succeeds with both signers.
        XCTAssertNoThrow(
            try cfg.verifyRoundSignatures(
                serverEaPK: f1.eaPK,
                signers: trustAnchor,
                kRequired: 2,
                chainID: f1.chainID
            )
        )
        // k_required = 3 fails: only 2 distinct verified signers exist.
        XCTAssertThrowsError(
            try cfg.verifyRoundSignatures(
                serverEaPK: f1.eaPK,
                signers: trustAnchor,
                kRequired: 3,
                chainID: f1.chainID
            )
        )
    }

    func testVerifyHardFailsOnMalformedManifest() throws {
        let f = try Fixture.make()

        // round_id not 64 hex chars.
        let bad1 = f.makeConfig(
            roundSignatures: f.makeSignatures(roundId: "deadbeef")
        )
        XCTAssertThrowsError(
            try bad1.verifyRoundSignatures(
                serverEaPK: f.eaPK,
                signers: f.trustAnchor,
                kRequired: 1,
                chainID: f.chainID
            )
        ) { error in
            // round_id != vote_round_id wins because we check that first.
            guard case VotingConfigError.manifestRoundIdMismatch = error else {
                return XCTFail("expected manifestRoundIdMismatch, got \(error)")
            }
        }

        // ea_pk not 32 bytes.
        let bad2 = f.makeConfig(
            roundSignatures: f.makeSignatures(eaPKOverride: Data([1, 2, 3]).base64EncodedString())
        )
        XCTAssertThrowsError(
            try bad2.verifyRoundSignatures(
                serverEaPK: f.eaPK,
                signers: f.trustAnchor,
                kRequired: 1,
                chainID: f.chainID
            )
        ) { error in
            guard case VotingConfigError.manifestMalformed = error else {
                return XCTFail("expected manifestMalformed, got \(error)")
            }
        }
    }
}
