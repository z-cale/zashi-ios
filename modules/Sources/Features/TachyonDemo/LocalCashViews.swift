import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

// MARK: - Sender: Enter Amount

struct CashSenderEnterAmountView: View {
    @Perception.Bindable var store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Text("Create Local Cash")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)

                Text("The recipient will scan this QR to receive funds")
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

                ZashiButton("Create") {
                    store.send(.proceedTapped)
                }
                .disabled(store.isOverBalance)
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Local Cash")
        }
        .applyScreenBackground()
    }
}

// MARK: - Sender: Show QR

struct CashSenderShowQRView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .foregroundStyle(Color.green)
                    Text("Local Cash")
                        .zFont(.semiBold, size: 24, style: Design.Text.primary)
                }

                TachyonQRCodeView(content: store.qrContent, size: 240)
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._2xl)
                            .fill(Color.white)
                    }
                    .padding(.top, 16)

                Text("\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 16)

                Text("Show this QR to the recipient — they scan it with their camera")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                VStack(spacing: 12) {
                    ZashiButton("Recipient scans this") {
                        store.send(.proceedTapped)
                    }

                    ZashiButton("Revoke Payment", type: .destructive1) {
                        store.send(.revokePayment)
                    }
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Local Cash")
        }
        .applyScreenBackground()
    }
}

// MARK: - Outside: Camera Scan

struct CashOutsideCameraScanView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                // Mock camera viewfinder
                ZStack {
                    RoundedRectangle(cornerRadius: Design.Radius._2xl)
                        .fill(Color.black.opacity(0.85))
                        .frame(width: 280, height: 280)

                    // Corner brackets
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 3)
                        .frame(width: 180, height: 180)

                    // Mock QR in center
                    TachyonQRCodeView(content: store.qrContent, size: 120)
                        .opacity(0.7)

                    // Camera label
                    VStack {
                        HStack {
                            Text("Camera")
                                .zFont(.medium, size: 12, color: .white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(16)
                    .frame(width: 280, height: 280)
                }

                Text("Recipient scans the QR with their camera app")
                    .zFont(size: 14, style: Design.Text.support)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                Spacer()

                ZashiButton("QR scanned — open Zodl") {
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

struct CashOutsideInstallAppView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    // Universal link banner
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "z.square.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.blue)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open in Zodl?")
                                .zFont(.semiBold, size: 16, style: Design.Text.primary)
                            Text("claim.zcash.co")
                                .zFont(size: 14, style: Design.Text.tertiary)
                        }

                        Spacer()

                        Text("Open")
                            .zFont(.semiBold, size: 14, color: .blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._xl)
                            .fill()
                            .zForegroundColor(Design.Surfaces.bgSecondary)
                    }
                }

                Text("If Zodl is installed, it opens directly.\nIf not, they're sent to the App Store first.")
                    .zFont(size: 14, style: Design.Text.support)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                Spacer()

                ZashiButton("Open Zodl with payment") {
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

// MARK: - Recipient: Claim

struct CashRecipientClaimView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .foregroundStyle(Color.green)
                    Text("Local Cash")
                        .zFont(.semiBold, size: 20, style: Design.Text.primary)
                }

                Text("Someone handed you digital cash!")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

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
