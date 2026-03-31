//
//  AddKeystoneHWWalletCoordFlowStore.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-03-19.
//

import SwiftUI
import ComposableArchitecture
import ZcashLightClientKit
import ZcashSDKEnvironment

import AudioServices

// Path
import AddKeystoneHWWallet
import Scan
import WalletBirthday

@Reducer
public struct AddKeystoneHWWalletCoordFlow {
    @Reducer
    public enum Path {
        case accountHWWalletSelection(AddKeystoneHWWallet)
        case estimateBirthdaysDate(WalletBirthday)
        case estimatedBirthday(WalletBirthday)
        case keystoneConnected(AddKeystoneHWWallet)
        case keystoneDeviceReady(AddKeystoneHWWallet)
        case scan(Scan)
        case walletBirthday(WalletBirthday)
    }
    
    @ObservableState
    public struct State {
        public var addKeystoneHWWalletState = AddKeystoneHWWallet.State.initial
        public var birthday: BlockHeight? = nil
        public var isHelpSheetPresented = false
        public var path = StackState<Path.State>()

        public init() { }
    }

    public enum Action: BindableAction {
        case addKeystoneHWWallet(AddKeystoneHWWallet.Action)
        case binding(BindingAction<AddKeystoneHWWalletCoordFlow.State>)
        case closeHelpSheetTapped
        case path(StackActionOf<Path>)
    }

    @Dependency(\.audioServices) var audioServices
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment
    
    public init() { }

    public var body: some Reducer<State, Action> {
        coordinatorReduce()

        BindingReducer()

        Scope(state: \.addKeystoneHWWalletState, action: \.addKeystoneHWWallet) {
            AddKeystoneHWWallet()
        }
        
        Reduce { state, action in
            switch action {
            case .closeHelpSheetTapped:
                state.isHelpSheetPresented = false
                return .none
            default: return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
