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
            screenView(for: screen)
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

        case let .rolePicker(flow):
            RolePickerView(store: store, flow: flow)

        // Flow 1: Payment Request
        case .prRecipientCreate:
            PRRecipientCreateView(store: store)
        case .prRecipientShowQR:
            PRRecipientShowQRView(store: store)
        case .prSenderScan:
            PRSenderScanView(store: store)
        case .prSenderConfirm:
            PRSenderConfirmView(store: store)
        case .prSenderProcessing:
            TachyonProcessingView(message: "Sending payment...")
        case .prSenderDone:
            TachyonSuccessView(
                store: store,
                title: "Payment Sent!",
                subtitle: "The recipient will be notified."
            )
        case .prRecipientReceived:
            TachyonSuccessView(
                store: store,
                title: "Payment Received!",
                subtitle: "\(store.amount.isEmpty ? "1.0" : store.amount) ZEC from anonymous sender"
            )

        // Flow 2: Local Cash
        case .lcSenderEnterAmount:
            LCSenderEnterAmountView(store: store)
        case .lcSenderShowPayment:
            LCSenderShowPaymentView(store: store)
        case .lcRecipientClaim:
            LCRecipientClaimView(store: store)
        case .lcRecipientClaiming:
            TachyonProcessingView(message: "Claiming payment...")
        case .lcRecipientDone:
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
        case .ppSenderScan:
            PPSenderScanView(store: store)
        case .ppSenderEnterAmount:
            PPSenderEnterAmountView(store: store)
        case .ppSenderConfirm:
            PPSenderConfirmView(store: store)
        case .ppSenderProcessing:
            TachyonProcessingView(message: "Sending via relay...")
        case .ppSenderDone:
            TachyonSuccessView(
                store: store,
                title: "Payment Stored for Delivery",
                subtitle: "The relay will forward it when the recipient comes online."
            )
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
