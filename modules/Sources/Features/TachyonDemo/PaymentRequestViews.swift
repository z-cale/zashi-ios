import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

// MARK: - Recipient: Create Request

struct PRRecipientCreateView: View {
    @Perception.Bindable var store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Text("Create Payment Request")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)

                TruncatedKeyView(label: "Your payment key:", key: MockData.recipientKey)
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    TextField("Amount (ZEC)", text: $store.amount.sending(\.amountChanged))
                        .keyboardType(.decimalPad)
                        .font(.custom(FontFamily.RobotoMono.semiBold.name, size: 32))
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background { RoundedRectangle(cornerRadius: Design.Radius._xl).fill().zForegroundColor(Design.Surfaces.bgSecondary) }

                    MockBalanceView()
                }
                .padding(.top, 24)

                Spacer()

                ZashiButton("Generate Request") {
                    store.send(.proceedTapped)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Payment Request")
        }
        .applyScreenBackground()
    }
}

// MARK: - Recipient: Show QR

struct PRRecipientShowQRView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                TachyonQRCodeView(content: store.qrContent, size: 240)
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._2xl)
                            .fill(Color.white)
                    }

                Text("\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 16)

                Text("Waiting for payment...")
                    .zFont(size: 14, style: Design.Text.support)
                    .padding(.top, 8)

                Spacer()

                ZashiButton("Sender scans this QR") {
                    store.send(.proceedTapped)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Payment Request")
        }
        .applyScreenBackground()
    }
}

// MARK: - Sender: Confirm

struct PRSenderConfirmView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Text("Confirm Payment")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)

                VStack(spacing: 12) {
                    ConfirmRow(label: "To", value: MockData.recipientKey.truncated)
                    ConfirmRow(label: "Amount", value: "\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                    ConfirmRow(label: "Fee", value: "\(MockData.mockFee) ZEC")
                }
                .padding(16)
                .background { RoundedRectangle(cornerRadius: Design.Radius._xl).fill().zForegroundColor(Design.Surfaces.bgSecondary) }
                .padding(.top, 24)

                Spacer()

                MockBalanceView()
                    .padding(.bottom, 12)

                ZashiButton("Pay") {
                    store.send(.proceedTapped)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Payment Request")
        }
        .applyScreenBackground()
    }
}
