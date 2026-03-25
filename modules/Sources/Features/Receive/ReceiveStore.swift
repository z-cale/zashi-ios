//
//  ReceiveStore.swift
//  Zashi
//
//  Created by Lukáš Korba on 05.07.2022.
//

import Foundation
import SwiftUI
import ComposableArchitecture
import PaymentServiceClient
import ZcashLightClientKit
import Pasteboard
import Generated
import Utils
import UIComponents
import Models

// Path
import AddressDetails
import PublicPaymentFlow
import RequestZec
import ZecKeyboard

@Reducer
public struct Receive {
    @Reducer
    public enum Path {
        case addressDetails(AddressDetails)
        case publicPaymentRegistration(PublicPaymentRegistration)
        case requestZec(RequestZec)
        case requestZecSummary(RequestZec)
        case zecKeyboard(ZecKeyboard)
    }

    @ObservableState
    public struct State {
        public enum AddressType {
            case ldaAddress
            case tAddress
            case publicDonationAddress
        }

        public var currentFocus = AddressType.ldaAddress
        public var isAddressExplainerPresented = false
        public var isExplainerForShielded = false
        public var isLDAInfoPresented = false
        public var memo = ""
        public var path = StackState<Path.State>()
        @Shared(.inMemory(.selectedWalletAccount)) public var selectedWalletAccount: WalletAccount? = nil
        @Shared(.inMemory(.toast)) public var toast: Toast.Edge? = nil

        // Path
        public var requestZecState = RequestZec.State.initial

        // LDA address — rotates on each screen appearance
        public var ldaAddress: String = Self.generateMockLDA()

        // Public donation — persists across navigation via @Shared
        @Shared(.inMemory(.publicDonationAddress)) public var publicDonationAddress: String = ""
        @Shared(.inMemory(.publicDonationRelayId)) public var publicDonationRelayId: String = ""
        public var publicDonationRelayURL: String? = nil
        public var isPublicDonationRegistered: Bool { !publicDonationAddress.isEmpty }

        public var transparentAddress: String {
            selectedWalletAccount?.transparentAddress ?? L10n.Receive.Error.cantExtractTransparentAddress
        }

        public init() { }

        // Generate a mock Linkable Dynamic Address
        static func generateMockLDA() -> String {
            let chars = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
            let random = (0..<52).map { _ in chars.randomElement()! }
            return "dyn1" + String(random)
        }
    }

    public enum Action {
        case addressDetailsRequest(RedactableString, Bool)
        case backToHomeTapped
        case copyToPastboard(RedactableString)
        case infoTapped(Bool)
        case ldaInfoTapped
        case ldaInfoDismissed
        case onAppear
        case path(StackActionOf<Path>)
        case registerPublicAddressTapped
        case requestTapped(RedactableString, Bool)
        case shareTapped(String)
        case updateCurrentFocus(State.AddressType)
    }

    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.paymentServiceClient) var paymentServiceClient

    public init() { }

    public var body: some Reducer<State, Action> {
        coordinatorReduce()

        Reduce { state, action in
            switch action {
            case .backToHomeTapped:
                return .none

            case .addressDetailsRequest:
                return .none

            case .copyToPastboard(let text):
                pasteboard.setString(text)
                state.$toast.withLock { $0 = .top(L10n.General.copiedToTheClipboard) }
                return .none

            case .requestTapped:
                return .none

            case .updateCurrentFocus(let newFocus):
                state.currentFocus = newFocus
                return .none

            case .path:
                return .none

            case .infoTapped(let shielded):
                state.isAddressExplainerPresented.toggle()
                state.isExplainerForShielded = shielded
                return .none

            case .ldaInfoTapped:
                state.isLDAInfoPresented = true
                return .none

            case .ldaInfoDismissed:
                state.isLDAInfoPresented = false
                return .none

            case .onAppear:
                // Rotate the LDA address on each screen appearance
                state.ldaAddress = State.generateMockLDA()
                state.currentFocus = .ldaAddress
                // Register the new dyn1 address as alias of the stable u1 address
                let alias = state.ldaAddress
                let owner = state.selectedWalletAccount?.unifiedAddress ?? ""
                guard !owner.isEmpty else { return .none }
                return .run { _ in
                    try? await paymentServiceClient.registerAlias(alias, owner)
                }

            case .registerPublicAddressTapped:
                return .none

            case .shareTapped(let text):
                pasteboard.setString(text.redacted)
                state.$toast.withLock { $0 = .top(L10n.General.copiedToTheClipboard) }
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
