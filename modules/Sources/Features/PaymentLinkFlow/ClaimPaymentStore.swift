//
//  ClaimPaymentStore.swift
//  Zashi
//

import ComposableArchitecture
import Foundation
import PaymentServiceClient

@Reducer
public struct ClaimPayment {
    @ObservableState
    public struct State: Equatable {
        public enum Screen: Equatable {
            case loading
            case ready
            case claiming
            case claimed
            case error
        }

        public var screen: Screen = .loading
        public var paymentLinkId: String = ""
        public var amount: String = ""
        public var description: String?
        public var recipientAddress: String = ""
        public var errorMessage: String?

        public init() {}

        public init(linkId: String, amount: String = "", description: String? = nil) {
            self.paymentLinkId = linkId
            self.amount = amount
            self.description = description
        }

        public static let initial = State()
    }

    public enum Action: Equatable {
        case onAppear
        case linkLoaded(PaymentLinkResponse)
        case loadFailed(String)
        case claimTapped
        case claimCompleted(PaymentLinkResponse)
        case claimFailed(String)
        case closeTapped
        case viewTransactionTapped
    }

    @Dependency(\.paymentServiceClient) var paymentServiceClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // If we already have amount info from the URL fragment, go straight to ready
                if !state.amount.isEmpty {
                    state.screen = .ready
                    return .none
                }
                // Otherwise fetch from the service
                let linkId = state.paymentLinkId
                return .run { send in
                    let response = try await paymentServiceClient.getPaymentLink(linkId)
                    await send(.linkLoaded(response))
                } catch: { error, send in
                    await send(.loadFailed(error.localizedDescription))
                }

            case let .linkLoaded(response):
                state.amount = response.amount
                state.description = response.description
                state.screen = .ready
                return .none

            case let .loadFailed(message):
                state.errorMessage = message
                state.screen = .error
                return .none

            case .claimTapped:
                state.screen = .claiming
                let linkId = state.paymentLinkId
                let request = ClaimPaymentLinkRequest(recipientAddress: state.recipientAddress)
                return .run { send in
                    let response = try await paymentServiceClient.claimPaymentLink(linkId, request)
                    await send(.claimCompleted(response))
                } catch: { error, send in
                    await send(.claimFailed(error.localizedDescription))
                }

            case let .claimCompleted(response):
                state.amount = response.amount
                state.screen = .claimed
                return .none

            case let .claimFailed(message):
                state.errorMessage = message
                state.screen = .error
                return .none

            case .closeTapped, .viewTransactionTapped:
                return .none
            }
        }
    }
}
