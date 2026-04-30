import CryptoKit
import Foundation

/// CDN-hosted voting service configuration as specified in ZIP 1244 §"Vote Configuration Format".
///
/// A JSON document published per voting round; fetched at startup from `configURL`.
/// A debug-only local override (`localOverrideFilename` in the app bundle) takes priority for testing.
struct VotingServiceConfig: Codable, Equatable, Sendable {
    let configVersion: Int
    let voteRoundId: String
    let voteServers: [ServiceEndpoint]
    let pirEndpoints: [ServiceEndpoint]
    let snapshotHeight: UInt64
    let voteEndTime: UInt64
    let proposals: [Proposal]
    let supportedVersions: SupportedVersions
    /// Phase 1+: signed off-chain attestation that the chain's `ea_pk` for
    /// `voteRoundId` came from the TSS ceremony. Phase 2 wallets hard-fail
    /// with `manifestSignaturesMissing` when this field is absent. See
    /// `RoundSignaturesConfig` and vote-sdk/docs/config.md.
    let roundSignatures: RoundSignaturesConfig?

    struct ServiceEndpoint: Codable, Equatable, Sendable {
        let url: String
        let label: String

        init(url: String, label: String) {
            self.url = url
            self.label = label
        }
    }

    struct SupportedVersions: Codable, Equatable, Sendable {
        let pir: [String]
        let voteProtocol: String
        let tally: String
        let voteServer: String

        init(pir: [String], voteProtocol: String, tally: String, voteServer: String) {
            self.pir = pir
            self.voteProtocol = voteProtocol
            self.tally = tally
            self.voteServer = voteServer
        }

        enum CodingKeys: String, CodingKey {
            case pir
            case voteProtocol = "vote_protocol"
            case tally
            case voteServer = "vote_server"
        }
    }

    struct Proposal: Codable, Equatable, Sendable {
        let id: Int
        let title: String
        let description: String
        let options: [Option]

        init(id: Int, title: String, description: String, options: [Option]) {
            self.id = id
            self.title = title
            self.description = description
            self.options = options
        }

        struct Option: Codable, Equatable, Sendable {
            let index: Int
            let label: String

            init(index: Int, label: String) {
                self.index = index
                self.label = label
            }
        }
    }

    init(
        configVersion: Int,
        voteRoundId: String,
        voteServers: [ServiceEndpoint],
        pirEndpoints: [ServiceEndpoint],
        snapshotHeight: UInt64,
        voteEndTime: UInt64,
        proposals: [Proposal],
        supportedVersions: SupportedVersions,
        roundSignatures: RoundSignaturesConfig? = nil
    ) {
        self.configVersion = configVersion
        self.voteRoundId = voteRoundId
        self.voteServers = voteServers
        self.pirEndpoints = pirEndpoints
        self.snapshotHeight = snapshotHeight
        self.voteEndTime = voteEndTime
        self.proposals = proposals
        self.supportedVersions = supportedVersions
        self.roundSignatures = roundSignatures
    }

    enum CodingKeys: String, CodingKey {
        case configVersion = "config_version"
        case voteRoundId = "vote_round_id"
        case voteServers = "vote_servers"
        case pirEndpoints = "pir_endpoints"
        case snapshotHeight = "snapshot_height"
        case voteEndTime = "vote_end_time"
        case proposals
        case supportedVersions = "supported_versions"
        case roundSignatures = "round_signatures"
    }

    /// Config URL served via GitHub Pages CDN.
    public static let configURL = URL(string: "https://valargroup.github.io/token-holder-voting-config/voting-config.json")!

    /// Filename for a local override bundled in the app (debug-only).
    static let localOverrideFilename = "voting-config-local.json"

    #if DEBUG
    /// Debug-only config used by previews and tests. Not used on the live path —
    /// a CDN fetch or decode failure surfaces as a `VotingConfigError` instead.
    static let debugFallback = VotingServiceConfig(
        configVersion: 1,
        voteRoundId: String(repeating: "0", count: 64),
        voteServers: [ServiceEndpoint(url: "https://vote-chain-primary.valargroup.org", label: "Primary")],
        pirEndpoints: [ServiceEndpoint(url: "https://pir.valargroup.org", label: "PIR Server")],
        snapshotHeight: 0,
        voteEndTime: 0,
        proposals: [],
        supportedVersions: SupportedVersions(
            pir: ["v0"],
            voteProtocol: "v0",
            tally: "v0",
            voteServer: "v1"
        ),
        roundSignatures: nil
    )
    #endif
}

// MARK: - Wallet capabilities

/// Versions of each voting-protocol component this wallet build can handle.
/// Values MUST reflect what the app (including `VotingRustBackend`) actually implements —
/// not what it aspires to — or the wallet will reject valid configs and lock users out.
enum WalletCapabilities {
    static let voteServer: Set<String> = ["v1"]
    static let voteProtocol: Set<String> = ["v0"]
    static let tally: Set<String> = ["v0"]
    static let pir: Set<String> = ["v0"]
}

// MARK: - Errors

