//
//  AddKeystoneHWWalletCoordFlowCoordinator.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-03-19.
//

import ComposableArchitecture
import Generated
import AudioServices

// Path
import AddKeystoneHWWallet
import Scan
import WalletBirthday

extension AddKeystoneHWWalletCoordFlow {
    public func coordinatorReduce() -> Reduce<AddKeystoneHWWalletCoordFlow.State, AddKeystoneHWWalletCoordFlow.Action> {
        Reduce { state, action in
            switch action {

                // MARK: - Scan

            case .path(.element(id: _, action: .scan(.foundAccounts(let account)))):
                var addKeystoneHWWalletState = AddKeystoneHWWallet.State.initial
                addKeystoneHWWalletState.zcashAccounts = account
                state.path.append(.accountHWWalletSelection(addKeystoneHWWalletState))
                audioServices.systemSoundVibrate()
                return .none

            case .path(.element(id: _, action: .scan(.cancelTapped))):
                let _ = state.path.popLast()
                return .none

                // MARK: - Account Selection -> Birthday

            case .path(.element(id: _, action: .accountHWWalletSelection(.unlockTapped))):
                state.path.append(.walletBirthday(WalletBirthday.State.initial))
                return .none

                // MARK: - Wallet Birthday

            case .path(.element(id: _, action: .walletBirthday(.helpSheetRequested))):
                state.isHelpSheetPresented.toggle()
                return .none

            case .path(.element(id: _, action: .walletBirthday(.estimateHeightTapped))):
                state.path.append(.estimateBirthdaysDate(WalletBirthday.State.initial))
                return .none

            case .path(.element(id: _, action: .walletBirthday(.restoreTapped))):
                for element in state.path {
                    if case .walletBirthday(let walletBirthdayState) = element {
                        state.birthday = walletBirthdayState.estimatedHeight
                    }
                }
                return performKeystoneImport(&state)

                // MARK: - Estimate Birthday Date

            case .path(.element(id: _, action: .estimateBirthdaysDate(.helpSheetRequested))):
                state.isHelpSheetPresented.toggle()
                return .none

            case .path(.element(id: _, action: .estimateBirthdaysDate(.estimateHeightReady))):
                for element in state.path {
                    if case .estimateBirthdaysDate(let estimateState) = element {
                        state.path.append(.estimatedBirthday(estimateState))
                    }
                }
                return .none

                // MARK: - Estimated Birthday Height

            case .path(.element(id: _, action: .estimatedBirthday(.helpSheetRequested))):
                state.isHelpSheetPresented.toggle()
                return .none

            case .path(.element(id: _, action: .estimatedBirthday(.restoreTapped))):
                for element in state.path {
                    if case .estimatedBirthday(let estimatedBirthdayState) = element {
                        state.birthday = estimatedBirthdayState.estimatedHeight
                    }
                }
                return performKeystoneImport(&state)

                // MARK: - Self

            case .addKeystoneHWWallet(.readyToScanTapped):
                var scanState = Scan.State.initial
                scanState.checkers = [.keystoneScanChecker]
                scanState.instructions = String(localizable: .keystoneScanInfo)
                scanState.forceLibraryToHide = true
                state.path.append(.scan(scanState))
                return .none

            case .helpSheetRequested:
                state.isHelpSheetPresented.toggle()
                return .none

            default: return .none
            }
        }
    }

    private func performKeystoneImport(_ state: inout AddKeystoneHWWalletCoordFlow.State) -> Effect<AddKeystoneHWWalletCoordFlow.Action> {
        let birthday = state.birthday
        // Find the accountHWWalletSelection in the path and send importAccount
        for (id, element) in zip(state.path.ids, state.path) {
            if case .accountHWWalletSelection = element {
                return .send(.path(.element(id: id, action: .accountHWWalletSelection(.importAccount(birthday)))))
            }
        }
        return .none
    }
}
