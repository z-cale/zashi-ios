//
//  WalletBirthdayEstimatedHeightView.swift
//  Zashi
//
//  Created by Lukáš Korba on 03-31-2025.
//

import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

public struct WalletBirthdayEstimatedHeightView: View {
    @Perception.Bindable var store: StoreOf<WalletBirthday>
    
    public init(store: StoreOf<WalletBirthday>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                Text(localizable: .restoreWalletBirthdayEstimatedTitle)
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 40)
                    .padding(.bottom, 8)

                Text(localizable: .restoreWalletBirthdayEstimatedInfo)
                    .zFont(size: 14, style: Design.Text.primary)
                    .padding(.bottom, 56)

                VStack {
                    Text(store.estimatedHeightString)
                        .zFont(.semiBold, size: 48, style: Design.Text.primary)
                        .padding(.bottom, 12)

                    ZashiButton(
                        String(localizable: .receiveCopy),
                        type: .tertiary,
                        infinityWidth: false,
                        prefixView:
                            Asset.Assets.copy.image
                                .zImage(size: 20, style: Design.Btns.Tertiary.fg)
                    ) {
                        store.send(.copyBirthdayTapped)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                if store.isKeystoneFlow {
                    // TODO: Loc
                    ZashiButton(
                        "L10n.Keystone.AddHWWallet.enterManually",
                        type: .ghost
                    ) {
                        store.send(.enterManuallyTapped)
                    }
                    .padding(.bottom, 12)
                }

                    // TODO: Loc
//                ZashiButton(String(localizable: .importWalletButtonRestoreWallet))
                ZashiButton(store.isKeystoneFlow ? "L10n.Keystone.AddHWWallet.connect" : "L10n.ImportWallet.Button.restoreWallet") {
                    store.send(.restoreTapped)
                }
                .padding(.bottom, 24)
            }
            .zashiBack()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
            trailing:
                Button {
                    store.send(.helpSheetRequested)
                } label: {
                    Asset.Assets.Icons.help.image
                        .zImage(size: 24, style: Design.Text.primary)
                        .padding(Design.Spacing.navBarButtonPadding)
                }
        )
        .screenHorizontalPadding()
        .applyScreenBackground()
        // TODO: Loc
//        .screenTitle(String(localizable: .importWalletButtonRestoreWallet))
        .screenTitle(store.isKeystoneFlow ? "L10n.Keystone.connect" : "L10n.ImportWallet.Button.restoreWallet")
    }
}

// MARK: - Previews

#Preview {
    WalletBirthdayEstimateDateView(store: WalletBirthday.initial)
}