enum VotingConfigError: Error, Equatable, LocalizedError {
    case decodeFailed(String)
    case unsupportedVersion(component: String, advertised: String)
    case proposalsHashMismatch(expected: Data, actual: Data)
    case roundIdMismatch(configRoundId: String, chainRoundId: String)

    // Round-manifest verification failures (Phase 2). See
    // vote-sdk/docs/config.md §"Wallet verification decision tree" for which
    // case triggers when. All hard-fail; none are skippable from the UX.
    /// `round_signatures` is missing from the CDN config — Phase 2 wallets
    /// refuse to vote without it. Recovery: wait for the publisher to push,
    /// or update the wallet to a build that doesn't yet require it.
    case manifestSignaturesMissing
    /// `round_signatures.round_id` doesn't match `vote_round_id`. The CDN
    /// config is internally inconsistent — the publisher made an error.
    case manifestRoundIdMismatch(configRoundId: String, manifestRoundId: String)
    /// One or more fields in `round_signatures` are not the expected length /
    /// format (e.g. `round_id` not 32 bytes hex, `ea_pk` not 32 bytes b64).
    case manifestMalformed(detail: String)
    /// Fewer than `kRequired` distinct signers produced a valid signature
    /// against pinned wallet trust anchor. Most likely tampered CDN, expired
    /// signer set, or stripped signatures. NOT user-skippable.
    case manifestSignatureInvalid(matched: Int, required: Int)
    /// `round_signatures.ea_pk` does not match the `ea_pk` the chain's vote
    /// server returns for this round. This is the cross-check that catches a
    /// hijacked-vote-server attack even before light-client verification.
    case eaPKMismatch(manifest: Data, server: Data)

    var errorDescription: String? {
        switch self {
        case .decodeFailed(let detail):
            return "Voting config decode failed: \(detail)"
        case .unsupportedVersion(let component, let advertised):
            return "Wallet does not support \(component) version \"\(advertised)\". Please update the wallet."
        case .proposalsHashMismatch:
            return "Voting config proposals don't match the active round. Please update the wallet."
        case .roundIdMismatch(let configRoundId, let chainRoundId):
            return "Voting config is for round \(configRoundId.prefix(16))… but the active round is \(chainRoundId.prefix(16))…. Please update the wallet."
        case .manifestSignaturesMissing:
            return "Could not authenticate this round: the round manifest signature is missing. Please wait for the publisher to update the config, or update the wallet."
        case .manifestRoundIdMismatch(let cfg, let manifest):
            return "Could not authenticate this round: round_signatures.round_id (\(manifest.prefix(16))…) does not match vote_round_id (\(cfg.prefix(16))…)."
        case .manifestMalformed(let detail):
            return "Could not authenticate this round: round_signatures malformed (\(detail))."
        case .manifestSignatureInvalid(let matched, let required):
            return "Could not authenticate this round: only \(matched) of \(required) required signatures were valid. Please update the wallet."
        case .eaPKMismatch:
            return "Could not authenticate this round: the election authority key returned by the vote server does not match the off-chain attestation. Refusing to vote."
        }
    }
}

// MARK: - Validation (ZIP 1244 §"Version Handling")

extension VotingServiceConfig {
    /// Throws `VotingConfigError.unsupportedVersion` on the first component the wallet doesn't support.
    func validate() throws {
        if !WalletCapabilities.voteServer.contains(supportedVersions.voteServer) {
            throw VotingConfigError.unsupportedVersion(
                component: "vote_server",
                advertised: supportedVersions.voteServer
            )
        }
        if !WalletCapabilities.voteProtocol.contains(supportedVersions.voteProtocol) {
            throw VotingConfigError.unsupportedVersion(
                component: "vote_protocol",
                advertised: supportedVersions.voteProtocol
            )
        }
        if !WalletCapabilities.tally.contains(supportedVersions.tally) {
            throw VotingConfigError.unsupportedVersion(
                component: "tally",
                advertised: supportedVersions.tally
            )
        }
        if WalletCapabilities.pir.isDisjoint(with: supportedVersions.pir) {
            throw VotingConfigError.unsupportedVersion(
                component: "pir",
                advertised: supportedVersions.pir.joined(separator: ",")
            )
        }
    }
}

// MARK: - Proposals hash (ZIP 1244 §"Proposals Hash")

extension VotingServiceConfig {
    /// SHA-256 of the canonical JSON serialization of the proposals array.
    static func computeProposalsHash(_ proposals: [Proposal]) -> Data {
        Data(SHA256.hash(data: Data(canonicalProposalsJSON(proposals).utf8)))
    }

