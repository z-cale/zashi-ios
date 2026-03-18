import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

// MARK: - Recipient: Register

struct PPRecipientRegisterView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Create Public Payment Address")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                Text("Register your payment key with a relay service. Anyone can send you payments by scanning the QR — even while you're offline.")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                TruncatedKeyView(label: "Payment key:", key: MockData.recipientKey)
                    .padding(.top, 16)

                Spacer()

                ZashiButton("Register with Relay") {
                    store.send(.registerWithRelay)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Public Payment")
        }
        .applyScreenBackground()
    }
}

// MARK: - Recipient: Show URL

struct PPRecipientShowURLView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                ViaRelayBadge()

                Text("Your Public Payment Address")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                TachyonQRCodeView(content: store.relayURL, size: 220)
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._2xl)
                            .fill(Color.white)
                    }
                    .padding(.top, 16)

                Text(store.relayURL)
                    .zFont(fontFamily: .robotoMono, size: 12, style: Design.Text.tertiary)
                    .padding(.top, 8)

                Text("Post this anywhere. Anyone can scan and pay.")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                VStack(spacing: 12) {
                    ZashiButton("Share", prefixView: Image(systemName: "square.and.arrow.up")) {
                        store.send(.sharePayment)
                    }

                    ZashiButton("Recipient goes offline", type: .secondary) {
                        store.send(.proceedTapped)
                    }
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .sheet(isPresented: .constant(store.isSharePresented)) {
                ShareSheet(items: [store.relayURL]) {
                    store.send(.shareFinished)
                }
            }
            .zashiBack { store.send(.goBack) }
            .screenTitle("Public Payment")
        }
        .applyScreenBackground()
    }
}

// MARK: - Sender: Enter Amount

struct PPSenderEnterAmountView: View {
    @Perception.Bindable var store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                ViaRelayBadge()

                Text("Send to Public Address")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 12)

                Text(TachyonURI.relayURL(relayId: MockData.relayId))
                    .zFont(fontFamily: .robotoMono, size: 12, style: Design.Text.tertiary)
                    .padding(.top, 4)

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

                ZashiButton("Continue") {
                    store.send(.proceedTapped)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Public Payment")
        }
        .applyScreenBackground()
    }
}

// MARK: - Sender: Confirm

struct PPSenderConfirmView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Text("Confirm Payment")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)

                ViaRelayBadge()
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    ConfirmRow(label: "Relay", value: MockData.relayBaseURL)
                    ConfirmRow(label: "Amount", value: "\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                    ConfirmRow(label: "Fee", value: "\(MockData.mockFee) ZEC")
                }
                .padding(16)
                .background { RoundedRectangle(cornerRadius: Design.Radius._xl).fill().zForegroundColor(Design.Surfaces.bgSecondary) }
                .padding(.top, 16)

                Text("The relay will store your payment until the recipient comes online.")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                Spacer()

                ZashiButton("Send via Relay") {
                    store.send(.proceedTapped)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Public Payment")
        }
        .applyScreenBackground()
    }
}

// MARK: - Recipient: Check Relay

struct PPRecipientCheckRelayView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Check for Payments")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 16)

                Text("Query the relay for payments sent to your public address while you were offline.")
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                ZashiButton("Check Relay") {
                    store.send(.checkRelay)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle("Public Payment")
        }
        .applyScreenBackground()
    }
}

// MARK: - Recipient: Payments Arrived

struct PPRecipientPaymentsArrivedView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text("\(store.receivedPayments.count) payments received")
                        .zFont(.semiBold, size: 20, style: Design.Text.primary)
                }
                .padding(.top, 24)

                ViaRelayBadge()
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.receivedPayments) { payment in
                            paymentRow(payment)
                        }
                    }
                    .padding(.top, 16)
                }

                Spacer()

                ZashiButton("Done") {
                    store.send(.backToFlowPicker)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .navigationBarBackButtonHidden(true)
        }
        .applyScreenBackground()
    }

    private func paymentRow(_ payment: MockPayment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("+\(payment.amount) ZEC")
                    .zFont(.semiBold, size: 16, style: Design.Text.primary)
                Text(payment.senderLabel)
                    .zFont(size: 14, style: Design.Text.tertiary)
            }

            Spacer()

            Text(payment.timestamp, style: .relative)
                .zFont(size: 12, style: Design.Text.quaternary)
        }
        .padding(12)
        .background { RoundedRectangle(cornerRadius: Design.Radius._lg).fill().zForegroundColor(Design.Surfaces.bgSecondary) }
    }
}
