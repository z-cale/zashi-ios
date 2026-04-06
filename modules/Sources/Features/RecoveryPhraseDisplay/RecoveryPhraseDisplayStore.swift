//
//  RecoveryPhraseDisplayStore.swift
//  Zashi
//
//  Created by Francisco Gindre on 10/26/21.
//

import Foundation
import ComposableArchitecture
import Models
import WalletStorage
import ZcashLightClientKit
import Utils
import Generated
import NumberFormatter
import LocalAuthenticationHandler

@Reducer
public struct RecoveryPhraseDisplay {
    @ObservableState
    public struct State: Equatable {
        @Presents public var alert: AlertState<Action>?
        public var birthday: Birthday?
        public var birthdayValue: String?
        public var isBirthdayHintVisible = false
        public var isHelpSheetPresented = false
        public var isRecoveryPhraseHidden = true
        public var isWalletBackup = false
        public var phrase: RecoveryPhrase?

        public enum LearnMoreOptions: CaseIterable {
            case control
            case keep
            case store
            case height

            public func title() -> String {
                switch self {
                case .control: return String(localizable: .recoveryPhraseDisplayWarningControlTitle)
                case .keep: return String(localizable: .recoveryPhraseDisplayWarningKeepTitle)
                case .store: return String(localizable: .recoveryPhraseDisplayWarningStoreTitle)
                case .height: return String(localizable: .recoveryPhraseDisplayWarningHeightTitle)
                }
            }

            public func subtitle() -> String {
                switch self {
                case .control: return String(localizable: .recoveryPhraseDisplayWarningControlInfo)
                case .keep: return String(localizable: .recoveryPhraseDisplayWarningKeepInfo)
                case .store: return String(localizable: .recoveryPhraseDisplayWarningStoreInfo)
                case .height: return String(localizable: .recoveryPhraseDisplayWarningHeightInfo)
                }
            }

            public func icon() -> ImageAsset {
                switch self {
                case .control: return Asset.Assets.Icons.cryptocurrency
                case .keep: return Asset.Assets.Icons.emptyShield
                case .store: return Asset.Assets.Icons.archive
                case .height: return Asset.Assets.Icons.calendar
                }
            }
        }
        
        public init(
            birthday: Birthday? = nil,
            birthdayValue: String? = nil,
            phrase: RecoveryPhrase? = nil
        ) {
            self.birthday = birthday
            self.birthdayValue = birthdayValue
            self.phrase = phrase
        }
    }
    
    public enum Action: BindableAction, Equatable {
        case binding(BindingAction<RecoveryPhraseDisplay.State>)
        case alert(PresentationAction<Action>)
        case finishedTapped
        case helpSheetRequested
        case hideEverything
        case onAppear
        case recoveryPhraseTapped
        case recoveryPhraseUnhideRequested
        case remindMeLaterTapped
        case securityWarningNextTapped
        case seedSavedTapped
        case tooltipTapped
    }
    
    @Dependency(\.localAuthentication) var localAuthentication
    @Dependency(\.numberFormatter) var numberFormatter
    @Dependency(\.walletStorage) var walletStorage

    public init() {}
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
        
        Reduce { state, action in
            switch action {
            case .onAppear:
                // __LD TESTED
                state.isRecoveryPhraseHidden = true
                do {
                    let storedWallet = try walletStorage.exportWallet()
                    state.birthday = storedWallet.birthday
                    
                    if let value = state.birthday?.value() {
                        state.birthdayValue = String(value)
                    }
                    
                    let seedWords = storedWallet.seedPhrase.value().split(separator: " ").map { RedactableString(String($0)) }
                    state.phrase = RecoveryPhrase(words: seedWords)
                } catch {
                    state.alert = AlertState.storedWalletFailure(error.toZcashError())
                }
                
                return .none
                
            case .hideEverything:
                state.isRecoveryPhraseHidden = true
                return .none

            case .alert(.presented(let action)):
                return .send(action)

            case .alert(.dismiss):
                state.alert = nil
                return .none
                
            case .binding:
                return .none
                
            case .finishedTapped:
                return .none
                
            case .tooltipTapped:
                state.isBirthdayHintVisible.toggle()
                return .none
                
            case .recoveryPhraseUnhideRequested:
                return .run { send in
                    guard await localAuthentication.authenticate() else {
                        return
                    }
                    
                    await send(.recoveryPhraseTapped)
                }

            case .recoveryPhraseTapped:
                state.isRecoveryPhraseHidden.toggle()
                return .none
                
            case .securityWarningNextTapped:
                return .none
                
            case .helpSheetRequested:
                state.isHelpSheetPresented.toggle()
                return .none
                
            case .seedSavedTapped:
                return .none
                
            case .remindMeLaterTapped:
                return .none
            }
        }
    }
}

// MARK: Alerts

extension AlertState where Action == RecoveryPhraseDisplay.Action {
    public static func storedWalletFailure(_ error: ZcashError) -> AlertState {
        AlertState {
            TextState(String(localizable: .recoveryPhraseDisplayAlertFailedTitle))
        } message: {
            TextState(String(localizable: .recoveryPhraseDisplayAlertFailedMessage(error.detailedMessage)))
        }
    }
}