    /// Canonical JSON form per ZIP 1244: proposals sorted by `id` ascending, options by `index` ascending,
    /// no whitespace, keys in order `id`, `title`, `description`, `options` (and `index`, `label` for each option).
    static func canonicalProposalsJSON(_ proposals: [Proposal]) -> String {
        let sortedProposals = proposals.sorted { $0.id < $1.id }
        let parts = sortedProposals.map { proposal -> String in
            let sortedOptions = proposal.options.sorted { $0.index < $1.index }
            let optionParts = sortedOptions.map { option -> String in
                "{\"index\":\(option.index),\"label\":\(jsonEncodedString(option.label))}"
            }
            return "{\"id\":\(proposal.id),\"title\":\(jsonEncodedString(proposal.title)),\"description\":\(jsonEncodedString(proposal.description)),\"options\":[\(optionParts.joined(separator: ","))]}"
        }
        return "[\(parts.joined(separator: ","))]"
    }

    /// JSON-encode a Swift string to match the Rust `serde_json::to_string` byte output.
    /// `JSONEncoder` with `.withoutEscapingSlashes` leaves `/` un-escaped (Swift default: `\/`);
    /// otherwise defaults match serde_json (UTF-8 for non-ASCII, `\uXXXX` for control chars).
    /// The chain server computes `proposals_hash` using `serde_json`, so divergence here would
    /// cause a hard-fail `proposalsHashMismatch` any time a proposal title or label contained `/`.
    // swiftlint:disable:next force_try
    private static func jsonEncodedString(_ s: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try! encoder.encode(s)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Round-manifest verification (Phase 2)

extension VotingServiceConfig {
    /// Verify `round_signatures` against the wallet's pinned manifest signers
    /// AND cross-check `ea_pk` byte-for-byte against the value returned by
    /// the vote server for the active round. On success, returns the
    /// 32-byte `ea_pk` the wallet should encrypt to. On any failure throws a
    /// `VotingConfigError` — the caller MUST hard-fail (no skip / retry).
    ///
    /// Implements the "Phase 2 wallet pseudocode" block in
    /// vote-sdk/docs/config.md §"Wallet verification decision tree".
    ///
    /// - Parameters:
    ///   - serverEaPK: the `ea_pk` the chain REST API returned for this
    ///     round's `VoteRound`. Cross-checking against this catches a
    ///     hijacked single vote-server even before light-client verification.
    ///   - trustAnchor: the wallet's compiled-in signer pubkeys & threshold.
    ///     Defaults to `ManifestTrustAnchor`; injectable for tests.
    @discardableResult
    func verifyRoundSignatures(
        serverEaPK: Data,
        signers: [String: ManifestSigner] = ManifestTrustAnchor.signersByID,
        kRequired: Int = ManifestTrustAnchor.kRequired,
        chainID: String = ManifestTrustAnchor.chainID
    ) throws -> Data {
        guard let sigs = roundSignatures else {
            throw VotingConfigError.manifestSignaturesMissing
        }

        // 1. round_id (manifest) must match vote_round_id (config).
        guard sigs.roundId.lowercased() == voteRoundId.lowercased() else {
            throw VotingConfigError.manifestRoundIdMismatch(
                configRoundId: voteRoundId,
                manifestRoundId: sigs.roundId
            )
        }

        // 2. Decode the bytes and check lengths up-front so we never feed
        //    junk into the canonical encoder (which would precondition-fail).
        guard let roundIDBytes = Data(hex: sigs.roundId), roundIDBytes.count == 32 else {
            throw VotingConfigError.manifestMalformed(detail: "round_id is not 32-byte hex")
        }
        guard let valsetHashBytes = Data(hex: sigs.valsetHash), valsetHashBytes.count == 32 else {
            throw VotingConfigError.manifestMalformed(detail: "valset_hash is not 32-byte hex")
        }
        guard let eaPKBytes = Data(base64Encoded: sigs.eaPK), eaPKBytes.count == 32 else {
            throw VotingConfigError.manifestMalformed(detail: "ea_pk is not 32-byte base64")
        }

        // 3. Cross-check: server-returned ea_pk MUST match the attested one,
        //    byte-for-byte. This branch is what makes a Kelp-style hijacked
        //    vote-server unable to substitute a different ea_pk than the one
        //    the publisher signed off-chain.
        guard eaPKBytes == serverEaPK else {
            throw VotingConfigError.eaPKMismatch(manifest: eaPKBytes, server: serverEaPK)
        }

        // 4. Reconstruct the canonical signing payload. The bytes here
        //    must match what the manifest-signer Go binary emitted.
        let payload = canonicalRoundManifestPayload(
            chainID: chainID,
            roundID: roundIDBytes,
            eaPK: eaPKBytes,
            valsetHash: valsetHashBytes
        )

        // 5. Walk signatures[]; count distinct verified signers.
        var verifiedSigners = Set<String>()
        for entry in sigs.signatures {
            guard entry.alg == "ed25519" else { continue }
            guard let signer = signers[entry.signer] else { continue }
            guard let sigBytes = Data(base64Encoded: entry.signature), sigBytes.count == 64 else { continue }
            if signer.parsedKey.isValidSignature(sigBytes, for: payload) {
                verifiedSigners.insert(entry.signer)
            }
        }

        guard verifiedSigners.count >= kRequired else {
            throw VotingConfigError.manifestSignatureInvalid(
                matched: verifiedSigners.count,
                required: kRequired
            )
        }

        return eaPKBytes
    }
}
