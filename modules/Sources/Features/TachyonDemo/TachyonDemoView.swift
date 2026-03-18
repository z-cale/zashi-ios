import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

public struct TachyonDemoView: View {
    let store: StoreOf<TachyonDemo>

    public init(store: StoreOf<TachyonDemo>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            let screen = store.screenStack.last ?? .flowPicker
            let role = screen.role

            VStack(spacing: 0) {
                if let role {
                    RoleBanner(role: role)
                }

                screenView(for: screen)
            }
            .roleTint(role)
            .animation(.easeInOut(duration: 0.25), value: store.screenStack.count)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func screenView(for screen: TachyonDemo.State.Screen) -> some View {
        switch screen {
        case .flowPicker:
            FlowPickerView(store: store)

        case let .switchTo(perspective):
            PerspectiveSwitchView(store: store, perspective: perspective)

        // Flow 1: Payment Request
        case .prRecipientCreate:
            PRRecipientCreateView(store: store)
        case .prRecipientShowQR:
            PRRecipientShowQRView(store: store)
        case .prSenderConfirm:
            PRSenderConfirmView(store: store)
        case .prSenderProcessing:
            TachyonProcessingView(message: "Sending payment...")
        case .prRecipientReceived:
            TachyonSuccessView(
                store: store,
                title: "Payment Received!",
                subtitle: "\(store.amount.isEmpty ? "1.0" : store.amount) ZEC from anonymous sender"
            )

        // Flow 2A: Payment Link
        case .plSenderEnterAmount:
            PLSenderEnterAmountView(store: store)
        case .plSenderShare:
            PLSenderShareView(store: store)
        case .plSenderRevoking:
            TachyonProcessingView(message: "Revoking payment...")
        case .plSenderRevoked:
            TachyonSuccessView(
                store: store,
                title: "Payment Revoked",
                subtitle: "Funds swept back to your wallet. The link is now invalid."
            )
        case .plOutsideMessageReceived:
            PLOutsideMessageReceivedView(store: store)
        case .plOutsideInstallApp:
            PLOutsideInstallAppView(store: store)
        case .plOutsideFaceID:
            PLOutsideFaceIDView(store: store)
        case .plRecipientClaim:
            PLRecipientClaimView(store: store)
        case .plRecipientFinalizing:
            TachyonProcessingView(message: "Finalizing payment...")
        case .plRecipientDone:
            TachyonSuccessView(
                store: store,
                title: "Funds Claimed!",
                subtitle: "\(store.amount.isEmpty ? "1.0" : store.amount) ZEC added to your wallet"
            )

        // Flow 2B: Local Cash
        case .cashSenderEnterAmount:
            CashSenderEnterAmountView(store: store)
        case .cashSenderShowQR:
            CashSenderShowQRView(store: store)
        case .cashSenderRevoking:
            TachyonProcessingView(message: "Revoking payment...")
        case .cashSenderRevoked:
            TachyonSuccessView(
                store: store,
                title: "Payment Revoked",
                subtitle: "Funds swept back to your wallet. The QR is now invalid."
            )
        case .cashOutsideCameraScan:
            CashOutsideCameraScanView(store: store)
        case .cashOutsideInstallApp:
            CashOutsideInstallAppView(store: store)
        case .cashRecipientClaim:
            CashRecipientClaimView(store: store)
        case .cashRecipientFinalizing:
            TachyonProcessingView(message: "Finalizing payment...")
        case .cashRecipientDone:
            TachyonSuccessView(
                store: store,
                title: "Funds Claimed!",
                subtitle: "\(store.amount.isEmpty ? "1.0" : store.amount) ZEC added to your wallet"
            )

        // Flow 3: Public Payment
        case .ppRecipientRegister:
            PPRecipientRegisterView(store: store)
        case .ppRecipientRegistering:
            TachyonProcessingView(message: "Registering with relay...")
        case .ppRecipientShowURL:
            PPRecipientShowURLView(store: store)
        case .ppSenderEnterAmount:
            PPSenderEnterAmountView(store: store)
        case .ppSenderConfirm:
            PPSenderConfirmView(store: store)
        case .ppSenderProcessing:
            TachyonProcessingView(message: "Sending via relay...")
        case .ppRecipientCheckRelay:
            PPRecipientCheckRelayView(store: store)
        case .ppRecipientChecking:
            TachyonProcessingView(message: "Checking relay...")
        case .ppRecipientPaymentsArrived:
            PPRecipientPaymentsArrivedView(store: store)
        }
    }
}

// MARK: - Placeholder

extension TachyonDemo {
    public static let placeholder = StoreOf<TachyonDemo>(
        initialState: .initial
    ) {
        TachyonDemo()
    }
}

#Preview {
    NavigationStack {
        TachyonDemoView(store: TachyonDemo.placeholder)
    }
}
