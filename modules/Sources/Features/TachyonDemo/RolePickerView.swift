import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

struct RolePickerView: View {
    let store: StoreOf<TachyonDemo>
    let flow: TachyonDemo.State.Flow

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: flow.systemImage)
                    .zImage(size: 48, style: Design.Text.support)

                Text(flow.title)
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 16)

                Text(roleExplanation)
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    roleButton(.recipient)
                    roleButton(.sender)
                }
                .padding(.top, 24)

                Spacer()
                Spacer()
            }
            .screenHorizontalPadding()
            .zashiBack { store.send(.goBack) }
            .screenTitle(flow.title)
        }
        .applyScreenBackground()
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
            HStack(spacing: 12) {
                Image(systemName: role == .recipient ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .zImage(size: 24, style: Design.Text.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(role.title)
                        .zFont(.semiBold, size: 16, style: Design.Text.primary)

                    Text(roleSubtitle(role))
                        .zFont(size: 14, style: Design.Text.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .zImage(size: 12, style: Design.Text.quaternary)
            }
            .padding(16)
            .background { RoundedRectangle(cornerRadius: Design.Radius._xl).fill().zForegroundColor(Design.Surfaces.bgSecondary) }
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
