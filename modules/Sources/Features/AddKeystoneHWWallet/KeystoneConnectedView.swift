//
//  KeystoneConnectedView.swift
//  Zodl
//
//  Created by Lukáš Korba on 2025-03-27.
//

import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

public struct KeystoneConnectedView: View {
    @Perception.Bindable var store: StoreOf<AddKeystoneHWWallet>

    public init(store: StoreOf<AddKeystoneHWWallet>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()
                
                store.successIlustration
                    .resizable()
                    .frame(width: 148, height: 148)
                
                Text(L10n.Keystone.AddHWWallet.connected)
                    .zFont(.semiBold, size: 28, style: Design.Text.primary)
                    .padding(.top, 16)
                
                Text(L10n.Keystone.AddHWWallet.connectedDesc)
                    .zFont(size: 14, style: Design.Text.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1.5)
                    .padding(.top, 8)
                    .screenHorizontalPadding()
                
                Spacer()
                
                ZashiButton(L10n.Keystone.AddHWWallet.close) {
                    store.send(.closeTapped)
                }
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden()
        .padding(.vertical, 1)
        .screenHorizontalPadding()
        .applySuccessScreenBackground()
    }
}
