import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

// MARK: - Sender: Enter Amount

struct PLSenderEnterAmountView: View {
    @Perception.Bindable var store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Text("Send a Friend ZEC")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)

                Text("They'll receive a link to claim the funds")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    TextField("Amount (ZEC)", text: $store.amount.sending(\.amountChanged))
                        .keyboardType(.decimalPad)
                        .font(.custom(FontFamily.RobotoMono.semiBold.name, size: 32))
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background { RoundedRectangle(cornerRadius: Design.Radius._xl).fill().zForegroundColor(Design.Surfaces.bgSecondary) }

                    MockBalanceView(isOverBalance: store.isOverBalance)
                }
                .padding(.top, 24)

                Spacer()

                ZashiButton("Create Payment Link") {
                    store.send(.proceedTapped)
                }
                .disabled(store.isOverBalance)
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Payment Link")
        }
        .applyScreenBackground()
    }
}

// MARK: - Sender: Share

struct PLSenderShareView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "link.badge.plus")
                    .font(.system(size: 48))
                    .zForegroundColor(Design.Surfaces.brandPrimary)

                Text("Payment Link Ready")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 16)

                Text("\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                    .zFont(.bold, size: 32, style: Design.Text.primary)
                    .padding(.top, 8)

                Text(store.qrContent)
                    .zFont(fontFamily: .robotoMono, size: 11, style: Design.Text.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text("Send this link to your friend. They can claim the funds even without a wallet — they'll be prompted to install Zodl.")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                Spacer()

                VStack(spacing: 12) {
                    ZashiButton("Share Link", prefixView: Image(systemName: "square.and.arrow.up")) {
                        store.send(.sharePayment)
                    }

                    ZashiButton("Link sent — continue demo", type: .secondary) {
                        store.send(.proceedTapped)
                    }

                    ZashiButton("Revoke Payment", type: .destructive1) {
                        store.send(.revokePayment)
                    }
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .sheet(isPresented: .constant(store.isSharePresented)) {
                ShareSheet(items: [store.qrContent]) {
                    store.send(.shareFinished)
                }
            }
            .zashiBack { store.send(.goBack) }
            .screenTitle("Payment Link")
        }
        .applyScreenBackground()
    }
}

// MARK: - Outside: Message Received

struct PLOutsideMessageReceivedView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                // Mock iMessage bubble
                VStack(alignment: .leading, spacing: 12) {
                    Text("iMessage")
                        .zFont(.medium, size: 12, style: Design.Text.quaternary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hey! Welcome to Zcash 🎉")
                            .zFont(size: 16, style: Design.Text.primary)

                        Text("I sent you \(store.amount.isEmpty ? "1.0" : store.amount) ZEC. Tap the link to claim it:")
                            .zFont(size: 16, style: Design.Text.primary)

                        Text(store.qrContent)
                            .zFont(fontFamily: .robotoMono, size: 12, color: .blue)
                            .lineLimit(2)
                    }
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.blue.opacity(0.08))
                    }
                }
                .padding(24)
                .background {
                    RoundedRectangle(cornerRadius: Design.Radius._2xl)
                        .fill()
                        .zForegroundColor(Design.Surfaces.bgSecondary)
                }

                Text("The recipient receives this message")
                    .zFont(size: 14, style: Design.Text.support)
                    .padding(.top, 16)

                Spacer()

                ZashiButton("Recipient taps the link") {
                    store.send(.proceedTapped)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .navigationBarBackButtonHidden(true)
        }
        .applyScreenBackground()
    }
}

// MARK: - Outside: Install App

struct PLOutsideInstallAppView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                // Mock App Store prompt
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: "z.square.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue)
                        }

                    Text("Zodl — Zcash Wallet")
                        .zFont(.semiBold, size: 20, style: Design.Text.primary)

                    Text("Private digital cash")
                        .zFont(size: 14, style: Design.Text.tertiary)

                    HStack(spacing: 4) {
                        ForEach(0..<5) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        }
                        Text("4.9")
                            .zFont(size: 12, style: Design.Text.tertiary)
                    }

                    ZashiButton("INSTALL", type: .brand, fontSize: 14) {
                        store.send(.proceedTapped)
                    }
                    .frame(width: 120)
                }
                .padding(32)
                .background {
                    RoundedRectangle(cornerRadius: Design.Radius._2xl)
                        .fill()
                        .zForegroundColor(Design.Surfaces.bgSecondary)
                }

                Text("Recipient doesn't have Zodl — installs it")
                    .zFont(size: 14, style: Design.Text.support)
                    .padding(.top, 16)

                Spacer()
            }
            .screenHorizontalPadding()
            .navigationBarBackButtonHidden(true)
        }
        .applyScreenBackground()
    }
}

// MARK: - Recipient: Claim

struct PLRecipientClaimView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "gift.fill")
                    .zImage(size: 48, style: Design.Surfaces.brandPrimary)

                Text("Someone sent you ZEC!")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 16)

                Text("\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                    .zFont(.bold, size: 32, style: Design.Text.primary)
                    .padding(.top, 12)

                Text("Finalize to sweep these funds into your wallet")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                ZashiButton("Finalize", type: .brand) {
                    store.send(.proceedTapped)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Claim Payment")
        }
        .applyScreenBackground()
    }
}
