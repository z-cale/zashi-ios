//
//  RootDestination.swift
//  Zashi
//
//  Created by Lukáš Korba on 01.12.2022.
//

import Foundation
import ComposableArchitecture
import ZcashLightClientKit
import Deeplink
import DerivationTool
import Generated
import PaymentLinkFlow

import SwiftUI

/// In this file is a collection of helpers that control all state and action related operations
/// for the `Root` with a connection to the UI navigation.
extension Root {
    public struct DestinationState {
        public enum Destination {
            case deeplinkWarning
            case notEnoughFreeSpace
            case onboarding
            case osStatusError
            case startup
            case home
            case welcome
        }
        
        public var internalDestination: Destination = .welcome
        public var preNotEnoughFreeSpaceDestination: Destination?
        public var previousDestination: Destination?

        public var destination: Destination {
            get { internalDestination }
            set {
                previousDestination = internalDestination
                internalDestination = newValue
            }
        }
    }
    
    public enum DestinationAction {
        case deeplink(URL)
        case deeplinkHome
        case deeplinkSend(Zatoshi, String, String)
        case deeplinkClaimPayment(String, String)
        case deeplinkFailed(URL, ZcashError)
        case updateDestination(Root.DestinationState.Destination)
        case serverSwitch
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func destinationReduce() -> Reduce<Root.State, Root.Action> {
        Reduce { state, action in
            switch action {
            case let .destination(.updateDestination(destination)):
                guard (state.destinationState.destination != .deeplinkWarning)
                        || (state.destinationState.destination == .deeplinkWarning && destination == .home) else {
                    return .none
                }
                state.destinationState.destination = destination
                return .none

            case .destination(.deeplink(let url)):
                // Check for payment link URLs
                // Supports both:
                //   zcashpay://claim?id=...&amount=...  (custom scheme, works on simulator)
                //   https://pay.withzcash.com:65536/payment/v1#id=...  (production format)
                if url.scheme == "zcashpay" {
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let linkId = components?.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
                    let amount = components?.queryItems?.first(where: { $0.name == "amount" })?.value ?? ""
                    if !linkId.isEmpty {
                        return .send(.destination(.deeplinkClaimPayment(linkId, amount)))
                    }
                }
                if let fragment = url.fragment,
                   url.host == "pay.withzcash.com" || url.absoluteString.contains("pay.withzcash.com") {
                    let params = Self.parseFragment(fragment)
                    if let linkId = params["id"] {
                        let amount = params["amount"] ?? ""
                        return .send(.destination(.deeplinkClaimPayment(linkId, amount)))
                    }
                }

                if let _ = uriParser.checkRP(url.absoluteString, zcashSDKEnvironment.network.networkType) {
                    // The deeplink is some zip321, we ignore it and let users know in a warning screen
                    return .send(.destination(.updateDestination(.deeplinkWarning)))
                }
                return .none

            case .destination(.deeplinkHome):
                return .none

            case let .destination(.deeplinkClaimPayment(linkId, amount)):
                var claimState = ClaimPayment.State(linkId: linkId, amount: amount)
                claimState.recipientAddress = state.selectedWalletAccount?.unifiedAddress ?? "demo-recipient"
                state.claimPaymentState = claimState
                state.path = .claimPayment
                return .none

            case .destination(.deeplinkSend):
                return .none

            case let .destination(.deeplinkFailed(url, error)):
                state.alert = AlertState.failedToProcessDeeplink(url, error)
                return .none

            case .destination(.serverSwitch):
                state.serverSetupViewBinding = true
                return .none

            case .splashRemovalRequested:
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(0.01))
                    await send(.splashFinished)
                }
            
            case .splashFinished:
                state.splashAppeared = true
                state.$lastAuthenticationTimestamp.withLock { $0 = Int(Date().timeIntervalSince1970) }
                return .none

            case .flexaOnTransactionRequest(let transaction):
                guard let transaction else {
                    return .none
                }
                guard let account = state.selectedWalletAccount, let zip32AccountIndex = account.zip32AccountIndex else {
                    return .none
                }
                flexaHandler.clearTransactionRequest()
                return .run { send in
                    do {
                        if await !localAuthentication.authenticate() {
                            return
                        }

                        // get a proposal
                        let recipient = try Recipient(transaction.address, network: zcashSDKEnvironment.network.networkType)
                        let proposal = try await sdkSynchronizer.proposeTransfer(account.id, recipient, transaction.amount, nil)

                        // make the actual send
                        let storedWallet = try walletStorage.exportWallet()
                        let seedBytes = try mnemonic.toSeed(storedWallet.seedPhrase.value())
                        let network = zcashSDKEnvironment.network.networkType
                        let spendingKey = try derivationTool.deriveSpendingKey(seedBytes, zip32AccountIndex, network)
                        
                        let result = try await sdkSynchronizer.createProposedTransactions(proposal, spendingKey)
                        
                        switch result {
                        case .partial:
                            await send(.flexaTransactionFailed(L10n.Partners.Flexa.transactionFailedMessage))
                        case .success(let txIds), .grpcFailure(let txIds), .failure(let txIds, _, _):
                            if let txId = txIds.last, try await sdkSynchronizer.txIdExists(txId) {
                                flexaHandler.transactionSent(transaction.commerceSessionId, txId)
                            }
                        }
                    } catch {
                        await send(.flexaTransactionFailed(error.localizedDescription))
                    }
                }
                
            case .flexaTransactionFailed(let message):
                flexaHandler.flexaAlert(L10n.Partners.Flexa.transactionFailedTitle, message)
                return .none

            default:
                return .none
            }
        }
    }
}

private extension Root {
    func process(
        url: URL,
        deeplink: DeeplinkClient,
        derivationTool: DerivationToolClient
    ) async throws -> Root.Action {
        @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment
        let deeplink = try deeplink.resolveDeeplinkURL(url, zcashSDKEnvironment.network.networkType, derivationTool)
        
        switch deeplink {
        case .home:
            return .destination(.deeplinkHome)
        case let .send(amount, address, memo):
            return .destination(.deeplinkSend(Zatoshi(Int64(amount)), address, memo))
        }
    }
}

// MARK: - URL Fragment Parser

extension Root {
    static func parseFragment(_ fragment: String) -> [String: String] {
        var params: [String: String] = [:]
        for component in fragment.split(separator: "&") {
            let pair = component.split(separator: "=", maxSplits: 1)
            if pair.count == 2 {
                let key = String(pair[0])
                let value = String(pair[1]).removingPercentEncoding ?? String(pair[1])
                params[key] = value
            }
        }
        return params
    }
}

extension StoreOf<Root> {
    public func goToDestination(_ destination: Root.DestinationState.Destination) {
        send(.destination(.updateDestination(destination)))
    }
    
    public func goToDeeplink(_ deeplink: URL) {
        send(.destination(.deeplink(deeplink)))
    }
}

// MARK: Placeholders

extension Root.DestinationState {
    public static var initial: Self {
        .init()
    }
}
