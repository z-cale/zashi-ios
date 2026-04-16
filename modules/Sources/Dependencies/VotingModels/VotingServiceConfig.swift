import Foundation

/// CDN-hosted config listing vote servers and PIR servers.
/// Fetched at startup from `VotingServiceConfig.configURL`.
/// A local override file (`voting-config-local.json` in the app bundle) takes priority
/// to simplify testing against a local chain.
public struct VotingServiceConfig: Codable, Equatable, Sendable {
    public let version: Int
    public let voteServers: [ServiceEndpoint]
    public let pirServers: [ServiceEndpoint]

    public struct ServiceEndpoint: Codable, Equatable, Sendable {
        public let url: String
        public let label: String

        public init(url: String, label: String) {
            self.url = url
            self.label = label
        }
    }

    public init(version: Int, voteServers: [ServiceEndpoint], pirServers: [ServiceEndpoint]) {
        self.version = version
        self.voteServers = voteServers
        self.pirServers = pirServers
    }

    enum CodingKeys: String, CodingKey {
        case version
        case voteServers = "vote_servers"
        case pirServers = "pir_servers"
    }

    public enum Environment: String, Sendable {
        case staging
        case production

        var configURL: URL {
            let base = "https://valargroup.github.io/token-holder-voting-config"
            return URL(string: "\(base)/\(rawValue)/voting-config.json")!
        }
    }

    /// Active environment. Change at launch before first config fetch.
    public static var environment: Environment = .staging

    /// Config URL for the active environment (served via GitHub Pages CDN).
    public static var configURL: URL { environment.configURL }

    /// Filename for a local override bundled in the app (takes priority over CDN).
    public static let localOverrideFilename = "voting-config-local.json"

    /// Default config used when both local override and CDN are unavailable.
    /// Points at the deployed dev server so TestFlight builds work without CDN.
    public static let fallback = VotingServiceConfig(
        version: 1,
        voteServers: [ServiceEndpoint(url: "https://46-101-255-48.sslip.io", label: "Primary")],
        pirServers: [ServiceEndpoint(url: "https://46-101-255-48.sslip.io/nullifier", label: "PIR Server")]
    )
}
