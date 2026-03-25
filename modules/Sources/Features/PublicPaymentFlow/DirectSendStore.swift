//
//  DirectSendStore.swift
//  Zashi
//
//  Direct send to a Linkable Dynamic Address (dyn1).
//  Flow: PIR resolve → ML-KEM encapsulate (mocked) → transfer → done
//

import ComposableArchitecture
import Foundation
import PaymentServiceClient

@Reducer
public struct DirectSend {
    @ObservableState
    public struct State: Equatable {
        public enum Step: Equatable {
            case confirm
            case resolving
            case sending
            case sent
            case failed
        }

        public var recipientAddress: String = ""
        public var senderAddress: String = ""
        public var amount: String = ""
        public var step: Step = .confirm
        public var resolvedPubkey: String?
        public var txId: String?
        public var error: String?

        public var fee: String { "0.00001" }

        public var totalAmount: String {
            guard let amt = Double(amount), let f = Double(fee) else { return amount }
            return String(format: "%.5f", amt + f)
        }

        public init() {}
        public static let initial = State()
    }

    public enum Action: Equatable {
        case sendTapped
        case pirResolveCompleted(String) // resolved public key
        case transferCompleted(String)   // tx ID
        case failed(String)
        case closeTapped
        case backTapped
    }

    @Dependency(\.paymentServiceClient) var paymentServiceClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .sendTapped:
                state.step = .resolving
                let address = state.recipientAddress
                let senderAddress = state.senderAddress
                let amount = state.amount

                // Extract the PIR tag from the dyn1 address (everything after "dyn1")
                let tag = String(address.dropFirst(4).prefix(30))

                return .run { send in
                    // Step 1: PIR resolve
                    var pubkey = "mock-pq-pubkey-fallback"
                    if let pirResult = try? await paymentServiceClient.resolvePIRTag(tag) {
                        pubkey = pirResult.publicKey
                    }
                    await send(.pirResolveCompleted(pubkey))
                }

            case let .pirResolveCompleted(pubkey):
                state.resolvedPubkey = pubkey
                state.step = .sending

                let request = TransferRequest(
                    senderAddress: state.senderAddress,
                    recipientAddress: state.recipientAddress,
                    amount: state.amount
                )

                return .run { send in
                    // Step 2: Transfer funds via mock service
                    let response = try await paymentServiceClient.transfer(request)
                    await send(.transferCompleted(response.txId))
                } catch: { error, send in
                    await send(.failed(error.localizedDescription))
                }

            case let .transferCompleted(txId):
                state.txId = txId
                state.step = .sent
                return .none

            case let .failed(message):
                state.error = message
                state.step = .failed
                return .none

            case .closeTapped, .backTapped:
                return .none
            }
        }
    }
}
