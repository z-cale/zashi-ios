//
//  RequestZecStore.swift
//  Zashi
//
//  Created by Lukáš Korba on 09-20-2024.
//

import Foundation
import SwiftUI
import ComposableArchitecture
import ZcashLightClientKit
import Pasteboard
import Generated
import Utils
import UIComponents
import ZcashSDKEnvironment
import ZcashPaymentURI
import Models
import URIParser

@Reducer
public struct RequestZec {
    @ObservableState
    public struct State: Equatable {
        public var cancelId = UUID()

        public var address: RedactableString = .empty
        public var encryptedOutput: String?
        public var encryptedOutputToBeShared: String?
        public var isQRCodeEnlarged = false
        public var maxPrivacy = false
        public var memoState: MessageEditor.State = .initial
        public var requestedZec: Zatoshi = .zero
        @Shared(.inMemory(.selectedWalletAccount)) public var selectedWalletAccount: WalletAccount? = nil
        public var storedEnlargedQR: CGImage?
        public var storedQR: CGImage?

        public init() {}
    }

    public enum Action: BindableAction, Equatable {
        case binding(BindingAction<RequestZec.State>)
        case cancelRequestTapped
        case generateEnlargedQRCode
        case generateQRCode(Bool)
        case memo(MessageEditor.Action)
        case onAppear
        case onDisappear
        case qrCodeTapped
        case rememberEnlargedQR(CGImage?)
        case rememberQR(CGImage?)
        case requestTapped
        case shareFinished
        case shareQR
    }
    
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment
    
    public init() { }

    public var body: some Reducer<State, Action> {
        BindingReducer()
        
        Scope(state: \.memoState, action: \.memo) {
            MessageEditor()
        }
        
        Reduce { state, action in
            switch action {
            case .onAppear:
                // __LD TESTED
                state.memoState.charLimit = zcashSDKEnvironment.memoCharLimit
                state.encryptedOutput = nil
                return .send(.generateEnlargedQRCode)

            case .onDisappear:
                // __LD2 TESTing
                return .cancel(id: state.cancelId)

            case .binding:
                return .none
                
            case .cancelRequestTapped:
                return .none
                
            case .memo:
                return .none
            
            case .requestTapped:
                return .none

            case .qrCodeTapped:
                state.isQRCodeEnlarged = true
                guard state.storedEnlargedQR != nil else {
                    return .send(.generateEnlargedQRCode)
                }
                return .none
                
            case let .rememberQR(image):
                state.storedQR = image
                return .none
                
            case let .rememberEnlargedQR(image):
                state.storedEnlargedQR = image
                return .none

            case .generateQRCode:
                // Fallback for mock addresses (dyn1, pub1) that aren't recognized by ZIP-321 parser
                if state.address.data.hasPrefix("dyn1") || state.address.data.hasPrefix("pub1") {
                    let amount = state.requestedZec.decimalString()
                    var uri = "zcash:\(state.address.data)?amount=\(amount)"
                    if !state.memoState.text.isEmpty,
                       let encoded = state.memoState.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        uri += "&memo=\(encoded)"
                    }
                    let encryptedOutput = uri
                    state.encryptedOutput = encryptedOutput
                    return .publisher {
                        QRCodeGenerator.generate(
                            from: encryptedOutput,
                            maxPrivacy: state.maxPrivacy,
                            vendor: .zashi,
                            color: Asset.Colors.primary.systemColor
                        )
                        .map(Action.rememberQR)
                    }
                    .cancellable(id: state.cancelId)
                }

                if let recipient = RecipientAddress(value: state.address.data, context: ParserContext.from(networkType: zcashSDKEnvironment.network.networkType)) {
                    do {
                        let payment = try Payment(
                            recipientAddress: recipient,
                            amount: try Amount(value: state.requestedZec.decimalValue.doubleValue),
                            memo: state.memoState.text.isEmpty ? nil : try MemoBytes(utf8String: state.memoState.text),
                            label: nil,
                            message: nil,
                            otherParams: nil
                        )

                        let encryptedOutput = ZIP321.request(payment, formattingOptions: .useEmptyParamIndex(omitAddressLabel: true))
                        state.encryptedOutput = encryptedOutput
                        return .publisher {
                            QRCodeGenerator.generate(
                                from: encryptedOutput,
                                maxPrivacy: state.maxPrivacy,
                                vendor: .zashi,
                                color: Asset.Colors.primary.systemColor
                            )
                            .map(Action.rememberQR)
                        }
                        .cancellable(id: state.cancelId)
                    } catch {
                        return .none
                    }
                }
                return .none
                
            case .generateEnlargedQRCode:
                // Fallback for mock addresses (dyn1, pub1)
                if state.address.data.hasPrefix("dyn1") || state.address.data.hasPrefix("pub1") {
                    let amount = state.requestedZec.decimalString()
                    var uri = "zcash:\(state.address.data)?amount=\(amount)"
                    if !state.memoState.text.isEmpty,
                       let encoded = state.memoState.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        uri += "&memo=\(encoded)"
                    }
                    let encryptedOutput = uri
                    state.encryptedOutput = encryptedOutput
                    return .publisher {
                        QRCodeGenerator.generate(
                            from: encryptedOutput,
                            maxPrivacy: state.maxPrivacy,
                            vendor: .zashi,
                            color: .black
                        )
                        .map(Action.rememberEnlargedQR)
                    }
                    .cancellable(id: state.cancelId)
                }

                if let recipient = RecipientAddress(value: state.address.data, context: ParserContext.from(networkType: zcashSDKEnvironment.network.networkType)) {
                    do {
                        let payment = try Payment(
                            recipientAddress: recipient,
                            amount: try Amount(value: state.requestedZec.decimalValue.doubleValue),
                            memo: state.memoState.text.isEmpty ? nil : try MemoBytes(utf8String: state.memoState.text),
                            label: nil,
                            message: nil,
                            otherParams: nil
                        )

                        let encryptedOutput = ZIP321.request(payment, formattingOptions: .useEmptyParamIndex(omitAddressLabel: true))
                        state.encryptedOutput = encryptedOutput
                        return .publisher {
                            QRCodeGenerator.generate(
                                from: encryptedOutput,
                                maxPrivacy: state.maxPrivacy,
                                vendor: .zashi,
                                color: .black
                            )
                            .map(Action.rememberEnlargedQR)
                        }
                        .cancellable(id: state.cancelId)
                    } catch {
                        return .none
                    }
                }
                return .none

            case .shareFinished:
                state.encryptedOutputToBeShared = nil
                return .none
                
            case .shareQR:
                state.encryptedOutputToBeShared = state.encryptedOutput
                return .none
            }
        }
    }
}
