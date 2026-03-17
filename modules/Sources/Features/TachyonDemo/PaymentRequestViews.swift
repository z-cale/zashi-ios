import SwiftUI
import ComposableArchitecture
import UIComponents

// MARK: - Recipient: Create Request

struct PRRecipientCreateView: View {
    @Perception.Bindable var store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                Text("Create Payment Request")
                    .font(.title3.weight(.semibold))

                TruncatedKeyView(label: "Your payment key:", key: MockData.recipientKey)

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
                    Text("Generate Request")
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
                    Text("Payment Request").font(.headline)
                }
            }
        }
    }
}

// MARK: - Recipient: Show QR

struct PRRecipientShowQRView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                TachyonQRCodeView(content: store.qrContent, size: 240)
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text("\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                    .font(.title2.weight(.bold))

                Text("Waiting for payment...")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    store.send(.simulateReceived)
                } label: {
                    Text("Simulate Payment Received")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
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
                    Text("Payment Request").font(.headline)
                }
            }
        }
    }
}

// MARK: - Sender: Scan

struct PRSenderScanView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(.secondary)
                    .frame(width: 240, height: 240)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Scan payment request QR")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                Spacer()

                Button {
                    store.send(.proceedTapped)
                } label: {
                    Text("Simulate Scan")
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
                    Text("Payment Request").font(.headline)
                }
            }
        }
    }
}

// MARK: - Sender: Confirm

struct PRSenderConfirmView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Text("Confirm Payment")
                        .font(.title3.weight(.semibold))

                    VStack(spacing: 12) {
                        confirmRow("To", value: MockData.recipientKey.truncated)
                        confirmRow("Amount", value: "\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                        confirmRow("Fee", value: "\(MockData.mockFee) ZEC")
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)

                Spacer()

                MockBalanceView()
                    .padding(.bottom, 12)

                Button {
                    store.send(.proceedTapped)
                } label: {
                    Text("Pay")
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
                    Text("Payment Request").font(.headline)
                }
            }
        }
    }

    private func confirmRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}
