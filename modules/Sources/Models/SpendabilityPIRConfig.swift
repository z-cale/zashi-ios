import Foundation

public struct SpendabilityPIRConfig: Sendable {
    /// Base URL of the nullifier PIR server (spend-checking).
    public let serverUrl: String
    /// Base URL of the witness PIR server (note commitment witnesses).
    public let witnessServerUrl: String

    public init(serverUrl: String, witnessServerUrl: String) {
        self.serverUrl = serverUrl
        self.witnessServerUrl = witnessServerUrl
    }

    /// Default config. Debug builds connect to local servers;
    /// distribution builds use the production endpoints.
    #if SECANT_DISTRIB
    public static let `default` = SpendabilityPIRConfig(
        serverUrl: "https://164-92-137-124.sslip.io/nullifier",
        witnessServerUrl: "https://164-92-137-124.sslip.io/witness"
    )
    #else
    public static let `default` = SpendabilityPIRConfig(
        serverUrl: "http://localhost:8080",
        witnessServerUrl: "http://localhost:8080/witness"
    )
    #endif
}
