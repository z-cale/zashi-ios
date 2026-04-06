//
//  ServerSetupView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2024-02-07.
//

import SwiftUI
import ComposableArchitecture
import ZcashLightClientKit

import Generated
import UIComponents
import ZcashSDKEnvironment

public struct ServerSetupView: View {
    @Environment(\.colorScheme) var colorScheme

    var customDismiss: (() -> Void)? = nil

    @Perception.Bindable var store: StoreOf<ServerSetup>

    public init(store: StoreOf<ServerSetup>, customDismiss: (() -> Void)? = nil) {
        self.store = store
        self.customDismiss = customDismiss
    }

    public var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .center, spacing: 0) {
                ScrollView {
                    Text(localizable: .serverSetupDescription)
                        .zFont(size: 14, style: Design.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .screenHorizontalPadding()
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    if store.topKServers.isEmpty {
                        VStack(spacing: 15) {
                            progressView()

                            Text(localizable: .serverSetupPerformingTest)
                                .zFont(.semiBold, size: 20, style: Design.Text.primary)

                            Text(localizable: .serverSetupCouldTakeTime)
                                .zFont(size: 14, style: Design.Text.tertiary)
                        }
                        .frame(height: 136)
                    } else {
                        HStack {
                            Text(localizable: .serverSetupFastestServers)
                                .zFont(.semiBold, size: 18, style: Design.Text.primary)

                            Spacer()

                            Button {
                                store.send(.refreshServersTapped)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(localizable: .serverSetupRefresh)
                                        .zFont(.semiBold, size: 14, style: Design.Text.primary)

                                    if store.isEvaluatingServers {
                                        progressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Asset.Assets.refreshCCW2.image
                                            .zImage(size: 20, style: Design.Text.primary)
                                    }
                                }
                                .padding(5)
                            }
                        }
                        .screenHorizontalPadding()
                        .padding(.top, 12)

                        serverList(store.topKServers)
                    }

                    HStack {
                        Text(
                            store.topKServers.isEmpty
                            ? String(localizable: .serverSetupAllServers)
                            : String(localizable: .serverSetupOtherServers)
                        )
                        .zFont(.semiBold, size: 18, style: Design.Text.primary)

                        Spacer()
                    }
                    .screenHorizontalPadding()
                    .padding(.top, store.topKServers.isEmpty ? 0 : 15)

                    serverList(store.servers)
                }
                .padding(.vertical, 1)

                WithPerceptionTracking {
                    ZStack {
                        Asset.Colors.background.color
                            .frame(height: 72)
                            .cornerRadius(32)
                            .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: -8)

                        let canSave = store.hasChanges && !store.selectedServers.isEmpty

                        Button {
                            store.send(.setServerTapped)
                        } label: {
                            if store.isUpdatingServer {
                                HStack(spacing: 8) {
                                    Text(localizable: .serverSetupSave)
                                        .zFont(.semiBold, size: 16,
                                               style: !canSave
                                               ? Design.Btns.Primary.fgDisabled
                                               : Design.Btns.Primary.fg
                                        )
                                    progressView(invertTint: true)
                                }
                                .frame(height: 48)
                                .frame(maxWidth: .infinity)
                                .background(
                                    !canSave
                                    ? Design.Btns.Primary.bgDisabled.color(colorScheme)
                                    : Design.Btns.Primary.bg.color(colorScheme)
                                )
                                .cornerRadius(10)
                                .screenHorizontalPadding()
                            } else {
                                Text(localizable: .serverSetupSave)
                                    .zFont(.semiBold, size: 16,
                                           style: !canSave
                                           ? Design.Btns.Primary.fgDisabled
                                           : Design.Btns.Primary.fg
                                    )
                                    .frame(height: 48)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        !canSave
                                        ? Design.Btns.Primary.bgDisabled.color(colorScheme)
                                        : Design.Btns.Primary.bg.color(colorScheme)
                                    )
                                    .cornerRadius(10)
                                    .screenHorizontalPadding()
                            }
                        }
                        .disabled(store.isUpdatingServer || !canSave)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .zashiBack(store.isUpdatingServer, customDismiss: customDismiss)
            .screenTitle(String(localizable: .serverSetupTitle))
            .onAppear { store.send(.onAppear) }
            .alert($store.scope(state: \.alert, action: \.alert))
            .applyScreenBackground()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func serverList(_ servers: [ZcashSDKEnvironment.Server]) -> some View {
        ForEach(servers, id: \.self) { server in
            WithPerceptionTracking {
                let serverValue = server.value(for: store.network)
                let isSelected = store.selectedServers.contains(serverValue)
                let isCustom = serverValue == String(localizable: .serverSetupCustom)
                let isCustomExpanded = isCustom && isSelected
                let isSyncServer = isCustom
                    ? store.activeSyncServer == store.customServer
                    : store.activeSyncServer == serverValue

                VStack {
                    HStack(spacing: 0) {
                        Button {
                            store.send(.serverToggled(serverValue))
                        } label: {
                            HStack(
                                alignment: isCustomExpanded ? .top : .center,
                                spacing: 10
                            ) {
                                checkbox(isSelected: isSelected)
                                    .padding(.top, isCustomExpanded ? 16 : 0)

                                if isCustomExpanded {
                                    VStack(alignment: .leading) {
                                        Text(serverValue)
                                            .zFont(.medium, size: 14, style: Design.Text.primary)
                                            .multilineTextAlignment(.leading)

                                        WithPerceptionTracking {
                                            TextField(
                                                String(localizable: .serverSetupPlaceholder),
                                                text: $store.customServer
                                            )
                                            .zFont(.medium, size: 14, style: Design.Text.primary)
                                            .frame(height: 40)
                                            .autocapitalization(.none)
                                            .multilineTextAlignment(.leading)
                                            .padding(.leading, 10)
                                            .background {
                                                RoundedRectangle(cornerRadius: Design.Radius._md)
                                                    .fill(Design.Surfaces.bgPrimary.color(colorScheme))
                                            }
                                            .overlay {
                                                RoundedRectangle(cornerRadius: Design.Radius._md)
                                                    .stroke(Design.Inputs.Default.stroke.color(colorScheme), lineWidth: 1)
                                            }
                                            .padding(.vertical, 8)
                                        }
                                    }
                                    .padding(.vertical, 16)
                                } else {
                                    VStack(alignment: .leading) {
                                        Text(
                                            isCustom && !store.customServer.isEmpty
                                            ? store.customServer
                                            : serverValue
                                        )
                                        .zFont(.medium, size: 14, style: Design.Text.primary)
                                        .multilineTextAlignment(.leading)

                                        if let desc = server.desc(for: store.network) {
                                            Text(desc)
                                                .zFont(size: 14, style: Design.Text.tertiary)
                                        }
                                    }
                                }

                                Spacer()

                                if isSyncServer {
                                    Text(localizable: .serverSetupActive)
                                        .zFont(.medium, size: 14, style: Design.Utility.SuccessGreen._700)
                                        .frame(height: 20)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 2)
                                        .zBackground(Design.Utility.SuccessGreen._50)
                                        .cornerRadius(16)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: Design.Radius._2xl)
                                                .inset(by: 0.5)
                                                .stroke(Design.Utility.SuccessGreen._200.color(colorScheme), lineWidth: 1)
                                        }
                                }

                                if isCustom && !isSelected {
                                    Asset.Assets.chevronDown.image
                                        .zImage(size: 20, style: Design.Text.primary)
                                }
                            }
                            .frame(minHeight: 48)
                            .padding(.leading, 24)
                            .padding(.trailing, isCustomExpanded ? 0 : 24)
                            .background {
                                RoundedRectangle(cornerRadius: Design.Radius._xl)
                                    .fill(
                                        isSelected
                                        ? Design.Surfaces.bgSecondary.color(colorScheme)
                                        : Asset.Colors.background.color
                                    )
                            }
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 8)

                    if let last = servers.last, last != server {
                        Design.Surfaces.divider.color(colorScheme)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func checkbox(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Design.Surfaces.brandPrimary.color(colorScheme))
                .frame(width: 20, height: 20)
                .overlay {
                    Asset.Assets.check.image
                        .zImage(size: 14, style: Design.Surfaces.brandFg)
                }
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Design.Checkboxes.offBg.color(colorScheme))
                .frame(width: 20, height: 20)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Design.Checkboxes.offStroke.color(colorScheme))
                        .frame(width: 20, height: 20)
                }
        }
    }

    private func progressView(invertTint: Bool = false) -> some View {
        ProgressView()
            .progressViewStyle(
                CircularProgressViewStyle(
                    tint: colorScheme == .dark
                    ? (invertTint ? .black : .white) : (invertTint ? .white : .black)
                )
            )
    }
}

// MARK: - Previews

#Preview {
    NavigationView {
        ServerSetupView(
            store: ServerSetup.placeholder
        )
    }
}

// MARK: Placeholders

extension ServerSetup.State {
    public static var initial = ServerSetup.State()
}

extension ServerSetup {
    public static let placeholder = StoreOf<ServerSetup>(
        initialState: .initial
    ) {
        ServerSetup()
    }
}
