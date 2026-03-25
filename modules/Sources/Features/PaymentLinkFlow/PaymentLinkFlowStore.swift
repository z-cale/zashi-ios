//
//  PaymentLinkFlowStore.swift
//  Zashi
//

import ComposableArchitecture
import Foundation
import PaymentServiceClient

@Reducer
public struct PaymentLinkFlow {
    @ObservableState
    public struct State: Equatable {
        public enum Screen: Equatable {
            case enterAmount
            case creating
            case linkReady
            case revoking
            case revoked
        }

        public var screen: Screen = .enterAmount
        public var amount: String = ""
        public var description: String = ""
        public var senderAddress: String = ""
        public var balance: String = "12.5"
        public var paymentLink: PaymentLinkResponse?
        public var qrContent: String = ""
        public var isSharePresented: Bool = false
        public var error: String?

        public var isOverBalance: Bool {
            guard let value = Double(amount), let bal = Double(balance) else { return false }
            return value > bal
        }

        public var isValidAmount: Bool {
            guard let value = Double(amount) else { return false }
            return value > 0 && !isOverBalance
        }

        public init() {}

        public static let initial = State()
    }

    public enum Action: Equatable {
        case amountChanged(String)
        case createTapped
        case linkCreated(PaymentLinkResponse)
        case createFailed(String)
        case shareLinkTapped
        case shareQRTapped
        case shareFinished
        case revokeTapped
        case revokeCompleted(PaymentLinkResponse)
        case revokeFailed(String)
        case closeTapped
        case backTapped
    }

    @Dependency(\.paymentServiceClient) var paymentServiceClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .amountChanged(text):
                state.amount = text
                return .none

            case .createTapped:
                guard state.isValidAmount else { return .none }
                state.screen = .creating
                let request = PaymentLinkCreateRequest(
                    amount: state.amount,
                    senderAddress: state.senderAddress,
                    description: state.description.isEmpty ? nil : state.description
                )
                return .run { send in
                    let response = try await paymentServiceClient.createPaymentLink(request)
                    await send(.linkCreated(response))
                } catch: { error, send in
                    await send(.createFailed(error.localizedDescription))
                }

            case let .linkCreated(response):
                state.paymentLink = response
                // Build ZIP-324 URI
                var fragment = "amount=\(response.amount)&key=\(response.ephemeralKey)"
                if let desc = response.description, !desc.isEmpty {
                    let encoded = desc.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? desc
                    fragment += "&desc=\(encoded)"
                }
                state.qrContent = "https://pay.withzcash.com:65536/payment/v1#\(fragment)"
                state.screen = .linkReady
                return .none

            case let .createFailed(message):
                state.error = message
                state.screen = .enterAmount
                return .none

            case .shareLinkTapped:
                state.isSharePresented = true
                return .none

            case .shareQRTapped:
                state.isSharePresented = true
                return .none

            case .shareFinished:
                state.isSharePresented = false
                return .none

            case .revokeTapped:
                guard let linkId = state.paymentLink?.id else { return .none }
                state.screen = .revoking
                return .run { send in
                    let response = try await paymentServiceClient.revokePaymentLink(linkId)
                    await send(.revokeCompleted(response))
                } catch: { error, send in
                    await send(.revokeFailed(error.localizedDescription))
                }

            case let .revokeCompleted(response):
                state.paymentLink = response
                state.screen = .revoked
                return .none

            case let .revokeFailed(message):
                state.error = message
                state.screen = .linkReady
                return .none

            case .closeTapped, .backTapped:
                return .none
            }
        }
    }
}
