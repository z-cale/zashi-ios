import SwiftUI
import ComposableArchitecture
import UIComponents

// MARK: - Recipient: Register

struct PPRecipientRegisterView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Create Public Payment Address")
                    .font(.title3.weight(.semibold))

                Text("Register your payment key with a relay service. Anyone can send you payments by scanning the QR — even while you're offline.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                TruncatedKeyView(label: "Payment key:", key: MockData.recipientKey)

                Spacer()

                Button {
                    store.send(.registerWithRelay)
                } label: {
                    Text("Register with Relay")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
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
                    Text("Public Payment").font(.headline)
                }
            }
        }
    }
}

// MARK: - Recipient: Show URL

struct PPRecipientShowURLView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 20) {
                Spacer()

                ViaRelayBadge()

                Text("Your Public Payment Address")
                    .font(.title3.weight(.semibold))

                TachyonQRCodeView(content: store.relayURL, size: 220)
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(store.relayURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)

                Text("Post this anywhere. Anyone can scan and pay.")
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
                            Text("Share")
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
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
                ShareSheet(items: [store.relayURL]) {
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
                    Text("Public Payment").font(.headline)
                }
            }
        }
    }
}

// MARK: - Sender: Scan

struct PPSenderScanView: View {
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
                            Text("Scan public payment QR")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                ViaRelayBadge()

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
                    Text("Public Payment").font(.headline)
                }
            }
        }
    }
}

// MARK: - Sender: Enter Amount

struct PPSenderEnterAmountView: View {
    @Perception.Bindable var store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                ViaRelayBadge()

                Text("Send to Public Address")
                    .font(.title3.weight(.semibold))

                Text(TachyonURI.relayURL(relayId: MockData.relayId))
                    .font(.system(.caption, design: .monospaced))
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
                    Text("Continue")
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
                    Text("Public Payment").font(.headline)
                }
            }
        }
    }
}

// MARK: - Sender: Confirm

struct PPSenderConfirmView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Text("Confirm Payment")
                        .font(.title3.weight(.semibold))

                    ViaRelayBadge()

                    VStack(spacing: 12) {
                        confirmRow("Relay", value: MockData.relayBaseURL)
                        confirmRow("Amount", value: "\(store.amount.isEmpty ? "1.0" : store.amount) ZEC")
                        confirmRow("Fee", value: "\(MockData.mockFee) ZEC")
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("The relay will store your payment until the recipient comes online.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)

                Spacer()

                Button {
                    store.send(.proceedTapped)
                } label: {
                    Text("Send via Relay")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
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
                    Text("Public Payment").font(.headline)
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
                .lineLimit(1)
        }
    }
}

// MARK: - Recipient: Check Relay

struct PPRecipientCheckRelayView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Check for Payments")
                    .font(.title3.weight(.semibold))

                Text("Query the relay service for any payments sent to your public address while you were offline.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button {
                    store.send(.checkRelay)
                } label: {
                    Text("Check Relay")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
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
                    Text("Public Payment").font(.headline)
                }
            }
        }
    }
}

// MARK: - Recipient: Payments Arrived

struct PPRecipientPaymentsArrivedView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(store.receivedPayments.count) payments received")
                        .font(.title3.weight(.semibold))
                }
                .padding(.top, 24)

                ViaRelayBadge()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.receivedPayments) { payment in
                            paymentRow(payment)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                Button {
                    store.send(.backToFlowPicker)
                } label: {
                    Text("Done")
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
            .navigationBarBackButtonHidden(true)
        }
    }

    private func paymentRow(_ payment: MockPayment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("+\(payment.amount) ZEC")
                    .font(.body.weight(.semibold))
                Text(payment.senderLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(payment.timestamp, style: .relative)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
