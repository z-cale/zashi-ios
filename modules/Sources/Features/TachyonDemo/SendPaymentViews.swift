import SwiftUI
import ComposableArchitecture
import UIComponents

// MARK: - Sender: Enter Amount

struct LCSenderEnterAmountView: View {
    @Perception.Bindable var store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                Text("Create Payment")
                    .font(.title3.weight(.semibold))

                Text("The recipient will claim this via link or QR")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    TextField("Amount (ZEC)", text: $store.amount.sending(\.amountChanged))
                        .keyboardType(.decimalPad)
                        .font(.system(.title, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    MockBalanceView()
                }
                .padding(.horizontal, 32)

                Spacer()

                Button {
                    store.send(.proceedTapped)
                } label: {
                    Text("Create Payment")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { store.send(.goBack) } label: {
                        Image(systemName: "chevron.left").foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Send Payment").font(.headline)
                }
            }
        }
    }
}

// MARK: - Sender: Show Payment (Local Cash)

struct LCSenderShowPaymentView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 20) {
                Spacer()

                // Local Cash branding
                HStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .foregroundStyle(.green)
                    Text("Local Cash")
                        .font(.title3.weight(.bold))
                }

                TachyonQRCodeView(content: store.qrContent, size: 240)
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text("\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                    .font(.title2.weight(.bold))

                Text("Show this QR to the recipient, or share the link")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        store.send(.sharePayment)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Link")
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        store.send(.backToFlowPicker)
                    } label: {
                        Text("Done")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: .constant(store.isSharePresented)) {
                ShareSheet(items: [store.qrContent]) {
                    store.send(.shareFinished)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { store.send(.goBack) } label: {
                        Image(systemName: "chevron.left").foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Local Cash").font(.headline)
                }
            }
        }
    }
}

// MARK: - Recipient: Claim

struct LCRecipientClaimView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "gift.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("You received a payment!")
                    .font(.title3.weight(.semibold))

                Text("1.0 ZEC")
                    .font(.title.weight(.bold))

                Text("Tap claim to add these funds to your wallet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button {
                    store.send(.proceedTapped)
                } label: {
                    Text("Claim")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { store.send(.goBack) } label: {
                        Image(systemName: "chevron.left").foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Claim Payment").font(.headline)
                }
            }
        }
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
