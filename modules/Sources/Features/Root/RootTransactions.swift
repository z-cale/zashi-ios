//
//  RootTransactions.swift
//  Zashi
//
//  Created by Lukáš Korba on 29.01.2025.
//

import Combine
import ComposableArchitecture
import Foundation
import ZcashLightClientKit
import Generated
import Models
import UserMetadataProvider

extension Root {
    public func transactionsReduce() -> Reduce<Root.State, Root.Action> {
        Reduce { state, action in
            switch action {
            case .observeTransactions:
                return .merge(
                    .publisher {
                        sdkSynchronizer.eventStream()
                            .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                            .compactMap {
                                if case SynchronizerEvent.foundTransactions(let transactions, _) = $0 {
                                    return Root.Action.foundTransactions(transactions)
                                } else if case SynchronizerEvent.minedTransaction(let transaction) = $0 {
                                    return Root.Action.minedTransaction(transaction)
                                }
                                return nil
                            }
                    }
                    .cancellable(id: state.CancelEventId, cancelInFlight: true),
                    .publisher {
                        sdkSynchronizer.stateStream()
                            .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                            .map {
                                if $0.syncStatus == .upToDate {
                                    return Root.Action.syncReachedUpToDate
                                }
                                return Root.Action.noChangeInTransactions
                            }
                    }
                    .cancellable(id: state.CancelStateId, cancelInFlight: true),
                    .send(.fetchTransactionsForTheSelectedAccount)
                )
                
            case .noChangeInTransactions:
                return .none
                
            case .foundTransactions, .syncReachedUpToDate:
                var effects: [Effect<Root.Action>] = [
                    .send(.fetchTransactionsForTheSelectedAccount)
                ]
                if state.walletConfig.isEnabled(.pirSpendability) {
                    effects.append(.send(.initialization(.checkSpendabilityPIR)))
                }
                if state.walletConfig.isEnabled(.pirWitness) && !state.walletConfig.isEnabled(.pirSpendability) {
                    effects.append(.send(.initialization(.checkWitnessPIR)))
                }
                return .merge(effects)
                
            case .minedTransaction:
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .fetchTransactionsForTheSelectedAccount:
                guard let accountUUID = state.selectedWalletAccount?.id else {
                    return .none
                }
                let pirEnabled = state.walletConfig.isEnabled(.pirSpendability)
                return .run { send in
                    async let txTask = sdkSynchronizer.getAllTransactions(accountUUID)
                    let pirActivity: [PIRActivityEntry]?
                    if pirEnabled {
                        pirActivity = try? await sdkSynchronizer.getPIRActivityEntries()
                    } else {
                        pirActivity = nil
                    }

                    if let transactions = try? await txTask {
                        await send(.fetchedTransactions(transactions, pirActivity))
                    }
                }
                
            case .fetchedTransactions(var transactions, let pirActivityEntries):
                let mempoolHeight = sdkSynchronizer.latestState().latestBlockHeight + 1

                // Resolve Swaps
                let allSwaps = userMetadataProvider.allSwaps()
                
                // Swaps From ZEC and CrossPays
                let swapsFromZecAndCrossPays = allSwaps.filter {
                    $0.fromAsset == SwapConstants.zecAssetIdOnNear
                }
                
                swapsFromZecAndCrossPays.forEach { swap in
                    if let transaction = transactions.filter({ $0.zAddress == swap.depositAddress }).first {
                        transactions[id: transaction.id]?.type = swap.exactInput ? .swapFromZec : .crossPay
                        transactions[id: transaction.id]?.swapStatus = swap.swapStatus
                    }
                }

                // Swaps To ZEC
                let swapsToZec = allSwaps.filter {
                    $0.toAsset == SwapConstants.zecAssetIdOnNear
                }

                var mixedTransactions = transactions

                swapsToZec.forEach { swap in
                    mixedTransactions.append(
                        TransactionState(
                            depositAddress: swap.depositAddress,
                            timestamp: TimeInterval(swap.lastUpdated / 1000),
                            zecAmount: swap.amountOutFormatted.localeString ?? swap.amountOutFormatted,
                            swapStatus: swap.swapStatus
                        )
                    )
                }

                // PIR-derived transaction entries — real "Sent" rows that seamlessly
                // transition to scanner-confirmed entries via matching rawID (tx hash).
                if state.walletConfig.isEnabled(.pirSpendability),
                   let pirEntries = pirActivityEntries {
                    let existingIDs = Set(mixedTransactions.map(\.id))
                    for entry in pirEntries {
                        let entryID = entry.rawID.toHexStringTxId()
                        if existingIDs.contains(entryID) { continue }
                        mixedTransactions.append(
                            TransactionState(pirActivityEntry: entry)
                        )
                    }
                }

                // Sort all transactions
                let sortedTransactions = mixedTransactions
                    .sorted { lhs, rhs in
                        if let lhsTimestamp = lhs.timestamp, let rhsTimestamp = rhs.timestamp {
                            return lhsTimestamp > rhsTimestamp
                        } else {
                            return lhs.transactionListHeight(mempoolHeight) > rhs.transactionListHeight(mempoolHeight)
                        }
                    }
                
                let identifiedArray = IdentifiedArrayOf<TransactionState>(uniqueElements: sortedTransactions)

                // Update transactions
                if state.transactions != identifiedArray {
                    state.$transactions.withLock {
                        $0 = identifiedArray
                    }
                    return .send(.home(.smartBanner(.evaluatePriority6)))
                }
                return .none

            default: return .none
            }
        }
    }
}
