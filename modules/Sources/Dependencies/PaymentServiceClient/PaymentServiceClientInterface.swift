import ComposableArchitecture
import Foundation

extension DependencyValues {
    public var paymentServiceClient: PaymentServiceClient {
        get { self[PaymentServiceClient.self] }
        set { self[PaymentServiceClient.self] = newValue }
    }
}

@DependencyClient
public struct PaymentServiceClient {
    // PIR
    public var resolvePIRTag: @Sendable (_ tag: String) async throws -> PIRResolveResult
    // Payment Link
    public var createPaymentLink: @Sendable (_ request: PaymentLinkCreateRequest) async throws -> PaymentLinkResponse
    public var getPaymentLink: @Sendable (_ id: String) async throws -> PaymentLinkResponse
    public var claimPaymentLink: @Sendable (_ id: String, _ request: ClaimPaymentLinkRequest) async throws -> PaymentLinkResponse
    public var revokePaymentLink: @Sendable (_ id: String) async throws -> PaymentLinkResponse
    // Relay
    public var registerRelay: @Sendable (_ request: RegisterRelayRequest) async throws -> RegisterRelayResponse
    public var resolveRelayByAddress: @Sendable (_ address: String) async throws -> RegisterRelayResponse
    public var getRelayPubkey: @Sendable (_ relayId: String) async throws -> RelayPubkeyResponse
    public var postRelayEncaps: @Sendable (_ relayId: String, _ request: RelayEncapsRequest) async throws -> RelayStatusResponse
    public var getRelayStatus: @Sendable (_ relayId: String, _ encapsId: String) async throws -> RelayStatusResponse
    // Transfer
    public var transfer: @Sendable (_ request: TransferRequest) async throws -> TransferResponse
    // Address alias
    public var registerAlias: @Sendable (_ alias: String, _ owner: String) async throws -> Void
    // Transactions
    public var getTransactions: @Sendable (_ address: String) async throws -> MockTransactionListResponse
    // SSE events
    public var subscribeToEvents: @Sendable (_ address: String) -> AsyncStream<Void> = { _ in AsyncStream { $0.finish() } }
    // Balance
    public var getBalance: @Sendable (_ address: String) async throws -> MockBalanceResponse
}
