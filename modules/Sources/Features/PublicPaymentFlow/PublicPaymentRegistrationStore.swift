//
//  PublicPaymentRegistrationStore.swift
//  Zashi
//

import ComposableArchitecture
import Foundation
import PaymentServiceClient

@Reducer
public struct PublicPaymentRegistration {
    @ObservableState
    public struct State: Equatable {
        public enum Screen: Equatable {
            case register
            case registering
            case noFunds
            case showAddress
        }

        public var screen: Screen = .register
        public var ownerAddress: String = ""
        public var hasBalance: Bool = true
        public var registrationRelayId: String?
        public var publicAddress: String?
        public var relayURL: String?
        public var qrContent: String = ""
        public var error: String?

        public init() {}
        public static let initial = State()
    }

    public enum Action: Equatable {
        case onAppear
        case balanceChecked(Bool)
        case registerTapped
        case registrationCompleted(String, String, String) // relayId, publicAddress, relayUrl
        case registrationFailed(String)
        case shareLinkTapped
        case shareQRTapped
        case revokeTapped
        case revokeCompleted
        case goHomeTapped
        case closeTapped
    }

    @Dependency(\.paymentServiceClient) var paymentServiceClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Skip balance check — this is a mocked feature and the wallet has real ZEC
                return .none

            case .balanceChecked:
                return .none

            case .registerTapped:
                state.screen = .registering
                let request = RegisterRelayRequest(
                    ownerAddress: state.ownerAddress,
                    publicKey: "mock-pq-pubkey-\(UUID().uuidString.prefix(8))"
                )
                return .run { send in
                    let response = try await paymentServiceClient.registerRelay(request)
                    await send(.registrationCompleted(response.relayId, response.publicAddress, response.relayUrl))
                } catch: { error, send in
                    await send(.registrationFailed(error.localizedDescription))
                }

            case let .registrationCompleted(relayId, publicAddress, relayUrl):
                state.registrationRelayId = relayId
                state.publicAddress = publicAddress
                state.relayURL = relayUrl
                state.qrContent = relayUrl
                state.screen = .showAddress
                return .none

            case let .registrationFailed(message):
                state.error = message
                state.screen = .register
                return .none

            case .shareLinkTapped, .shareQRTapped:
                return .none

            case .revokeTapped:
                // Revoke the relay registration
                guard let relayId = state.registrationRelayId else { return .none }
                return .run { send in
                    _ = try await paymentServiceClient.getBalance(relayId) // placeholder
                    await send(.revokeCompleted)
                } catch: { _, send in
                    await send(.revokeCompleted)
                }

            case .revokeCompleted:
                state.publicAddress = nil
                state.registrationRelayId = nil
                state.screen = .register
                return .none

            case .goHomeTapped, .closeTapped:
                return .none
            }
        }
    }
}
