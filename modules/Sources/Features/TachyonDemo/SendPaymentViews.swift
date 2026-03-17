import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

// MARK: - Sender: Enter Amount

struct LCSenderEnterAmountView: View {
    @Perception.Bindable var store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Text("Create Payment")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)

                Text("The recipient will claim this via link or QR")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    TextField("Amount (ZEC)", text: $store.amount.sending(\.amountChanged))
                        .keyboardType(.decimalPad)
                        .zFont(.semiBold, fontFamily: .robotoMono, size: 32, style: Design.Text.primary)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background { RoundedRectangle(cornerRadius: Design.Radius._xl).fill().zForegroundColor(Design.Surfaces.bgSecondary) }

                    MockBalanceView()
                }
                .padding(.top, 24)

                Spacer()

                ZashiButton("Create Payment") {
                    store.send(.proceedTapped)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Send Payment")
        }
        .applyScreenBackground()
    }
}

// MARK: - Sender: Show Payment (Local Cash)

struct LCSenderShowPaymentView: View {
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

                Text("Show this QR to the recipient, or share the link")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                VStack(spacing: 12) {
                    ZashiButton("Share Link", prefixView: Image(systemName: "square.and.arrow.up")) {
                        store.send(.sharePayment)
                    }

                    ZashiButton("Done", type: .ghost) {
                        store.send(.backToFlowPicker)
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
            .screenTitle("Local Cash")
        }
        .applyScreenBackground()
    }
}

// MARK: - Recipient: Claim

struct LCRecipientClaimView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "gift.fill")
                    .zImage(size: 48, style: Design.Surfaces.brandPrimary)

                Text("You received a payment!")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 16)

                Text("1.0 ZEC")
                    .zFont(.bold, size: 32, style: Design.Text.primary)
                    .padding(.top, 12)

                Text("Tap claim to add these funds to your wallet")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                ZashiButton("Claim", type: .brand) {
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

// MARK: - Share Sheet Bridge

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
