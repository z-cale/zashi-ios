//
//  WalletBirthdayEstimateDateView.swift
//  Zashi
//
//  Created by Lukáš Korba on 03-31-2025.
//

import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

public struct WalletBirthdayEstimateDateView: View {
    @Perception.Bindable var store: StoreOf<WalletBirthday>
    
    public init(store: StoreOf<WalletBirthday>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                if store.isKeystoneFlow {
                    Asset.Assets.Partners.keystoneTitleLogo.image
                        .resizable()
                        .frame(width: 193, height: 32)
                        .padding(.top, 16)
                }

                Text(localizable: .restoreWalletBirthdayEstimateDateTitle)
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 40)
                    .padding(.bottom, 8)

                // TODO: Loc
//                Text(localizable: .restoreWalletBirthdayEstimateDateInfo)
                Text(
                    store.isKeystoneFlow
                    ? "L10n.Keystone.Birthday.EstimateDate.info"
                    : "L10n.RestoreWallet.Birthday.EstimateDate.info"
                )
                .zFont(size: 14, style: Design.Text.primary)
                .padding(.bottom, 32)

                HStack {
                    Picker("", selection: $store.selectedMonth) {
                        ForEach(store.months, id: \.self) { month in
                            Text(month)
                                .zFont(size: 23, style: Design.Text.primary)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("", selection: $store.selectedYear) {
                        ForEach(store.years, id: \.self) { year in
                            Text("\(String(year))")
                                .zFont(size: 23, style: Design.Text.primary)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                
                Spacer()

                if !store.isKeystoneFlow {
                    HStack(spacing: 0) {
                        Asset.Assets.infoOutline.image
                            .zImage(size: 20, style: Design.Utility.Indigo._500)
                            .padding(.trailing, 12)
                        
                        Text(localizable: .restoreWalletDateTip)
                            .zFont(.medium, size: 12, style: Design.Utility.Indigo._700)
                    }
                    .padding(.bottom, 20)
                    .screenHorizontalPadding()
                }

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

                ZashiButton(String(localizable: .generalNext)) {
                    store.send(.estimateHeightRequested)
                }
                .padding(.bottom, 24)
            }
            .onAppear { store.send(.onAppear) }
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
        .screenTitle(store.isKeystoneFlow ? "" : "L10n.ImportWallet.Button.restoreWallet")
    }
}

// MARK: - Previews

#Preview {
    WalletBirthdayEstimateDateView(store: WalletBirthday.initial)
}
