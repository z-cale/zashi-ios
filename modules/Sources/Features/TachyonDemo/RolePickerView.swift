import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

struct RolePickerView: View {
    let store: StoreOf<TachyonDemo>
    let flow: TachyonDemo.State.Flow

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: flow.systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text(flow.title)
                    .font(.title2.weight(.bold))

                Text(roleExplanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    roleButton(.recipient)
                    roleButton(.sender)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        store.send(.goBack)
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(flow.title)
                        .font(.headline)
                }
            }
        }
    }

    private var roleExplanation: String {
        switch flow {
        case .paymentRequest:
            return "The recipient creates a payment request QR. The sender scans it and pays."
        case .uriEncapsulatedPayment:
            return "The sender creates a payment and shares it as a link or Local Cash QR. The recipient claims it."
        case .publicPayment:
            return "The recipient registers a public address with a relay. The sender pays to it. The recipient picks up payments later."
        }
    }

    private func roleButton(_ role: TachyonDemo.State.Role) -> some View {
        Button {
            store.send(.roleSelected(role))
        } label: {
            HStack {
                Image(systemName: role == .recipient ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(role.title)
                        .font(.body.weight(.semibold))

                    Text(roleSubtitle(role))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func roleSubtitle(_ role: TachyonDemo.State.Role) -> String {
        switch (flow, role) {
        case (.paymentRequest, .recipient): return "Create a request and show QR"
        case (.paymentRequest, .sender): return "Scan a request and pay"
        case (.uriEncapsulatedPayment, .recipient): return "Claim a payment from a link or QR"
        case (.uriEncapsulatedPayment, .sender): return "Create and share a payment"
        case (.publicPayment, .recipient): return "Register a public address"
        case (.publicPayment, .sender): return "Pay to a public address"
        }
    }
}
