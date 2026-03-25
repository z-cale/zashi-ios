//
//  ReceiveCoordinator.swift
//  modules
//
//  Created by Lukáš Korba on 2025-03-17.
//

import ComposableArchitecture
import Generated

import AddressDetails
import PublicPaymentFlow
import RequestZec
import ZecKeyboard

extension Receive {
    public func coordinatorReduce() -> Reduce<Receive.State, Receive.Action> {
        Reduce { state, action in
            switch action {
                // MARK: Receive

            case let .addressDetailsRequest(address, maxPrivacy):
                var addressDetailsState = AddressDetails.State.initial
                addressDetailsState.address = address
                addressDetailsState.maxPrivacy = maxPrivacy
                if maxPrivacy {
                    addressDetailsState.addressTitle = "Linkable Dynamic Address"
                } else {
                    if state.selectedWalletAccount?.vendor == .keystone {
                        addressDetailsState.addressTitle = L10n.Accounts.Keystone.transparentAddress
                    } else {
                        addressDetailsState.addressTitle = L10n.Accounts.Zashi.transparentAddress
                    }
                }
                state.path.append(.addressDetails(addressDetailsState))
                return .none

            case .registerPublicAddressTapped:
                var registrationState = PublicPaymentRegistration.State()
                registrationState.ownerAddress = state.selectedWalletAccount?.unifiedAddress ?? state.ldaAddress
                state.path.append(.publicPaymentRegistration(registrationState))
                return .none

            case let .path(.element(id: _, action: .publicPaymentRegistration(.registrationCompleted(relayId, publicAddress, relayUrl)))):
                // Update receive state
                state.publicDonationAddress = publicAddress
                state.publicDonationRelayId = relayId
                state.publicDonationRelayURL = relayUrl
                // Pop registration and show the address details QR view
                state.path.removeAll()
                var addressDetailsState = AddressDetails.State.initial
                addressDetailsState.address = publicAddress.redacted
                addressDetailsState.maxPrivacy = false
                addressDetailsState.addressTitle = "Public Donation Address"
                state.path.append(.addressDetails(addressDetailsState))
                return .none

            case .path(.element(id: _, action: .publicPaymentRegistration(.closeTapped))):
                state.path.removeAll()
                return .none

            case .path(.element(id: _, action: .publicPaymentRegistration(.goHomeTapped))):
                state.path.removeAll()
                return .none

            case let .requestTapped(address, maxPrivacy):
                state.path.append(.zecKeyboard(ZecKeyboard.State.initial))
                state.memo = ""
                state.requestZecState = RequestZec.State.initial
                state.requestZecState.address = address
                state.requestZecState.maxPrivacy = maxPrivacy
                return .none

                // MARK: - Request Zec

            case .path(.element(id: _, action: .requestZec(.requestTapped))):
                for element in state.path {
                    if case .requestZec(let requestZecState) = element {
                        state.requestZecState.memoState = requestZecState.memoState
                        break
                    }
                }
                state.path.append(.requestZecSummary(state.requestZecState))
                return .none

            case .path(.element(id: _, action: .requestZecSummary(.cancelRequestTapped))):
                state.path.removeAll()
                return .none

                // MARK: - Zec Keyboard

            case .path(.element(id: _, action: .zecKeyboard(.nextTapped))):
                for element in state.path {
                    if case .zecKeyboard(let zecKeyboardState) = element {
                        state.requestZecState.memoState.text = state.memo
                        state.requestZecState.requestedZec = zecKeyboardState.amount.roundToAvoidDustSpend()
                        break
                    }
                }
                state.path.append(.requestZec(state.requestZecState))
                return .none

            default: return .none
            }
        }
    }
}
