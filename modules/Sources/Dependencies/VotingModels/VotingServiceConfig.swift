import CryptoKit
import Foundation

/// CDN-hosted voting service configuration as specified in ZIP 1244 §"Vote Configuration Format".
///
/// A JSON document published per voting round; fetched at startup from `configURL`.
/// A debug-only local override (`localOverrideFilename` in the app bundle) takes priority for testing.
public struct VotingServiceConfig: Codable, Equatable, Sendable {
    public let configVersion: Int
    public let voteRoundId: String
    public let voteServers: [ServiceEndpoint]
    public let pirEndpoints: [ServiceEndpoint]
    public let snapshotHeight: UInt64
    public let voteEndTime: UInt64
    public let proposals: [Proposal]
    public let supportedVersions: SupportedVersions

    public struct ServiceEndpoint: Codable, Equatable, Sendable {
        public let url: String
        public let label: String

        public init(url: String, label: String) {
            self.url = url
            self.label = label
        }
    }

    public struct SupportedVersions: Codable, Equatable, Sendable {
        public let pir: [String]
        public let voteProtocol: String
        public let tally: String
        public let voteServer: String

        public init(pir: [String], voteProtocol: String, tally: String, voteServer: String) {
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

    public struct Proposal: Codable, Equatable, Sendable {
        public let id: Int
        public let title: String
        public let options: [Option]

        public init(id: Int, title: String, options: [Option]) {
            self.id = id
            self.title = title
            self.options = options
        }

        public struct Option: Codable, Equatable, Sendable {
            public let index: Int
            public let label: String

            public init(index: Int, label: String) {
                self.index = index
                self.label = label
            }
        }
    }

    public init(
        configVersion: Int,
        voteRoundId: String,
        voteServers: [ServiceEndpoint],
        pirEndpoints: [ServiceEndpoint],
        snapshotHeight: UInt64,
        voteEndTime: UInt64,
        proposals: [Proposal],
        supportedVersions: SupportedVersions
    ) {
        self.configVersion = configVersion
        self.voteRoundId = voteRoundId
        self.voteServers = voteServers
        self.pirEndpoints = pirEndpoints
        self.snapshotHeight = snapshotHeight
        self.voteEndTime = voteEndTime
        self.proposals = proposals
        self.supportedVersions = supportedVersions
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
    }

    /// Config URL served via GitHub Pages CDN.
    public static let configURL = URL(string: "https://valargroup.github.io/token-holder-voting-config/voting-config.json")!

    /// Filename for a local override bundled in the app (debug-only).
    public static let localOverrideFilename = "voting-config-local.json"

    #if DEBUG
    /// Debug-only config used by previews and tests. Not used on the live path —
    /// a CDN fetch or decode failure surfaces as a `VotingConfigError` instead.
    public static let debugFallback = VotingServiceConfig(
        configVersion: 1,
        voteRoundId: String(repeating: "0", count: 64),
        voteServers: [ServiceEndpoint(url: "https://46-101-255-48.sslip.io", label: "Primary")],
        pirEndpoints: [ServiceEndpoint(url: "https://46-101-255-48.sslip.io/nullifier", label: "PIR Server")],
        snapshotHeight: 0,
        voteEndTime: 0,
        proposals: [],
        supportedVersions: SupportedVersions(
            pir: ["v0"],
            voteProtocol: "v0",
            tally: "v0",
            voteServer: "v1"
        )
    )
    #endif
}

// MARK: - Wallet capabilities

/// Versions of each voting-protocol component this wallet build can handle.
/// Values MUST reflect what the app (including `VotingRustBackend`) actually implements —
/// not what it aspires to — or the wallet will reject valid configs and lock users out.
public enum WalletCapabilities {
    public static let voteServer: Set<String> = ["v1"]
    public static let voteProtocol: Set<String> = ["v0"]
    public static let tally: Set<String> = ["v0"]
    public static let pir: Set<String> = ["v0"]
}

// MARK: - Errors

public enum VotingConfigError: Error, Equatable, LocalizedError {
    case decodeFailed(String)
    case unsupportedVersion(component: String, advertised: String)
    case proposalsHashMismatch(expected: Data, actual: Data)
    case roundIdMismatch(configRoundId: String, chainRoundId: String)

    public var errorDescription: String? {
        switch self {
        case .decodeFailed(let detail):
            return "Voting config decode failed: \(detail)"
        case .unsupportedVersion(let component, let advertised):
            return "Wallet does not support \(component) version \"\(advertised)\". Please update the wallet."
        case .proposalsHashMismatch:
            return "Voting config proposals don't match the active round. Please update the wallet."
        case .roundIdMismatch(let configRoundId, let chainRoundId):
            return "Voting config is for round \(configRoundId.prefix(16))… but the active round is \(chainRoundId.prefix(16))…. Please update the wallet."
        }
    }
}

// MARK: - Validation (ZIP 1244 §"Version Handling")

extension VotingServiceConfig {
    /// Throws `VotingConfigError.unsupportedVersion` on the first component the wallet doesn't support.
    public func validate() throws {
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
    public static func computeProposalsHash(_ proposals: [Proposal]) -> Data {
        Data(SHA256.hash(data: Data(canonicalProposalsJSON(proposals).utf8)))
    }

    /// Canonical JSON form per ZIP 1244: proposals sorted by `id` ascending, options by `index` ascending,
    /// no whitespace, keys in order `id`, `title`, `options` (and `index`, `label` for each option).
    public static func canonicalProposalsJSON(_ proposals: [Proposal]) -> String {
        let sortedProposals = proposals.sorted { $0.id < $1.id }
        let parts = sortedProposals.map { proposal -> String in
            let sortedOptions = proposal.options.sorted { $0.index < $1.index }
            let optionParts = sortedOptions.map { option -> String in
                "{\"index\":\(option.index),\"label\":\(jsonEncodedString(option.label))}"
            }
            return "{\"id\":\(proposal.id),\"title\":\(jsonEncodedString(proposal.title)),\"options\":[\(optionParts.joined(separator: ","))]}"
        }
        return "[\(parts.joined(separator: ","))]"
    }

    /// JSON-encode a Swift string to match the Rust `serde_json::to_string` byte output.
    /// `JSONEncoder` with `.withoutEscapingSlashes` leaves `/` un-escaped (Swift default: `\/`);
    /// otherwise defaults match serde_json (UTF-8 for non-ASCII, `\uXXXX` for control chars).
    /// The chain server computes `proposals_hash` using `serde_json`, so divergence here would
    /// cause a hard-fail `proposalsHashMismatch` any time a proposal title or label contained `/`.
    private static func jsonEncodedString(_ s: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try! encoder.encode(s)
        return String(decoding: data, as: UTF8.self)
    }
}
