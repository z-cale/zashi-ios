//
//  RestoreInfoView.swift
//  Zashi
//
//  Created by Lukáš Korba on 06-03-2024
//

import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

public struct RestoreInfoView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @Perception.Bindable var store: StoreOf<RestoreInfo>
    
    public init(store: StoreOf<RestoreInfo>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                Asset.Assets.Illustrations.connect.image
                    .resizable()
                    .frame(width: 132, height: 90)
                    .padding(.top, 40)
                    .padding(.bottom, 24)

                Text(localizable: .restoreInfoTitle)
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.bottom, 8)

                Text(localizable: .restoreInfoSubTitle)
                    .zFont(.medium, size: 16, style: Design.Text.primary)
                    .padding(.bottom, 16)

                Text(localizable: .restoreInfoTips)
                    .zFont(size: 14, style: Design.Text.primary)
                    .padding(.bottom, 4)

                bulletpoint(String(localizable: .restoreInfoTip1))
                bulletpoint(String(localizable: .restoreInfoTip2))
                    .padding(.bottom, 20)

                Spacer()

                Text("\(Text(localizable: .restoreInfoNote).bold())\(String(localizable: .restoreInfoNoteInfo))")
                    .zFont(size: 12, style: Design.Text.primary)
                    .padding(.bottom, 24)

                HStack {
                    ZashiToggle(
                        isOn: $store.isAcknowledged,
                        label: String(localizable: .restoreInfoCheckbox),
                        textSize: 16
                    )
                    
                    Spacer()
                }
                .padding(.leading, 1)

                ZashiButton(String(localizable: .restoreInfoGotIt)) {
                    store.send(.gotItTapped)
                }
                .padding(.vertical, 24)
            }
            .zashiBack(hidden: true)
        }
        .navigationBarTitleDisplayMode(.inline)
        .screenHorizontalPadding()
        .applyScreenBackground()
    }
    
    @ViewBuilder
    private func bulletpoint(_ text: String) -> some View {
        HStack(alignment: .top) {
            Circle()
                .frame(width: 4, height: 4)
                .padding(.top, 7)
                .padding(.leading, 8)

            Text(text)
                .zFont(size: 14, style: Design.Text.primary)
        }
        .padding(.bottom, 5)
    }
}

// MARK: - Previews

#Preview {
    RestoreInfoView(store: RestoreInfo.initial)
}

// MARK: - Store

extension RestoreInfo {
    public static var initial = StoreOf<RestoreInfo>(
        initialState: .initial
    ) {
        RestoreInfo()
    }
}

// MARK: - Placeholders

extension RestoreInfo.State {
    public static let initial = RestoreInfo.State()
}
