//
//  AddKeystoneHWWalletCoordFlowView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2023-03-19.
//

import SwiftUI
import ComposableArchitecture

import UIComponents
import Generated

// Path
import AddKeystoneHWWallet
import Scan
import WalletBirthday

public struct AddKeystoneHWWalletCoordFlowView: View {
    @Environment(\.colorScheme) var colorScheme

    @Perception.Bindable var store: StoreOf<AddKeystoneHWWalletCoordFlow>
    let tokenName: String

    public init(store: StoreOf<AddKeystoneHWWalletCoordFlow>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    public var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                AddKeystoneHWWalletView(
                    store:
                        store.scope(
                            state: \.addKeystoneHWWalletState,
                            action: \.addKeystoneHWWallet
                        )
                )
            } destination: { store in
                switch store.case {
                case let .accountHWWalletSelection(store):
                    AccountsSelectionView(store: store)
                case let .scan(store):
                    ScanView(store: store)
                case let .walletBirthday(store):
                    WalletBirthdayView(store: store)
                case let .estimateBirthdaysDate(store):
                    WalletBirthdayEstimateDateView(store: store)
                case let .estimatedBirthday(store):
                    WalletBirthdayEstimatedHeightView(store: store)
                }
            }
        }
        .applyScreenBackground()
        .zashiBack()
        .zashiSheet(
            isPresented: Binding(
                get: { store.isHelpSheetPresented },
                set: { _ in store.send(.helpSheetRequested) }
            )
        ) {
            helpSheetContent()
        }
    }

    @ViewBuilder private func helpSheetContent() -> some View {
        VStack(spacing: 0) {
            Text(localizable: .restoreWalletHelpTitle)
                .zFont(.semiBold, size: 24, style: Design.Text.primary)
                .padding(.top, 24)
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 8) {
                Asset.Assets.infoCircle.image
                    .zImage(size: 20, style: Design.Text.primary)

                if let attrText = try? AttributedString(
                    markdown: String(localizable: .restoreWalletHelpBirthday),
                    including: \.zashiApp
                ) {
                    ZashiText(withAttributedString: attrText, colorScheme: colorScheme)
                        .zFont(size: 14, style: Design.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 32)

            ZashiButton(String(localizable: .restoreInfoGotIt)) {
                store.send(.helpSheetRequested)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }
}

#Preview {
    NavigationView {
        AddKeystoneHWWalletCoordFlowView(store: AddKeystoneHWWalletCoordFlow.placeholder, tokenName: "ZEC")
    }
}

// MARK: - Placeholders

extension AddKeystoneHWWalletCoordFlow.State {
    public static let initial = AddKeystoneHWWalletCoordFlow.State()
}

extension AddKeystoneHWWalletCoordFlow {
    public static let placeholder = StoreOf<AddKeystoneHWWalletCoordFlow>(
        initialState: .initial
    ) {
        AddKeystoneHWWalletCoordFlow()
    }
}
