//
//  ReceiveView.swift
//  Zashi
//
//  Created by Lukáš Korba on 05.07.2022.
//

import SwiftUI
import ComposableArchitecture
import ZcashLightClientKit

import Generated
import UIComponents
import Utils

// Path
import AddressDetails
import PublicPaymentFlow
import RequestZec
import ZecKeyboard

public struct ReceiveView: View {
    @Environment(\.colorScheme) var colorScheme

    @Perception.Bindable var store: StoreOf<Receive>
    let networkType: NetworkType
    let tokenName: String

    @State var explainer = false
    @State var ldaInfo = false

    public init(store: StoreOf<Receive>, networkType: NetworkType, tokenName: String) {
        self.store = store
        self.networkType = networkType
        self.tokenName = tokenName
    }

    public var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                VStack(spacing: 0) {
                    ScrollView {
                        WithPerceptionTracking {
                            // 1. Linkable Dynamic Address (primary)
                            ldaAddressBlock()
                                .padding(.top, 24)

                            // 2. Transparent Address
                            transparentAddressBlock()

                            // 3. Public Donation Address
                            publicDonationSection()
                        }
                    }
                    .padding(.vertical, 1)
                    .onAppear {
                        store.send(.onAppear)
                    }

                    Spacer()

                    // Privacy footer
                    Asset.Assets.shieldTick.image
                        .zImage(size: 24, style: Design.Text.tertiary)
                        .padding(.bottom, 8)

                    Text("For privacy, always use shielded address.")
                        .zFont(size: 14, style: Design.Text.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 48)
                }
                .padding(.horizontal, 4)
                .applyScreenBackground()
                .screenTitle(L10n.Tabs.receiveZec)
                .zashiBack() { store.send(.backToHomeTapped) }
            } destination: { store in
                switch store.case {
                case let .addressDetails(store):
                    AddressDetailsView(store: store)
                case let .publicPaymentRegistration(store):
                    PublicPaymentRegistrationView(store: store)
                case let .requestZec(store):
                    RequestZecView(store: store, tokenName: tokenName)
                case let .requestZecSummary(store):
                    RequestZecSummaryView(store: store, tokenName: tokenName)
                case let .zecKeyboard(store):
                    ZecKeyboardView(store: store, tokenName: tokenName)
                }
            }
            .navigationBarHidden(!store.path.isEmpty)
            .zashiSheet(isPresented: $explainer) {
                explainerContent()
            }
            .zashiSheet(isPresented: $ldaInfo) {
                ldaInfoContent()
            }
        }
    }

    // MARK: - LDA Address Block

    @ViewBuilder private func ldaAddressBlock() -> some View {
        addressBlock(
            prefixIcon: Asset.Assets.Brandmarks.brandmarkMax.image,
            title: "Linkable Dynamic Address",
            address: store.ldaAddress,
            iconFg: Design.Utility.Purple._800,
            iconBg: Design.Utility.Purple._100,
            bcgColor: Design.Utility.Purple._50.color(colorScheme),
            expanded: store.currentFocus == .ldaAddress,
            shield: true,
            copyButtonTitle: "Share",
            infoAction: {
                store.send(.ldaInfoTapped)
                ldaInfo = true
            }
        ) {
            store.send(.shareTapped(store.ldaAddress))
        } qrAction: {
            store.send(.addressDetailsRequest(store.ldaAddress.redacted, true))
        } requestAction: {
            store.send(.requestTapped(store.ldaAddress.redacted, true))
        }
        .onTapGesture {
            store.send(.updateCurrentFocus(.ldaAddress), animation: .default)
        }
    }

    // MARK: - Transparent Address Block

    @ViewBuilder private func transparentAddressBlock() -> some View {
        addressBlock(
            prefixIcon: Asset.Assets.Brandmarks.brandmarkMax.image,
            title: L10n.Accounts.Zashi.transparentAddress,
            address: store.transparentAddress,
            iconFg: Design.Text.primary,
            iconBg: Design.Surfaces.bgTertiary,
            bcgColor: Design.Surfaces.bgSecondary.color(colorScheme),
            expanded: store.currentFocus == .tAddress,
            copyButton: false,
            infoAction: {
                store.send(.infoTapped(false))
                explainer = true
            }
        ) {
            store.send(.copyToPastboard(store.transparentAddress.redacted))
        } qrAction: {
            store.send(.addressDetailsRequest(store.transparentAddress.redacted, false))
        } requestAction: {
            store.send(.requestTapped(store.transparentAddress.redacted, false))
        }
        .onTapGesture {
            store.send(.updateCurrentFocus(.tAddress), animation: .default)
        }
    }

    // MARK: - Public Donation Section

    @ViewBuilder private func publicDonationSection() -> some View {
        VStack(spacing: 12) {
            if store.isPublicDonationRegistered {
                // Registered — show the address card (no Request button for public addresses)
                let pubAddr = store.publicDonationAddress
                addressBlock(
                    prefixIcon: Asset.Assets.Brandmarks.brandmarkMax.image,
                    title: "Public Donation Address",
                    address: pubAddr,
                    iconFg: Design.Text.primary,
                    iconBg: Design.Surfaces.bgTertiary,
                    bcgColor: Design.Surfaces.bgSecondary.color(colorScheme),
                    expanded: store.currentFocus == .publicDonationAddress,
                    showRequest: false,
                    infoAction: {
                        store.send(.infoTapped(true))
                        explainer = true
                    }
                ) {
                    store.send(.copyToPastboard(pubAddr.redacted))
                } qrAction: {
                    store.send(.addressDetailsRequest(pubAddr.redacted, false))
                } requestAction: {}
                .onTapGesture {
                    store.send(.updateCurrentFocus(.publicDonationAddress), animation: .default)
                }
            }

            // Register button (shown when not registered)
            if !store.isPublicDonationRegistered {
                Button {
                    store.send(.registerPublicAddressTapped)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Design.Text.primary.color(colorScheme))
                        Text("Register a Public Address")
                            .zFont(.semiBold, size: 16, style: Design.Text.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._xl)
                            .fill(Design.Utility.WarningYellow._400.color(colorScheme))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Explainer Sheets

    @ViewBuilder private func explainerContent() -> some View {
        VStack(spacing: 0) {
            if store.isExplainerForShielded {
                shieldedAddressExplainerContent()
            } else {
                transparentAddressExplainerContent()
            }
        }
    }

    @ViewBuilder private func ldaInfoContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("🔗")
                .font(.system(size: 18))
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: Design.Radius._full)
                        .fill(Design.Surfaces.bgTertiary.color(colorScheme))
                }
                .padding(.top, 24)
                .padding(.bottom, 12)

            Text("Linkable Dynamic Address")
                .zFont(.semiBold, size: 20, style: Design.Text.primary)
                .padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)

            infoContent(text: "Each address encodes your static 32-byte shielded receiver and a unique random 32-byte PIR tag, base58-encoded for sharing.")
                .padding(.bottom, 12)

            infoContent(text: "Senders query your payment info via Private Information Retrieval (PIR) using the static component — the server never learns who is being paid.")
                .padding(.bottom, 12)

            infoContent(text: "The random tag makes each shared address unlinkable, while remaining recoverable from your seed phrase.")
                .padding(.bottom, 12)

            infoContent(text: "All payments received through different Linkable Dynamic Addresses arrive in your shielded wallet balance under the same seed phrase.")
                .padding(.bottom, 32)

            ZashiButton(L10n.General.ok.uppercased()) {
                store.send(.ldaInfoDismissed)
                ldaInfo = false
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder private func shieldedAddressExplainerContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Asset.Assets.Icons.shieldTickFilled.image
                .zImage(size: 20, style: Design.Text.primary)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: Design.Radius._full)
                        .fill(Design.Surfaces.bgTertiary.color(colorScheme))
                }
                .padding(.top, 24)
                .padding(.bottom, 12)

            Text(L10n.Receive.Help.Shielded.title)
                .zFont(.semiBold, size: 20, style: Design.Text.primary)
                .padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)

            infoContent(text: L10n.Receive.Help.Shielded.desc1)
                .padding(.bottom, 12)

            infoContent(text: L10n.Receive.Help.Shielded.desc2)
                .padding(.bottom, 12)

            infoContent(text: L10n.Receive.Help.Shielded.desc3)
                .padding(.bottom, 12)

            infoContent(text: L10n.Receive.Help.Shielded.desc4)
                .padding(.bottom, 32)

            ZashiButton(L10n.General.ok.uppercased()) {
                store.send(.infoTapped(true))
                explainer = false
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder private func transparentAddressExplainerContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Asset.Assets.Icons.shieldOff.image
                .zImage(size: 20, style: Design.Text.primary)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: Design.Radius._full)
                        .fill(Design.Surfaces.bgTertiary.color(colorScheme))
                }
                .padding(.top, 24)
                .padding(.bottom, 12)

            Text(L10n.Receive.Help.Transparent.title)
                .zFont(.semiBold, size: 20, style: Design.Text.primary)
                .padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)

            infoContent(text: L10n.Receive.Help.Transparent.desc1)
                .padding(.bottom, 12)

            infoContent(text: L10n.Receive.Help.Transparent.desc2)
                .padding(.bottom, 12)

            infoContent(text: L10n.Receive.Help.Transparent.desc3)
                .padding(.bottom, 12)

            infoContent(text: L10n.Receive.Help.Transparent.desc4)
                .padding(.bottom, 32)

            ZashiButton(L10n.General.ok.uppercased()) {
                store.send(.infoTapped(false))
                explainer = false
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    // MARK: - Shared Components

    @ViewBuilder private func infoContent(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .frame(width: 4, height: 4)
                .foregroundColor(Design.Text.tertiary.color(colorScheme))
                .padding(.top, 8)

            if let attrText = try? AttributedString(
                markdown: text,
                including: \.zashiApp
            ) {
                ZashiText(withAttributedString: attrText, colorScheme: colorScheme)
                    .zFont(size: 14, style: Design.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func addressBlock(
        prefixIcon: Image,
        title: String,
        address: String,
        iconFg: Colorable,
        iconBg: Colorable,
        bcgColor: Color,
        expanded: Bool,
        shield: Bool = false,
        copyButton: Bool = true,
        copyButtonTitle: String? = nil,
        showRequest: Bool = true,
        infoAction: @escaping () -> Void = {},
        copyAction: @escaping () -> Void,
        qrAction: @escaping () -> Void,
        requestAction: @escaping () -> Void
    ) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 0) {
                if shield {
                    prefixIcon
                        .resizable()
                        .frame(width: 40, height: 40)
                        .padding(.trailing, 16)
                        .overlay {
                            Asset.Assets.Icons.shieldBcg.image
                                .zImage(size: 18, color: bcgColor)
                                .offset(x: 6, y: 14)
                                .overlay {
                                    Asset.Assets.Icons.shieldTickFilled.image
                                        .zImage(size: 14, color: colorScheme == .light ? .black : .white)
                                        .offset(x: 6.25, y: 14)
                                }
                        }
                } else {
                    prefixIcon
                        .resizable()
                        .frame(width: 40, height: 40)
                        .padding(.trailing, 16)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .zFont(.semiBold, size: 16, style: Design.Text.primary)
                        .minimumScaleFactor(0.5)
                        .padding(.bottom, 4)

                    Text(address.truncateMiddle10)
                        .zFont(fontFamily: .robotoMono, size: 14, style: Design.Text.tertiary)
                        .padding(.bottom, expanded ? 10 : 0)
                }
                .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    infoAction()
                } label: {
                    Asset.Assets.infoCircle.image
                        .zImage(size: 16, style: Design.Btns.Ghost.fg)
                        .padding(8)
                        .background {
                            if shield {
                                RoundedRectangle(cornerRadius: Design.Radius._md)
                                    .fill(Design.Utility.Purple._100.color(colorScheme))
                            } else {
                                RoundedRectangle(cornerRadius: Design.Radius._md)
                                    .fill(Design.Utility.Gray._200.color(colorScheme))
                            }
                        }
                }
            }
            .padding(.horizontal, 20)

            if expanded {
                HStack(spacing: 8) {
                    if copyButton {
                        button(
                            copyButtonTitle ?? L10n.Receive.copy,
                            fill: iconBg.color(colorScheme),
                            icon: Asset.Assets.copy.image
                        ) {
                            copyAction()
                        }
                    }

                    button(
                        L10n.Receive.qrCode,
                        fill: iconBg.color(colorScheme),
                        icon: Asset.Assets.Icons.qr.image
                    ) {
                        qrAction()
                    }

                    if showRequest {
                        button(
                            L10n.Receive.request,
                            fill: iconBg.color(colorScheme),
                            icon: Asset.Assets.Icons.coinsHand.image
                        ) {
                            requestAction()
                        }
                    }
                }
                .zFont(.medium, size: 14, style: iconFg)
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: Design.Radius._4xl)
                .fill(bcgColor)
        }
    }

    private func button(_ title: String, fill: Color, icon: Image, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            ZStack {
                icon
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                    .offset(x: 0, y: -10)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._xl)
                            .fill(fill)
                    }

                Text(title)
                    .offset(x: 0, y: 10)
            }
        }
    }
}

#Preview {
    NavigationView {
        ReceiveView(store: Receive.placeholder, networkType: .testnet, tokenName: "ZEC")
    }
}

// MARK: - Placeholders

extension Receive.State {
    public static let initial = Receive.State()
}

extension Receive {
    public static let placeholder = StoreOf<Receive>(
        initialState: .initial
    ) {
        Receive()
    }
}
