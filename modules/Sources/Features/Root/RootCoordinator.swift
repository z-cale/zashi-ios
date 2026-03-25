//
//  RootCoordinator.swift
//  Zashi
//
//  Created by Lukáš Korba on 07.03.2025.
//

import ComposableArchitecture
import PaymentServiceClient
import ZcashLightClientKit

extension Root {
    public func coordinatorReduce() -> Reduce<Root.State, Root.Action> {
        Reduce { state, action in
            switch action {
                
                // MARK: - Returns to Home

            case .settings(.backToHomeTapped),
                .receive(.backToHomeTapped),
                .walletBackupCoordFlow(.backToHomeTapped),
                .torSetup(.backToHomeTapped),
                .currencyConversionSetup(.backToHomeTapped),
                .backToHomeFromServerSwitchTapped,
                .sendCoordFlow(.sendForm(.dismissRequired)):
                state.path = nil
                return refreshMockBalance(state: &state)

            case .home(.refreshMockBalance):
                return refreshMockBalance(state: &state)
                
                // MARK: - Accounts

            case .home(.walletAccountTapped(let walletAccount)):
                guard state.selectedWalletAccount != walletAccount else {
                    return .none
                }
                state.$selectedWalletAccount.withLock { $0 = walletAccount }
                state.homeState.transactionListState.isInvalidated = true
                state.autoUpdateSwapCandidates.removeAll()
                return .merge(
                    .send(.home(.smartBanner(.walletAccountChanged))),
                    .send(.home(.walletBalances(.updateBalances))),
                    .send(.loadContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    ),
                    .send(.fetchTransactionsForTheSelectedAccount)
                )

                // MARK: - Add Keystone HW Wallet Coord Flow

            case .addKeystoneHWWalletCoordFlow(.path(.element(id: _, action: .accountHWWalletSelection(.forgetThisDeviceTapped)))):
                state.path = nil
                return .none

            case .addKeystoneHWWalletCoordFlow(.path(.element(id: _, action: .accountHWWalletSelection(.accountImportSucceeded)))):
                state.path = nil
                state.autoUpdateSwapCandidates.removeAll()
                return .merge(
                    .send(.loadContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    ),
                    .send(.fetchTransactionsForTheSelectedAccount)
                )
                
            case .addKeystoneHWWalletCoordFlow(.addKeystoneHWWallet(.backToHomeTapped)):
                state.path = nil
                return .none

                // MARK: - Add Keystone HW Wallet from Settings

            case .settings(.path(.element(id: _, action: .accountHWWalletSelection(.accountImportSucceeded)))):
                state.path = nil
                state.autoUpdateSwapCandidates.removeAll()
                return .merge(
                    .send(.loadContacts),
                    .concatenate(
                        .send(.resolveMetadataEncryptionKeys),
                        .send(.loadUserMetadata)
                    ),
                    .send(.fetchTransactionsForTheSelectedAccount)
                )
                
                // MARK: - Flexa

            case .flexaOpenRequest:
                flexaHandler.open()
                return .publisher {
                    flexaHandler.onTransactionRequest()
                        .map(Root.Action.flexaOnTransactionRequest)
                        .receive(on: mainQueue)
                }
                .cancellable(id: CancelFlexaId, cancelInFlight: true)
                
                // MARK: - Currency Conversion Setup
                
            case .currencyConversionSetup(.skipTapped), .currencyConversionSetup(.enableTapped):
                state.path = nil
                state.homeState.isRateEducationEnabled = false
                return .send(.home(.smartBanner(.closeAndCleanupBanner)))

                // MARK: - Home

            case .home(.settingsTapped):
                state.settingsState = .initial
                state.path = .settings
                return .none
                
            case .home(.receiveTapped):
                state.receiveState = .initial
                state.path = .receive
                return .none

            case .home(.sendTapped):
                state.sendCoordFlowState = .initial
                state.path = .sendCoordFlow
                exchangeRate.refreshExchangeRateUSD()
                return .none

            case .home(.scanTapped):
                state.scanCoordFlowState = .initial
                state.path = .scanCoordFlow
                return .none

            case .home(.flexaTapped), .settings(.payWithFlexaTapped):
                return .send(.flexaOpenRequest)
                
            case .home(.addKeystoneHWWalletTapped):
                state.addKeystoneHWWalletCoordFlowState = .initial
                state.path = .addKeystoneHWWalletCoordFlow
                return .none
                
            case .home(.swapWithNearTapped):
                state.swapAndPayCoordFlowState = .initial
                state.swapAndPayCoordFlowState.isSwapExperience = true
                state.swapAndPayCoordFlowState.swapAndPayState.isSwapExperienceEnabled = true
                state.path = .swapAndPayCoordFlow
                // whether to start on SwapToZEC or fromZEC
                return .send(.swapAndPayCoordFlow(.swapAndPay(.enableSwapToZecExperience)))

            case .home(.payWithNearTapped):
                state.swapAndPayCoordFlowState = .initial
                state.swapAndPayCoordFlowState.isSwapExperience = false
                state.swapAndPayCoordFlowState.swapAndPayState.isSwapExperienceEnabled = false
                state.path = .swapAndPayCoordFlow
                return .none

            case .home(.transactionList(.transactionTapped(let txId))):
                state.transactionsCoordFlowState = .initial
                state.transactionsCoordFlowState.transactionToOpen = txId
                if let index = state.transactions.index(id: txId) {
                    state.transactionsCoordFlowState.transactionDetailsState.transaction = state.transactions[index]
                }
                state.path = .transactionsCoordFlow
                return .none

            case .home(.seeAllTransactionsTapped):
                state.transactionsCoordFlowState = .initial
                state.path = .transactionsCoordFlow
                return .none
                
            case .home(.currencyConversionSetupTapped):
                state.currencyConversionSetupState = .initial
                state.path = .currencyConversionSetup
                return .none

            case .home(.torSetupTapped(let settingsView)):
                state.torSetupState = .initial
                state.torSetupState.isSettingsView = settingsView
                state.path = .torSetup
                return .none

            case .home(.smartBanner(.walletBackupTapped)):
                state.walletBackupCoordFlowState = .initial
                state.path = .walletBackup
                return .none
                
            case .home(.smartBanner(.serverSwitchRequested)):
                state.serverSetupState = .initial
                state.path = .serverSwitch
                return .none

                // MARK: - Tachyon Demo

            case .home(.fundWalletTapped):
                let walletAddress = state.selectedWalletAccount?.privateUnifiedAddress ?? "demo-wallet"
                return .run { send in
                    @Dependency(\.paymentServiceClient) var paymentServiceClient
                    let response = try await paymentServiceClient.getBalance(walletAddress)
                    // Credit 100 ZEC
                    _ = try await paymentServiceClient.transfer(
                        TransferRequest(
                            senderAddress: "faucet",
                            recipientAddress: walletAddress,
                            amount: "100.0"
                        )
                    )
                    let updated = try await paymentServiceClient.getBalance(walletAddress)
                    await send(.home(.fundWalletCompleted(updated.balance)))
                } catch: { error, send in
                    await send(.home(.fundWalletCompleted("error: \(error.localizedDescription)")))
                }

            case let .home(.fundWalletCompleted(balance)):
                state.$mockBalance.withLock { $0 = balance }
                state.$toast.withLock { $0 = .top("Funded! Mock balance: \(balance) ZEC") }
                return .none

            case .home(.tachyonDemoTapped):
                state.homeState.moreRequest = false
                state.tachyonDemoState = .initial
                state.path = .tachyonDemo
                return .none

            case .claimPayment(.closeTapped), .claimPayment(.viewTransactionTapped):
                state.path = nil
                return refreshMockBalance(state: &state)

            case .tachyonDemo(.dismissFlow):
                state.path = nil
                return .none

                // MARK: - Voting

            case .home(.votingBannerTapped):
                guard let account = state.selectedWalletAccount else { return .none }
                state.homeState.moreRequest = false
                state.votingState = .initial
                state.votingState.isKeystoneUser = state.homeState.isKeystoneAccountActive
                state.votingState.walletId = account.id.id.map { String(format: "%02x", $0) }.joined()
                state.path = .voting
                return .none

            case .voting(.dismissFlow):
                state.path = nil
                return .none

                // MARK: - Keystone

            case .sendCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.rejectTapped)))),
                    .signWithKeystoneCoordFlow(.sendConfirmation(.rejectTapped)),
                    .swapAndPayCoordFlow(.path(.element(id: _, action: .confirmWithKeystone(.rejectTapped)))):
                state.path = nil
                return .none

            case .signWithKeystoneRequested:
                state.signWithKeystoneCoordFlowBinding = true
                return .send(.signWithKeystoneCoordFlow(.sendConfirmation(.resolvePCZT)))
                
                // MARK: - Request Zec

            case .requestZecCoordFlow(.path(.element(id: _, action: .requestZecSummary(.cancelRequestTapped)))):
                state.path = nil
                return .none

                // MARK: - Reset Zashi

            case .settings(.path(.element(id: _, action: .resetZashi(.deleteTapped(let areMetadataPreserved))))):
                return .send(.initialization(.resetZashiRequest(areMetadataPreserved)))

                // MARK: - Restore Wallet Coord Flow from Onboarding

            case .onboarding(.path(.element(id: _, action: .restoreInfo(.gotItTapped)))):
                var leavesScreenOpen = false
                for element in state.onboardingState.path {
                    if case .restoreInfo(let restoreInfoState) = element {
                        leavesScreenOpen = restoreInfoState.isAcknowledged
                    }
                }
                userDefaults.setValue(leavesScreenOpen, Constants.udLeavesScreenOpen)
                state.isRestoringWallet = true
                userDefaults.setValue(true, Constants.udIsRestoringWallet)
                state.$walletStatus.withLock { $0 = .restoring }
                return .concatenate(
                    .send(.initialization(.initializeSDK(.restoreWallet))),
                    .send(.initialization(.checkBackupPhraseValidation)),
                    .send(.batteryStateChanged(nil))
                )

                // MARK: - Scan Coord Flow
                
            case .scanCoordFlow(.scan(.cancelTapped)):
                state.path = nil
                return .none
                
            case .scanCoordFlow(.path(.element(id: _, action: .sendForm(.dismissRequired)))):
                state.path = nil
                return .none

            case .scanCoordFlow(.path(.element(id: _, action: .transactionDetails(.closeDetailTapped)))):
                state.path = nil
                return .none

            case .scanCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .scanCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .scanCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.path = nil
                return .none

                // MARK: - Self

            case .sendAgainRequested(let transactionState):
                state.sendCoordFlowState = .initial
                state.path = .sendCoordFlow
                state.sendCoordFlowState.sendFormState.memoState.text = state.transactionMemos[transactionState.id]?.first ?? ""
                return .merge(
                    .send(.sendCoordFlow(.sendForm(.zecAmountUpdated(transactionState.amountWithoutFee.decimalString().redacted)))),
                    .send(.sendCoordFlow(.sendForm(.addressUpdated(transactionState.address.redacted))))
                )
                
            case .deeplinkWarning(.rescanInZashi):
                state = .initial
                state.splashAppeared = true
                return .merge(
                    .send(.destination(.updateDestination(.home))),
                    .send(.home(.scanTapped))
                )

                // MARK: - Send Coord Flow
                
            case .sendCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .sendCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .sendCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.path = nil
                return .none

            case .sendCoordFlow(.path(.element(id: _, action: .transactionDetails(.closeDetailTapped)))):
                state.path = nil
                return .none

                // MARK: - Sign with Keystone Coord Flow

            case .signWithKeystoneCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .signWithKeystoneCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .signWithKeystoneCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.signWithKeystoneCoordFlowBinding = false
                return .none

            case .signWithKeystoneCoordFlow(.path(.element(id: _, action: .transactionDetails(.closeDetailTapped)))):
                state.signWithKeystoneCoordFlowBinding = false
                return .none

                // MARK: - Tor Setup
                
            case .torSetup(.disableTapped), .torSetup(.enableTapped):
                state.path = nil
                return .send(.home(.smartBanner(.closeAndCleanupBanner)))

                // MARK: - Swap and Pay Coord Flow

            case .swapAndPayCoordFlow(.path(.element(id: _, action: .swapToZecSummary(.sentTheFundsButtonTapped)))):
                state.path = nil
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .swapAndPayCoordFlow(.customBackRequired):
                state.path = nil
                return .none

            case .swapAndPayCoordFlow(.swapAndPay(.customBackRequired)):
                state.path = nil
                return .none

            case .swapAndPayCoordFlow(.path(.element(id: _, action: .swapAndPayOptInForced(.customBackRequired)))):
                state.path = nil
                return .none

            case .swapAndPayCoordFlow(.swapAndPay(.cancelPaymentTapped)):
                state.path = nil
                return .none
                
            case .swapAndPayCoordFlow(.path(.element(id: _, action: .sendResultSuccess(.closeTapped)))),
                    .swapAndPayCoordFlow(.path(.element(id: _, action: .sendResultFailure(.closeTapped)))),
                    .swapAndPayCoordFlow(.path(.element(id: _, action: .sendResultPending(.closeTapped)))):
                state.path = nil
                return .none

            case .swapAndPayCoordFlow(.path(.element(id: _, action: .transactionDetails(.closeDetailTapped)))):
                state.path = nil
                return .none

                // MARK: - Transactions Coord Flow
                
            case .transactionsCoordFlow(.transactionDetails(.closeDetailTapped)):
                state.path = nil
                return .none

            case .transactionsCoordFlow(.transactionsManager(.dismissRequired)):
                state.path = nil
                return .none

            case .transactionsCoordFlow(.transactionDetails(.sendAgainTapped)):
                state.path = nil
                let transactionState = state.transactionsCoordFlowState.transactionDetailsState.transaction
                return .run { send in
                    try? await mainQueue.sleep(for: .seconds(0.8))
                    await send(.sendAgainRequested(transactionState))
                }
                
            case .transactionsCoordFlow(.path(.element(id: _, action: .transactionDetails(.sendAgainTapped)))):
                for element in state.transactionsCoordFlowState.path {
                    if case .transactionDetails(let transactionDetailsState) = element {
                        state.path = nil
                        return .run { send in
                            try? await mainQueue.sleep(for: .seconds(0.8))
                            await send(.sendAgainRequested(transactionDetailsState.transaction))
                        }
                    }
                }
                return .none

                // MARK: - Wallet Backup Coord Flow

            case .walletBackupCoordFlow(.path(.element(id: _, action: .phrase(.remindMeLaterTapped)))):
                state.path = nil
                return .send(.home(.smartBanner(.remindMeLaterTapped(.priority6))))

            case .walletBackupCoordFlow(.path(.element(id: _, action: .phrase(.seedSavedTapped)))):
                state.path = nil
                do {
                    try walletStorage.markUserPassedPhraseBackupTest(true)
                } catch {
                    state.alert = AlertState.cantStoreThatUserPassedPhraseBackupTest(error.toZcashError())
                }
                return .merge(
                    .send(.home(.smartBanner(.closeAndCleanupBanner))),
                    .send(.home(.smartBanner(.closeSheetTapped)))
                )

            default: return .none
            }
        }
    }

    private func refreshMockBalance(state: inout Root.State) -> Effect<Root.Action> {
        let address = state.selectedWalletAccount?.privateUnifiedAddress ?? ""
        guard !address.isEmpty else { return .none }
        return .run { [mockBalance = state.$mockBalance] _ in
            @Dependency(\.paymentServiceClient) var paymentServiceClient
            let response = try await paymentServiceClient.getBalance(address)
            mockBalance.withLock { $0 = response.balance }
        } catch: { _, _ in
            // Service unreachable — keep existing balance
        }
    }
}
